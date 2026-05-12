#!/usr/bin/env python3
"""
shin_snr_print.py — disassemble and print a shin:: SNR script file.

Requires:
    pip install kaitaistruct

Generate the Python parser first:
    kaitai-struct-compiler -t python shin_snr.ksy
    # produces shin_snr.py in the current directory

Usage:
    python shin_snr_print.py <path/to/file.snr> [options]

Options:
    --no-assets       Skip the asset-table listing
    --no-bytecode     Skip the bytecode disassembly
    --decode-sjis     Convert half-width katakana in message strings to full-width
                      (matches the engine's sjis_half_width_to_full_width transform).
                      Without this flag the raw Shift-JIS bytes are shown as-is.
"""

import sys
import os

sys.path.insert(0, os.path.dirname(__file__))

from shin_snr import ShinSnr
from kaitaistruct import KaitaiStream, BytesIO

# =============================================================================
# Half-width katakana -> hiragana conversion
#
# The engine stores dialogue in Shift-JIS with kana encoded as single-byte
# half-width katakana (0xA0-0xDF) to save storage.  At display time it calls
# sjis_half_width_to_full_width(), which is a direct table lookup into the
# 64-entry ushort array `char_j` at 0x00133400.
#
# The table maps to HIRAGANA (0x82xx SJIS range), NOT to full-width katakana.
# 0xDE (ﾞ dakuten) -> '！' (0x8149) and 0xDF (ﾟ handakuten) -> '？' (0x8148).
# There is NO combining logic: each byte maps independently.
#
# We replicate the LUT exactly as read from the binary (big-endian SJIS ushorts
# at 0x00133400, confirmed from Ghidra listing).
# =============================================================================

# char_j LUT: index = (input_byte - 0xA0), value = SJIS ushort -> decoded char.
# Built by decoding each big-endian SJIS ushort to its Unicode character.
import struct as _struct

_CHAR_J_SJIS = [
    # 0xA0-0xA3
    0x8140, 0x8142, 0x8175, 0x8176,
    # 0xA4-0xA7
    0x8141, 0x8163, 0x82F0, 0x829F,
    # 0xA8-0xAB
    0x82A1, 0x82A3, 0x82A5, 0x82A7,
    # 0xAC-0xAF
    0x82E1, 0x82E3, 0x82E5, 0x82C1,
    # 0xB0-0xB3
    0x815B, 0x82A0, 0x82A2, 0x82A4,
    # 0xB4-0xB7
    0x82A6, 0x82A8, 0x82A9, 0x82AB,
    # 0xB8-0xBB
    0x82AD, 0x82AF, 0x82B1, 0x82B3,
    # 0xBC-0xBF
    0x82B5, 0x82B7, 0x82B9, 0x82BB,
    # 0xC0-0xC3
    0x82BD, 0x82BF, 0x82C2, 0x82C4,
    # 0xC4-0xC7
    0x82C6, 0x82C8, 0x82C9, 0x82CA,
    # 0xC8-0xCB
    0x82CB, 0x82CC, 0x82CD, 0x82D0,
    # 0xCC-0xCF
    0x82D3, 0x82D6, 0x82D9, 0x82DC,
    # 0xD0-0xD3
    0x82DD, 0x82DE, 0x82DF, 0x82E0,
    # 0xD4-0xD7
    0x82E2, 0x82E4, 0x82E6, 0x82E7,
    # 0xD8-0xDB
    0x82E8, 0x82E9, 0x82EA, 0x82EB,
    # 0xDC-0xDF
    0x82ED, 0x82F1, 0x8149, 0x8148,
]

# Decode the LUT to Unicode strings once at import time.
_CHAR_J: list[str] = [
    _struct.pack('>H', v).decode('shift-jis', errors='replace')
    for v in _CHAR_J_SJIS
]


def _expand_halfwidth_kana(raw_bytes: bytes) -> str:
    """
    Replicate sjis_half_width_to_full_width() on raw Shift-JIS bytes.

    Operates on the raw byte stream before SJIS decoding so we can intercept
    the half-width katakana bytes (0xA0-0xDF) individually.  All other bytes
    are passed through to a single SJIS decode at the end.

    Each half-width katakana byte is replaced in-place by its char_j LUT entry
    (a 2-byte SJIS hiragana sequence).  No combining logic exists in the engine.
    """
    out = bytearray()
    i = 0
    while i < len(raw_bytes):
        b = raw_bytes[i]
        if 0xA0 <= b <= 0xDF:
            # Direct LUT substitution: emit the 2-byte SJIS replacement
            out += _struct.pack('>H', _CHAR_J_SJIS[b - 0xA0])
            i += 1
        elif (0x81 <= b <= 0x9F) or (0xE0 <= b <= 0xFC):
            # Lead byte of a 2-byte SJIS sequence: copy both bytes verbatim
            out.append(b)
            if i + 1 < len(raw_bytes):
                i += 1
                out.append(raw_bytes[i])
            i += 1
        else:
            out.append(b)
            i += 1
    return bytes(out).decode('shift-jis', errors='replace')


# =============================================================================
# String helpers
# =============================================================================

# Set by main() based on --decode-sjis flag
_DECODE_SJIS: bool = False


def _strz(b) -> str:
    """Decode a null-padded/null-terminated byte field (asset names etc.)."""
    if isinstance(b, (bytes, bytearray)):
        raw = bytes(b).split(b'\x00')[0]
        return _expand_halfwidth_kana(raw) if _DECODE_SJIS else raw.decode('shift-jis', errors='replace')
    if isinstance(b, str):
        return b.split('\x00')[0]
    return str(b) if b is not None else ''


def _str_msg(b) -> str:
    """
    Decode a dialogue/message byte field (CMD_MSGGET, CMD_LOGSET, etc.).
    Applies half-width->hiragana expansion (char_j LUT) only when --decode-sjis
    is active; otherwise returns raw Shift-JIS decoded string.
    """
    if isinstance(b, (bytes, bytearray)):
        raw = bytes(b).rstrip(b'\x00')
        return _expand_halfwidth_kana(raw) if _DECODE_SJIS else raw.decode('shift-jis', errors='replace')
    if isinstance(b, str):
        return b.rstrip('\x00')
    return str(b) if b is not None else ''

def _choices_str(b) -> str:
    """Decode a null-delimited choices blob, separating entries with ' | '."""
    return _str_msg(b).replace('\x00', ' | ').strip(' | ')


# =============================================================================
# Formatting helpers
# =============================================================================

def _vol(raw: int) -> str:
    if isinstance(raw, int):
      return f"{raw / 255 * 100:.1f}%"
    else:
      return f"NaN"

def fmt_operand(op) -> str:
    # 1. Handle the Kaitai 'operand' type
    if hasattr(op, 'is_var'):
        if op.is_var:
            return f"v{op.var_idx}"
        return f"{op.value}"
        
    # 2. If it's already a string (like a pre-formatted asset name), return it
    if isinstance(op, str):
        return op
        
    # 3. Fallback for raw integers
    if isinstance(op, int):
        try:
            # Cast to signed 16-bit to identify variables vs constants
            val = op if op < 0x8000 else op - 0x10000
            if val < -0x4000:
                return f"v{val + 0x8000}"
            return f"{val}"
        except Exception:
            return str(op)
# =============================================================================
# Asset name lookups (safe: return placeholder on out-of-range)
# =============================================================================

def _bgm_name(snr: ShinSnr, idx: int) -> str:
    sec = snr.bgm_section
    if idx < sec.num_records:
        r     = sec.records[idx]
        title = _strz(r.title)
        fn    = _strz(r.filename)
        return f'"{title}" ({fn})' if title else fn
    return f"bgm#{idx}"

def _sebg_name(snr: ShinSnr, idx: int) -> str:
    sec = snr.se_bg_section
    return _strz(sec.records[idx].name) if idx < sec.num_records else f"se#{idx}"

def _voice_name(snr: ShinSnr, idx: int) -> str:
    sec = snr.voice_section
    return _strz(sec.records[idx].filename) if idx < sec.num_records else f"voice#{idx}"

def _movie_name(snr: ShinSnr, idx: int) -> str:
    sec = snr.movie_section
    return _strz(sec.records[idx].name) if idx < sec.num_records else f"movie#{idx}"

def _mask_name(snr: ShinSnr, idx: int) -> str:
    if isinstance(idx, int):
      sec = snr.mask_section
      return _strz(sec.records[idx].name) if idx < sec.num_records else f"mask#{idx}"
    else: 
      return idx

def fmt_mask(snr: ShinSnr, idx: int) -> str:
    if idx.value > -0x4000:
      idx = idx.value
      sec = snr.mask_section
      return _strz(sec.records[idx].name) if idx < sec.num_records else f"mask#{idx}"
    else: 
      return fmt_operand(idx)

def _pic_name(snr: ShinSnr, idx: int) -> str:
    sec = snr.pic_section
    return _strz(sec.records[idx].name) if idx < sec.num_records else f"pic#{idx}"

def _bustup_str(snr: ShinSnr, idx: int) -> str:
    sec = snr.bustup_section
    if idx < sec.num_records:
        r = sec.records[idx]
        return f"{_strz(r.name)}/{_strz(r.emotion)}"
    return f"bustup#{idx}"

def _anime_name(snr: ShinSnr, idx: int) -> str:
    sec = snr.anime_section
    return _strz(sec.records[idx].name) if idx < sec.num_records else f"anime#{idx}"

_LAYER_TYPE_NAMES = {1:"TILE", 2:"PICTURE", 3:"BUSTUP", 4:"ANIME", 5:"RAIN", 6:"EFFECT"}

def fmt_anim_type(op) -> str:
    """Format an anim_type operand: show the enum name when it's a constant."""
    if hasattr(op, 'is_var') and op.is_var:
        return f"v{op.var_idx}"
    try:
        return op.value_anim_type.name
    except Exception:
        return fmt_operand(op)

def fmt_wait_anim_type(op) -> str:
    """Format a wait anim_type operand using the layer_wait_anim_type enum."""
    if hasattr(op, 'is_var') and op.is_var:
        return f"v{op.var_idx}"
    try:
        return op.value_layer_wait_anim_type.name
    except Exception:
        return fmt_operand(op)

def decode_decimal_rgba(encoded_int :int) -> tuple[int, int, int, int]:
    s = f"{encoded_int:04d}"
    rgba = [round((int(digit) / 9) * 255) for digit in s]
    return tuple(rgba)


def _layer_asset(snr: ShinSnr, lt: int, asset_id: int) -> str:
    if lt == 1: return f"RGBA = {decode_decimal_rgba(asset_id)}"
    if lt == 2: return _pic_name(snr, asset_id)
    if lt == 3: return _bustup_str(snr, asset_id)
    if lt == 4: return _anime_name(snr, asset_id)
    return f"asset#{asset_id}"


# =============================================================================
# Instruction formatter
# =============================================================================

def fmt_instruction(snr: ShinSnr, instr) -> str:
    oc = instr.opcode
    if hasattr(oc, 'name'):
        name   = oc.name.upper()
        oc_val = oc.value
    else:
        name   = f"UNK_{int(oc):#04x}"
        oc_val = int(oc)

    # No-payload opcodes: Kaitai does not create a `payload` attribute for
    # empty switch branches (RET, all scriptTrue stubs, MSGSIGNAL, MSGCLOSE,
    # WIPEWAIT, LAYERCLEAR, CANVASINIT, SCREENINIT, EVBEGIN, EVEND, AUTOSAVE).
    p = getattr(instr, 'payload', None)
    if p is None:
        return name

    # ── Logic / Memory ────────────────────────────────────────────────────────
    if oc == ShinSnr.OpCode.op_unary:
        op1 = f"  op1={fmt_operand(p.op1)}" if p.mode >= 0x80 else ""
        return f"{name}  mode={p.mode:#04x}  op1={fmt_operand(p.op1)}{op1}"

    if oc == ShinSnr.OpCode.op_alu:
        dst = fmt_operand(p.dst_var)
        
        # CLR operation
        if p.base_op == 1:
          return f"{name}  {dst} = 0"

        # Map operation codes to symbols
        op_chars = {
          0: "=", 2: "+", 3: "-", 4: "*", 5: "/", 6: "%",
          7: "&", 8: "|", 9: "^", 10: "<<", 11: ">>"
        }
        op_str = op_chars.get(p.base_op, f"?{p.base_op}?")

        op1 = fmt_operand(p.op1)

        if p.is_ternary:
          op2 = fmt_operand(p.op2)
          if p.base_op == 0:
            return f"{name}  {dst} = {op1}  (unused: {op2})"
          return f"{name}  {dst} = {op1} {op_str} {op2}"
        else:
          if p.base_op == 0: # direct assignment
            return f"{name}  {dst} = {op1}"
          return f"{name}  {dst} {op_str}= {op1}"

    if oc == ShinSnr.OpCode.op_stack:
        ops_str = " ".join(
            (f"PUSH {fmt_operand(op.operand)}" if op.op_code == 0 else f"OP({op.op_code})")
            for op in p.ops
        )
        return f"{name}  dst={fmt_operand(p.dst_var)}  [{ops_str}]"

    if oc == ShinSnr.OpCode.set_vars_mult_range:
        idx_s = ", ".join(fmt_operand(v) for v in p.var_idx)
        return f"{name}  value={fmt_operand(p.value_src)}  vars=[{idx_s}]"

    if oc == ShinSnr.OpCode.set_var_from_array:
        tbl = ", ".join(fmt_operand(v) for v in p.table_data)
        return f"{name}  dst={fmt_operand(p.dst_var)}  idx={fmt_operand(p.index_src)}  table=[{tbl}]"

    if oc == ShinSnr.OpCode.set_vars_mult_array:
        tbl = ", ".join(fmt_operand(v) for v in p.var_index_table)
        return f"{name}  value={fmt_operand(p.value_src)}  idx={fmt_operand(p.index_src)}  vars=[{tbl}]"

    # ── Flow Control ──────────────────────────────────────────────────────────
    if oc == ShinSnr.OpCode.jmp_cond:
      op1 = fmt_operand(p.op1)
      op2 = fmt_operand(p.op2)
      base_op = p.mode & 0x7f
      is_inverted = p.mode >= 0x80
  
      # Map C++ logic switch to comparison operators
      op_chars = {
        0: "==",
        1: "!=",
        2: ">=",
        3: ">",
        4: "<=",
        5: "<"
      }
  
      if base_op == 6:
        cond_str = f"({op1} & {op2}) != 0"
      else:
        comp = op_chars.get(base_op, f"?{base_op}?")
        cond_str = f"{op1} {comp} {op2}"
  
      # Bit 7 inverts the final condition result
      if is_inverted:
        cond_str = f"!({cond_str})"
  
      return f"{name}  if {cond_str} -> {p.target_addr:#010x}"
  
    if oc in (ShinSnr.OpCode.jmp_abs, ShinSnr.OpCode.call):
        return f"{name}  -> {p.target_addr:#010x}"
  
    if oc in (ShinSnr.OpCode.switch, ShinSnr.OpCode.switch_call):
        entries = "  ".join(f"[{i}]->{e:#010x}" for i, e in enumerate(p.entries))
        return f"{name}  idx={fmt_operand(p.index_src)}  {entries}"
  
    # ── Utilities ─────────────────────────────────────────────────────────────
    if oc == ShinSnr.OpCode.rand_range:
        return f"{name}  dst={fmt_operand(p.dst_var)}  range=[{fmt_operand(p.op1)}, {fmt_operand(p.op2)}]"

    if oc == ShinSnr.OpCode.push_mult:
        ops = ", ".join(fmt_operand(v) for v in p.operands)
        return f"{name}  [{ops}]"

    if oc == ShinSnr.OpCode.pop_mult:
        vs = ", ".join(fmt_operand(v) for v in p.var_idx)
        return f"{name}  [{vs}]"

    # ── System / Message / Scene ──────────────────────────────────────────────
    if oc == ShinSnr.OpCode.cmd_exit:
        return f"{name}  code={fmt_operand(p.exit_code_src)}"

    if oc == ShinSnr.OpCode.cmd_sget:
        # dst_var_raw is always a variable reference; apply the same encodeVariableRef
        # bias (+0x8000) that the engine uses so we display it as v<idx>.
        dst = f"v{p.dst_var_raw + 0x8000}"
        return f"{name}  dst={dst}  flag={fmt_operand(p.flag_id_src)}"

    if oc == ShinSnr.OpCode.cmd_sset:
        return f"{name}  value={fmt_operand(p.value_src)}  flag={fmt_operand(p.flag_id_src)}"

    if oc == ShinSnr.OpCode.cmd_wait:
        return f"{name}  duration={fmt_operand(p.duration_src)}"

    if oc == ShinSnr.OpCode.cmd_waitkey:
        return f"{name}  mode={fmt_operand(p.mode_src)}"

    if oc == ShinSnr.OpCode.cmd_msginit:
        return f"{name}  window_type={fmt_operand(p.window_type_src)}  justify={fmt_operand(p.justify_src)}"

    if oc == ShinSnr.OpCode.cmd_msgget:
        text = _str_msg(p.message_str) if p.len_message_str else ""
        aa   = "  [bool1]" if p.bool1 else ""
        return f'{name}  flag_base={p.base_flag_idx}{aa}  "{text}"'

    if oc == ShinSnr.OpCode.cmd_msgwait:
        return f"{name}  mode={fmt_operand(p.mode_src)}"

    if oc == ShinSnr.OpCode.cmd_msgcheck:
        return f"{name}  flag_base={p.base_flag_idx}"

    if oc == ShinSnr.OpCode.cmd_logset:
        return f'{name}  "{_str_msg(p.log_str)}"'

    if oc == ShinSnr.OpCode.cmd_select:
        title   = _str_msg(p.title_str) if p.len_title_str else ""
        choices = _choices_str(p.choices) if p.len_choices else ""
        vm = p.visibility_bitmask
        visible = f"{vm.value:#06x}" if not vm.is_var else fmt_operand(vm)
        return (f'{name}  flag_base={p.choice_base_flag_idc}'
                f'  flag_id=v{p.flag_base_raw}  dst={fmt_operand(p.script_var_num)}'
                f'  visible={visible}'
                f'  title="{title}"  choices=[{choices}]')

    if oc == ShinSnr.OpCode.cmd_wipe:
        parts = [f"bitmask={p.bitmask:#04x}"]
        if p.bitmask & 0x01: parts.append(f"mask={fmt_mask(snr, p.mask_snr_id)}")
        if p.bitmask & 0x02: parts.append(f"duration={fmt_operand(p.duration_ticks)}")
        if p.bitmask & 0x04: parts.append(f"height={fmt_operand(p.wipe_height)}")
        if p.bitmask & 0x08: parts.append(f"dir={fmt_operand(p.direction_flags)}")
        if p.wait_for_completion: parts.append("[wait]")
        return f"{name}  " + "  ".join(parts)

    # ── Audio ─────────────────────────────────────────────────────────────────
    if oc == ShinSnr.OpCode.cmd_bgmplay:
        return (f"{name}  [{fmt_operand(p.song_id)}] {_bgm_name(snr, p.song_id.value)}"
                f"  loop={fmt_operand(p.loop_num_records)}  vol={_vol(p.volume_raw.value)}"
                f"  fade={fmt_operand(p.fade_duration)}")

    if oc == ShinSnr.OpCode.cmd_bgmstop:
        return f"{name}  fade={fmt_operand(p.fade_duration)}"

    if oc == ShinSnr.OpCode.cmd_bgmvol:
        return f"{name}  vol={_vol(p.volume_raw.value)}  fade={fmt_operand(p.fade_duration)}"


    if oc == ShinSnr.OpCode.cmd_bgmwait:
        return f"{name}  duration={fmt_operand(p.duration_src)}"

    if oc == ShinSnr.OpCode.cmd_seplay:
        return (f"{name}  stream={fmt_operand(p.stream_id)}  [{fmt_operand(p.se_id)}] {_sebg_name(snr, p.se_id.value)}"
                f"  loop={fmt_operand(p.loop_num_records)}  vol={_vol(p.volume_raw.value)}"
                f"  fade={fmt_operand(p.fade_duration)}")

    if oc == ShinSnr.OpCode.cmd_sestop:
        return f"{name}  stream={fmt_operand(p.stream_id)} fade={fmt_operand(p.fade_duration)}"

    if oc == ShinSnr.OpCode.cmd_sestopall:
        return f"{name}  fade={fmt_operand(p.fade_duration)}"

    if oc == ShinSnr.OpCode.cmd_sevol:
        return f"{name}  stream={fmt_operand(p.stream_id)}  vol={_vol(p.volume_raw.value)}  fade={fmt_operand(p.fade_duration)}"

    if oc == ShinSnr.OpCode.cmd_sewait:
        return f"{name}  stream={fmt_operand(p.stream_id)}  preload={fmt_operand(p.do_preload)}"

    if oc == ShinSnr.OpCode.cmd_seonce:
        return (f"{name}  [{fmt_operand(p.sound_effect_id)}] {_sebg_name(snr, p.sound_effect_id.value)}"
                f"  vol={_vol(p.volume_raw.value)}  preload={fmt_operand(p.do_preload)}")

    if oc == ShinSnr.OpCode.cmd_vibrate:
        return f"{name}  intensity={fmt_operand(p.vibration_intensity)}  ticks={fmt_operand(p.duration_ticks)}"

    # ── Misc ──────────────────────────────────────────────────────────────────
    if oc == ShinSnr.OpCode.cmd_saveinfo:
        return f'{name}  type={p.type}  "{_str_msg(p.saveinfo_str)}"'

    if oc == ShinSnr.OpCode.cmd_movie:
        return f"{name}  [{p.movie_id}] {_movie_name(snr, p.movie_id)}"

    if oc == ShinSnr.OpCode.cmd_bgmsync:
        return f"{name}  threshold={p.threshold_duration}"

    if oc == ShinSnr.OpCode.cmd_bgmplay2:
        return (f"{name}  new=[{p.new_song_id}] {_bgm_name(snr, p.new_song_id)}"
                f"  old=[{p.old_song_id}] {_bgm_name(snr, p.old_song_id)}"
                f"  loop={fmt_operand(p.loop_num_records)}  vol={_vol(p.volume_raw)}"
                f"  crossfade={p.crossfade_delay}")

    if oc == ShinSnr.OpCode.cmd_bgmvol2:
        return f"{name}  vol={_vol(p.volume_raw.value)}  fade={fmt_operand(p.fade_duration)}"

    if oc == ShinSnr.OpCode.cmd_voiceplay:
        return (f"{name}  stream={p.stream_id}  [{p.voice_id}] {_voice_name(snr, p.voice_id)}"
                f"  loop={fmt_operand(p.loop_num_records)}  vol={_vol(p.volume_raw)}"
                f"  fade={p.fade_duration}")

    if oc == ShinSnr.OpCode.cmd_voicewait:
        return f"{name}  wait_flags={p.wait_flags.value:#06x}"

    if oc == ShinSnr.OpCode.cmd_tipsget:
        ids = ", ".join(str(fmt_operand(v)) for v in p.operands)
        return f"{name} .num_operands={p.num_operands}  ids=[{ids}]"

    # ── Layer / Canvas / Screen ───────────────────────────────────────────────
    if oc == ShinSnr.OpCode.cmd_thropy:
        return f"{name}  id={fmt_operand(p.thropy_id)}"

    if oc == ShinSnr.OpCode.cmd_char:
        return f"{name}  num_entries={fmt_operand(p.num_entries)}  op={fmt_operand(p.unnamed_operand)}"

    if oc == ShinSnr.OpCode.cmd_layerload:
        lt_val = p.layer_type.value_layer_type if hasattr(p.layer_type, 'value_layer_type') else int(p.layer_type)
        lt_str = _LAYER_TYPE_NAMES.get(lt_val, f"type={lt_val}")
        parts  = [f"layer={fmt_operand(p.layer_id)}", lt_str, f"field_mask={p.field_mask:#04x}"]
        if p.field_mask & 0x01:
            parts.append(f"asset=[{fmt_operand(p.asset_id)}] {_layer_asset(snr, lt_val, p.asset_id.value)}")
        if p.field_mask & 0x02: parts.append(f"paramb={fmt_operand(p.paramb)}")
        if p.field_mask & 0x04: parts.append(f"w={fmt_operand(p.width)}")
        if p.field_mask & 0x08: parts.append(f"h={fmt_operand(p.height)}")
        if p.field_mask & 0x10: parts.append(f"x={fmt_operand(p.x)}")
        if p.field_mask & 0x20: parts.append(f"y={fmt_operand(p.y)}")
        if p.field_mask & 0x40: parts.append(f"paramc={fmt_operand(p.paramc)}")
        if p.field_mask & 0x80: parts.append(f"paramd={fmt_operand(p.paramd)}")
        return f"{name}  " + "  ".join(parts)

    if oc == ShinSnr.OpCode.cmd_layerctrl:
        parts = [f"layer={fmt_operand(p.layer_id)}", f"anim={fmt_anim_type(p.anim_type)}", f"mask={p.field_mask:#04x}"]
        for i, (bit, attr) in enumerate([
                (0x01,'end_value'),(0x02,'duration_or_step'),(0x04,'mode_and_easing'),(0x08,'height'),
                (0x10,'x'),(0x20,'y'),(0x40,'paramc'),(0x80,'paramd')]):
            if p.field_mask & bit:
                parts.append(f"{attr}={fmt_operand(getattr(p, attr))}")
        return f"{name}  " + "  ".join(parts)

    if oc == ShinSnr.OpCode.cmd_layerwait:
        return f"{name}  layer={fmt_operand(p.layer_id)}  anim_type={fmt_wait_anim_type(p.anim_type)}"

    if oc == ShinSnr.OpCode.cmd_maskload:
        return f"{name}  [{fmt_operand(p.mask_id)}] {_mask_name(snr, p.mask_id.value)}  bool1={fmt_operand(p.bool1)}"

    if oc == ShinSnr.OpCode.cmd_canvas:
        return f"{name}  canvas_id={fmt_operand(p.canvas_id)}"

    if oc == ShinSnr.OpCode.cmd_canvasctrl:
        parts = [f"anim={fmt_anim_type(p.anim_type)}", f"mask={p.field_mask:#04x}"]
        for i, (bit, attr) in enumerate([
                (0x01,'param0'),(0x02,'param1'),(0x04,'param2'),(0x08,'param3'),
                (0x10,'param4'),(0x20,'param5'),(0x40,'param6'),(0x80,'param7')]):
            if p.field_mask & bit:
                parts.append(f"p{i}={fmt_operand(getattr(p, attr))}")
        return f"{name}  " + "  ".join(parts)

    if oc == ShinSnr.OpCode.cmd_canvaswait:
        return f"{name}  anim={fmt_wait_anim_type(p.anim_type)}"

    if oc == ShinSnr.OpCode.cmd_screenctr:
        parts = [f"anim={fmt_anim_type(p.anim_type)}", f"mask={p.field_mask:#04x}"]
        for i, (bit, attr) in enumerate([
                (0x01,'param0'),(0x02,'param1'),(0x04,'param2'),(0x08,'param3'),
                (0x10,'param4'),(0x20,'param5'),(0x40,'param6'),(0x80,'param7')]):
            if p.field_mask & bit:
                parts.append(f"p{i}={fmt_operand(getattr(p, attr))}")
        return f"{name}  " + "  ".join(parts)

    if oc == ShinSnr.OpCode.cmd_screenwait:
        return f"{name}  anim={fmt_wait_anim_type(p.anim_type)}"

    # ── Debug / Utility ───────────────────────────────────────────────────────
    if oc == ShinSnr.OpCode.cmd_msgbox:
        return f'{name}  "{_str_msg(p.message)}"'

    if oc == ShinSnr.OpCode.cmd_snapshot:
        return f'{name}  "{_strz(p.filename_base)}"  index={fmt_operand(p.index)}'

    # Fallback
    return f"{name}  (payload={type(p).__name__}  opcode={oc_val:#04x})"


# =============================================================================
# Asset table printer
# =============================================================================

def print_asset_tables(snr: ShinSnr) -> None:
    def section(title: str):
        print(f"\n{'─'*60}")
        print(f"  {title}")
        print(f"{'─'*60}")

    section("BGM")
    for i, r in enumerate(snr.bgm_section.records):
        print(f"  [{i:4d}]  {_strz(r.filename):<14}  {_strz(r.title)}")

    section("SE / Background Sound")
    for i, r in enumerate(snr.se_bg_section.records):
        print(f"  [{i:4d}]  {_strz(r.name)}")

    section("Voice")
    for i, r in enumerate(snr.voice_section.records):
        print(f"  [{i:4d}]  {_strz(r.filename)}")

    section("Movie")
    for i, r in enumerate(snr.movie_section.records):
        print(f"  [{i:4d}]  {_strz(r.name)}")

    section("Mask")
    for i, r in enumerate(snr.mask_section.records):
        print(f"  [{i:4d}]  {_strz(r.name)}")

    section("Picture")
    for i, r in enumerate(snr.pic_section.records):
        print(f"  [{i:4d}]  {_strz(r.name)}", end="")
        next_id = r.next_id
        while next_id != -1:
            next = snr.pic_section.records[next_id]
            print(f" --> [{next_id:4d}] {_strz(next.name)}", end="")
            next_id = next.next_id
        print("")

    section("Bustup")
    for i, r in enumerate(snr.bustup_section.records):
        print(f"[{i:4d}]  {_strz(r.name):<26}  emotion={_strz(r.emotion)}")

    section("Anime")
    for i, r in enumerate(snr.anime_section.records):
        print(f"  [{i:4d}]  {_strz(r.name)}")

    section("Picturebox")
    for i, r in enumerate(snr.picturebox_section.pages):
        pics = "  ".join(f"[{v}] {_pic_name(snr, v)}" for v in r.values)
        print(f"  [page {i:3d}]  type={r.type}  {pics}")


# =============================================================================
# Main
# =============================================================================

def main():
    global _DECODE_SJIS

    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    path          = sys.argv[1]
    show_assets   = "--no-assets"   not in sys.argv
    show_bytecode = "--no-bytecode" not in sys.argv
    _DECODE_SJIS  = "--decode-sjis" in sys.argv

    with open(path, 'rb') as fh:
        data = fh.read()

    snr = ShinSnr.from_bytes(data)

    print(f"SNR file      : {path}  ({len(data)} bytes)")
    print(f"bytecode off  : {snr.header.off_bytecode:#010x}")
    print(f"sjis decode   : {'on (half-width kana expanded)' if _DECODE_SJIS else 'off (raw)'}")
    print(f"BGM tracks    : {snr.bgm_section.num_records}")
    print(f"SE/bg sounds  : {snr.se_bg_section.num_records}")
    print(f"Voice clips   : {snr.voice_section.num_records}")
    print(f"Movies        : {snr.movie_section.num_records}")
    print(f"Masks         : {snr.mask_section.num_records}")
    print(f"Pictures      : {snr.pic_section.num_records}")
    print(f"Bustup sprites: {snr.bustup_section.num_records}")
    print(f"Anime clips   : {snr.anime_section.num_records}")
    print(f"Picturebox pgs: {snr.picturebox_section.num_pages}")

    if show_assets:
        print_asset_tables(snr)

    if not show_bytecode:
        return

    print(f"\n{'='*72}")
    print("  BYTECODE")
    print(f"{'='*72}")

    # Address tracking strategy:
    # The already-parsed instruction objects share the single _io stream of
    # the parent bytecode_stream, so _io.pos() on any of them only gives us
    # the end-of-file position after full parse.  Instead we walk a second
    # KaitaiStream in lockstep: record pos() BEFORE re-parsing each instruction
    # to get its true start address, then let the re-parse advance the cursor.
    # This is O(n) and parses the bytecode exactly twice.

    stream = KaitaiStream(BytesIO(data))
    stream.seek(snr.header.off_bytecode)

    for i, instr in enumerate(snr.bytecode.instructions):
        addr = stream.pos()

        try:
            ShinSnr.Instruction(stream, snr.bytecode, snr)
        except Exception:
            pass  # EOF on tracking stream; addr is still valid for this instr

        try:
            line = fmt_instruction(snr, instr)
        except Exception as ex:
            exc_type, exc_obj, exc_tb = sys.exc_info()
            fname = os.path.split(exc_tb.tb_frame.f_code.co_filename)[1]
            line = f"<ERROR: {ex} {exc_type}, {fname}, {exc_tb.tb_lineno})"

        print(f"  {i:6d}  [{addr:#010x}]  {line}")

    print()


if __name__ == "__main__":
    main()
