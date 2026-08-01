#!/usr/bin/env python3
"""
shin_snr_print.py — disassemble and print a shin:: SNR script file.

Handles BOTH format variants:
    * Umineko no Naku Koro ni Chiru PS3   (14 section slots, header 0x58)
    * Higurashi no Naku Koro ni Sui PS3   (12 section slots, header 0x50)

The variant is detected from the header (off_mask == 0x50 -> Higurashi);
there is no version field in the file — see the doc block in shin_snr.ksy.

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
# Version helpers
# =============================================================================

def is_higu(snr: ShinSnr) -> bool:
    return bool(snr.is_higurashi)


def _enum_name(v):
    """Return the enum member name if `v` resolved to an enum, else None."""
    return v.name if hasattr(v, 'name') else None


# Higurashi opcode names that mean the same thing as a differently-named
# Umineko opcode.  Dispatch below uses the Umineko (canonical) spelling; the
# printed mnemonic always uses the game's own name.
_HIGU_CANON = {
    'CMD_MSGSET':  'CMD_MSGGET',
    'CMD_KEYWAIT': 'CMD_WAITKEY',
    'CMD_TROPHY':  'CMD_THROPY',
}


def opcode_names(snr: ShinSnr, instr):
    """
    Return (display_name, canonical_mnemonic) for an instruction.

    display_name is the game's own opcode name (or UNK_0xNN for a stub slot);
    canonical_mnemonic is what fmt_instruction dispatches on.
    """
    oc = instr.op_higu if is_higu(snr) else instr.op_umi
    nm = _enum_name(oc)
    if nm is None:
        disp = f"UNK_{int(instr.opcode):#04x}"
        return disp, disp
    disp = nm.upper()
    return disp, (_HIGU_CANON.get(disp, disp) if is_higu(snr) else disp)


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
    if sec is None:
        return f"anime#{idx}"
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


def _layer_type_val(op):
    """Coerce a layer_type operand to a plain int (compiler versions differ)."""
    raw = op.value_layer_type if hasattr(op, 'value_layer_type') else op
    return raw.value if hasattr(raw, 'value') else int(raw)


# =============================================================================
# Instruction formatter
# =============================================================================

def fmt_instruction(snr: ShinSnr, instr) -> str:
    name, mn = opcode_names(snr, instr)
    higu = is_higu(snr)

    # No-payload opcodes: Kaitai does not create a `payload` attribute for
    # empty switch branches (RET, all scriptTrue stubs, MSGSIGNAL, MSGCLOSE,
    # WIPEWAIT, LAYERCLEAR, CANVASINIT, SCREENINIT, EVBEGIN(umi), EVEND,
    # AUTOSAVE, KAKERA, FAKESELECT).
    p = getattr(instr, 'payload', None)
    if p is None:
        return name

    # ── Logic / Memory ────────────────────────────────────────────────────────
    if mn == 'OP_UNARY':
        op1 = f"  op1={fmt_operand(p.op1)}" if p.mode >= 0x80 else ""
        return f"{name}  mode={p.mode:#04x}  op1={fmt_operand(p.op1)}{op1}"

    if mn == 'OP_ALU':
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

    if mn == 'OP_STACK':
        ops_str = " ".join(
            (f"PUSH {fmt_operand(op.operand)}" if op.op_code == 0 else f"OP({op.op_code})")
            for op in p.ops
        )
        return f"{name}  dst={fmt_operand(p.dst_var)}  [{ops_str}]"

    if mn == 'SET_VARS_MULT_RANGE':
        idx_s = ", ".join(fmt_operand(v) for v in p.var_idx)
        return f"{name}  value={fmt_operand(p.value_src)}  vars=[{idx_s}]"

    if mn == 'SET_VAR_FROM_ARRAY':
        tbl = ", ".join(fmt_operand(v) for v in p.table_data)
        return f"{name}  dst={fmt_operand(p.dst_var)}  idx={fmt_operand(p.index_src)}  table=[{tbl}]"

    if mn == 'SET_VARS_MULT_ARRAY':
        tbl = ", ".join(fmt_operand(v) for v in p.var_index_table)
        return f"{name}  value={fmt_operand(p.value_src)}  idx={fmt_operand(p.index_src)}  vars=[{tbl}]"

    # ── Flow Control ──────────────────────────────────────────────────────────
    if mn == 'JMP_COND':
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

    if mn in ('JMP_ABS', 'CALL'):
        return f"{name}  -> {p.target_addr:#010x}"

    if mn in ('SWITCH', 'SWITCH_CALL'):
        entries = "  ".join(f"[{i}]->{e:#010x}" for i, e in enumerate(p.entries))
        return f"{name}  idx={fmt_operand(p.index_src)}  {entries}"

    # ── Utilities ─────────────────────────────────────────────────────────────
    if mn == 'RAND_RANGE':
        return f"{name}  dst={fmt_operand(p.dst_var)}  range=[{fmt_operand(p.op1)}, {fmt_operand(p.op2)}]"

    if mn == 'PUSH_MULT':
        ops = ", ".join(fmt_operand(v) for v in p.operands)
        return f"{name}  [{ops}]"

    if mn == 'POP_MULT':
        vs = ", ".join(fmt_operand(v) for v in p.var_idx)
        return f"{name}  [{vs}]"

    # ── System / Message / Scene ──────────────────────────────────────────────
    if mn == 'CMD_EXIT':
        return f"{name}  code={fmt_operand(p.exit_code_src)}"

    if mn == 'CMD_SGET':
        # dst_var_raw is always a variable reference; apply the same encodeVariableRef
        # bias (+0x8000) that the engine uses so we display it as v<idx>.
        dst = f"v{p.dst_var_raw + 0x8000}"
        return f"{name}  dst={dst}  flag={fmt_operand(p.flag_id_src)}"

    if mn == 'CMD_SSET':
        return f"{name}  value={fmt_operand(p.value_src)}  flag={fmt_operand(p.flag_id_src)}"

    if mn == 'CMD_WAIT':
        return f"{name}  duration={fmt_operand(p.duration_src)}"

    if mn == 'CMD_WAITKEY':
        return f"{name}  mode={fmt_operand(p.mode_src)}"

    if mn == 'CMD_MSGINIT':
        if hasattr(p.msg_style, 'is_var') and p.msg_style.is_var:
            style_str = f"v{p.msg_style.var_idx}"
        else:
            try:
                style_str = p.msg_style.value_msg_style.name.upper()
            except Exception:
                style_str = fmt_operand(p.msg_style)
        just = p.justification
        if hasattr(just, 'is_var') and just.is_var:
            just_str = f"v{just.var_idx}"
        else:
            try:
                just_str = just.value_justification.name
            except Exception:
                just_str = fmt_operand(just)
        return f"{name}  style={style_str}  justify={just_str}"

    if mn == 'CMD_MSGGET':
        text = _str_msg(p.message_str) if p.len_message_str else ""
        is_sync = "[sync mode]" if p.is_sync else "[async mode]"
        return f'{name}  flag_base={p.base_flag_idx} {is_sync}  "{text}"'

    if mn == 'CMD_MSGWAIT':
        return f"{name}  mode={fmt_operand(p.mode_src)}"

    if mn == 'CMD_MSGCHECK':
        return f"{name}  flag_base={p.base_flag_idx}"

    if mn == 'CMD_MSGQUAKE':
        return f"{name}  op1={fmt_operand(p.op1)}"

    if mn == 'CMD_LOGSET':
        return f'{name}  "{_str_msg(p.log_str)}"'

    if mn == 'CMD_SELECT':
        title   = _str_msg(p.title_str) if p.len_title_str else ""
        choices = _choices_str(p.choices) if p.len_choices else ""
        vm = p.visibility_bitmask
        visible = f"{vm.value:#06x}" if not vm.is_var else fmt_operand(vm)
        return (f'{name}  flag_base={p.choice_base_flag_idc}'
                f'  flag_id=v{p.flag_base_raw}  dst={fmt_operand(p.script_var_num)}'
                f'  visible={visible}'
                f'  title="{title}"  choices=[{choices}]')

    if mn == 'CMD_WIPE':
        # Higurashi has an extra leading `mode` byte, and when mode != 0 only
        # bit 0 of the bitmask gates an operand word (see payload_wipe_higu).
        gated = (not higu) or p.mode == 0
        parts = []
        if higu:
            parts.append(f"mode={p.mode:#04x}")
        parts.append(f"bitmask={p.bitmask:#04x}")
        if p.bitmask & 0x01:          parts.append(f"mask={fmt_mask(snr, p.mask_snr_id)}")
        if gated and p.bitmask & 0x02: parts.append(f"duration={fmt_operand(p.duration_ticks)}")
        if gated and p.bitmask & 0x04: parts.append(f"height={fmt_operand(p.wipe_height)}")
        if gated and p.bitmask & 0x08: parts.append(f"dir={fmt_operand(p.direction_flags)}")
        if p.wait_for_completion: parts.append("[wait]")
        return f"{name}  " + "  ".join(parts)

    # ── Audio ─────────────────────────────────────────────────────────────────
    if mn == 'CMD_BGMPLAY':
        return (f"{name}  [{fmt_operand(p.song_id)}] {_bgm_name(snr, p.song_id.value)}"
                f"  loop={fmt_operand(p.loop_num_records)}  vol={_vol(p.volume_raw.value)}"
                f"  fade={fmt_operand(p.fade_duration)}")

    if mn == 'CMD_BGMSTOP':
        return f"{name}  fade={fmt_operand(p.fade_duration)}"

    if mn == 'CMD_BGMVOL':
        return f"{name}  vol={_vol(p.volume_raw.value)}  fade={fmt_operand(p.fade_duration)}"

    if mn == 'CMD_BGMWAIT':
        return f"{name}  duration={fmt_operand(p.duration_src)}"

    if mn == 'CMD_SEPLAY':
        return (f"{name}  stream={fmt_operand(p.stream_id)}  [{fmt_operand(p.se_id)}] {_sebg_name(snr, p.se_id.value)}"
                f"  loop={fmt_operand(p.loop_num_records)}  vol={_vol(p.volume_raw.value)}"
                f"  fade={fmt_operand(p.fade_duration)}")

    if mn == 'CMD_SESTOP':
        return f"{name}  stream={fmt_operand(p.stream_id)} fade={fmt_operand(p.fade_duration)}"

    if mn == 'CMD_SESTOPALL':
        return f"{name}  fade={fmt_operand(p.fade_duration)}"

    if mn == 'CMD_SEVOL':
        return f"{name}  stream={fmt_operand(p.stream_id)}  vol={_vol(p.volume_raw.value)}  fade={fmt_operand(p.fade_duration)}"

    if mn == 'CMD_SEWAIT':
        return f"{name}  stream={fmt_operand(p.stream_id)}  preload={fmt_operand(p.do_preload)}"

    if mn == 'CMD_SEONCE':
        return (f"{name}  [{fmt_operand(p.sound_effect_id)}] {_sebg_name(snr, p.sound_effect_id.value)}"
                f"  vol={_vol(p.volume_raw.value)}  preload={fmt_operand(p.do_preload)}")

    if mn == 'CMD_VIBRATE':
        return f"{name}  intensity={fmt_operand(p.vibration_intensity)}  ticks={fmt_operand(p.duration_ticks)}"

    # ── Misc ──────────────────────────────────────────────────────────────────
    if mn == 'CMD_SAVEINFO':
        if higu:
            return f'{name}  type={fmt_operand(p.type)}  "{_str_msg(p.saveinfo_str)}"'
        return f'{name}  type={p.type}  "{_str_msg(p.saveinfo_str)}"'

    if mn == 'CMD_MOVIE':
        return f"{name}  [{p.movie_id}] {_movie_name(snr, p.movie_id)}"

    if mn == 'CMD_BGMSYNC':
        return f"{name}  threshold={p.threshold_duration}"

    if mn == 'CMD_EVBEGIN':
        # Higurashi only — Umineko's EVBEGIN has no payload and returned above.
        return f"{name}  event={fmt_operand(p.event_id)}"

    if mn == 'CMD_BGMPLAY2':
        return (f"{name}  new=[{p.new_song_id}] {_bgm_name(snr, p.new_song_id)}"
                f"  old=[{p.old_song_id}] {_bgm_name(snr, p.old_song_id)}"
                f"  loop={fmt_operand(p.loop_num_records)}  vol={_vol(p.volume_raw)}"
                f"  crossfade={p.crossfade_delay}")

    if mn == 'CMD_BGMVOL2':
        return f"{name}  vol={_vol(p.volume_raw.value)}  fade={fmt_operand(p.fade_duration)}"

    if mn == 'CMD_VOICEPLAY':
        if higu:
            return (f'{name}  "{_strz(p.path)}"  vol={fmt_operand(p.volume_raw)}'
                    f"  flag={fmt_operand(p.flag)}")
        return (f"{name}  stream={p.stream_id}  [{p.voice_id}] {_voice_name(snr, p.voice_id)}"
                f"  loop={fmt_operand(p.loop_num_records)}  vol={_vol(p.volume_raw)}"
                f"  fade={p.fade_duration}")

    if mn == 'CMD_VOICEWAIT':
        return f"{name}  wait_flags={p.wait_flags.value:#06x}"

    if mn == 'CMD_TIPSGET':
        ids = ", ".join(str(fmt_operand(v)) for v in p.operands)
        return f"{name} .num_operands={p.num_operands}  ids=[{ids}]"

    # ── Higurashi-only commands ───────────────────────────────────────────────
    if mn == 'CMD_CHARSEL':
        return (f"{name}  flag_base={p.flag_base_id}  dst=v{p.dst_var_idx}"
                f"  unused={p.unused:#06x}  op1={fmt_operand(p.op1)}")

    if mn == 'CMD_OTSUGET':
        return f"{name}  op1={fmt_operand(p.op1)}"

    if mn == 'CMD_CHART':
        ids = ", ".join(fmt_operand(v) for v in p.operands)
        return f"{name}  kind={p.chart_kind}  ids=[{ids}]"

    if mn == 'CMD_SNRSEL':
        return f"{name}  scenario={fmt_operand(p.op1)}"

    if mn == 'CMD_KAKERAGET':
        ids = ", ".join(fmt_operand(v) for v in p.operands)
        return f"{name}  op1={fmt_operand(p.op1)}  ids=[{ids}]"

    if mn == 'CMD_QUIZ':
        return (f"{name}  dst=v{p.dst_var_idx}  op1={fmt_operand(p.op1)}"
                f"  op2={fmt_operand(p.op2)}  op3={fmt_operand(p.op3)}")

    # ── Layer / Canvas / Screen ───────────────────────────────────────────────
    if mn == 'CMD_THROPY':
        return f"{name}  id={fmt_operand(p.thropy_id)}"

    if mn == 'CMD_CHAR':
        return f"{name}  char_tree_snapshot={fmt_operand(p.char_tree_snapshot)}  starting_page={fmt_operand(p.starting_page)}"

    if mn == 'CMD_LAYERLOAD':
        lt_val = _layer_type_val(p.layer_type)
        lt_str = _LAYER_TYPE_NAMES.get(lt_val, f"type={lt_val}")
        parts  = [f"layer={fmt_operand(p.layer_id)}", lt_str]
        if higu:
            parts.append(f"extra={fmt_operand(p.extra)}")
        parts.append(f"field_mask={p.field_mask:#04x}")
        if p.field_mask & 0x01:
            if p.asset_id.is_var:
                # asset id comes from a script variable — nothing to resolve
                parts.append(f"asset=[{fmt_operand(p.asset_id)}]")
            else:
                parts.append(f"asset=[{fmt_operand(p.asset_id)}] {_layer_asset(snr, lt_val, p.asset_id.value)}")
        if p.field_mask & 0x02: parts.append(f"paramb={fmt_operand(p.paramb)}")
        if p.field_mask & 0x04: parts.append(f"w={fmt_operand(p.width)}")
        if p.field_mask & 0x08: parts.append(f"h={fmt_operand(p.height)}")
        if p.field_mask & 0x10: parts.append(f"x={fmt_operand(p.x)}")
        if p.field_mask & 0x20: parts.append(f"y={fmt_operand(p.y)}")
        if p.field_mask & 0x40: parts.append(f"paramc={fmt_operand(p.paramc)}")
        if p.field_mask & 0x80: parts.append(f"paramd={fmt_operand(p.paramd)}")
        return f"{name}  " + "  ".join(parts)

    if mn == 'CMD_LAYERCTRL':
        parts = [f"layer={fmt_operand(p.layer_id)}", f"anim={fmt_anim_type(p.anim_type)}", f"mask={p.field_mask:#04x}"]
        for i, (bit, attr) in enumerate([
                (0x01,'end_value'),(0x02,'duration_or_step'),(0x04,'mode_and_easing'),(0x08,'height'),
                (0x10,'x'),(0x20,'y'),(0x40,'paramc'),(0x80,'paramd')]):
            if p.field_mask & bit:
                parts.append(f"{attr}={fmt_operand(getattr(p, attr))}")
        return f"{name}  " + "  ".join(parts)

    if mn == 'CMD_LAYERWAIT':
        return f"{name}  layer={fmt_operand(p.layer_id)}  anim_type={fmt_wait_anim_type(p.anim_type)}"

    if mn == 'CMD_MASKLOAD':
        return f"{name}  [{fmt_operand(p.mask_id)}] {_mask_name(snr, p.mask_id.value)}  bool1={fmt_operand(p.bool1)}"

    if mn == 'CMD_CANVAS':
        return f"{name}  canvas_id={fmt_operand(p.canvas_id)}"

    if mn == 'CMD_CANVASCTRL':
        parts = [f"anim={fmt_anim_type(p.anim_type)}", f"mask={p.field_mask:#04x}"]
        for i, (bit, attr) in enumerate([
                (0x01,'param0'),(0x02,'param1'),(0x04,'param2'),(0x08,'param3'),
                (0x10,'param4'),(0x20,'param5'),(0x40,'param6'),(0x80,'param7')]):
            if p.field_mask & bit:
                parts.append(f"p{i}={fmt_operand(getattr(p, attr))}")
        return f"{name}  " + "  ".join(parts)

    if mn == 'CMD_CANVASWAIT':
        return f"{name}  anim={fmt_wait_anim_type(p.anim_type)}"

    if mn == 'CMD_SCREENCTR':
        parts = [f"anim={fmt_anim_type(p.anim_type)}", f"mask={p.field_mask:#04x}"]
        for i, (bit, attr) in enumerate([
                (0x01,'param0'),(0x02,'param1'),(0x04,'param2'),(0x08,'param3'),
                (0x10,'param4'),(0x20,'param5'),(0x40,'param6'),(0x80,'param7')]):
            if p.field_mask & bit:
                parts.append(f"p{i}={fmt_operand(getattr(p, attr))}")
        return f"{name}  " + "  ".join(parts)

    if mn == 'CMD_SCREENWAIT':
        return f"{name}  anim={fmt_wait_anim_type(p.anim_type)}"

    # ── Debug / Utility ───────────────────────────────────────────────────────
    if mn == 'CMD_MSGBOX':
        return f'{name}  "{_str_msg(p.message)}"'

    if mn == 'CMD_SNAPSHOT':
        return f'{name}  "{_strz(p.filename_base)}"  index={fmt_operand(p.index)}'

    # Fallback
    return f"{name}  (payload={type(p).__name__}  opcode={int(instr.opcode):#04x})"


# =============================================================================
# Asset table printer
# =============================================================================

_CHART_NODE_NAMES = {0:"GROUP", 1:"TITLED_BOX", 2:"ICON_BOX",
                     3:"VLINE", 4:"HLINE", 5:"PAGE_MARKER"}


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
        if is_higu(snr):
            print(f"[{i:4d}]  {_strz(r.name):<26}  emotion={_strz(r.emotion):<18}  char_id={r.char_id}")
        else:
            print(f"[{i:4d}]  {_strz(r.name):<26}  emotion={_strz(r.emotion)}")

    if not is_higu(snr):
        section("Anime")
        for i, r in enumerate(snr.anime_section.records):
            print(f"  [{i:4d}]  {_strz(r.name)}")

    section("CG Gallery (Picturebox)")
    for i, r in enumerate(snr.picturebox_section.cg_entries):
        parts = []
        for v in r.values:
            chain = [_pic_name(snr, v)]
            if v < snr.pic_section.num_records:
                nid = snr.pic_section.records[v].next_id
                while nid != -1 and nid < snr.pic_section.num_records:
                    chain.append(_pic_name(snr, nid))
                    nid = snr.pic_section.records[nid].next_id
            parts.append(" -> ".join(chain))
        pics_str = "  |  ".join(parts)
        if is_higu(snr):
            print(f"  [cg {i:3d}]  bonus={int(r.is_bonus)}  {pics_str}")
        else:
            print(f"  [cg {i:3d}]  type={r.type}  {pics_str}")

    if is_higu(snr):
        section("Music Box")
        for i, r in enumerate(snr.musicbox_section.records):
            print(f"  [{i:4d}]  bgm=[{r.bgm_id}] {_bgm_name(snr, r.bgm_id)}"
                  f"  title=sheet{r.title_sheet}/row{r.title_row}  flags={r.flags}")

        section("Tips")
        for i, r in enumerate(snr.tips_section.tips):
            print(f"  [{i:4d}]  title=sheet{r.title_sheet}/row{r.title_row}"
                  f"  txa=\"{_strz(r.txa_path)}\"")

        section("Chart (episode flowchart)")
        for i, n in enumerate(snr.chart_section.payload.nodes):
            nt = n.node_type.value if hasattr(n.node_type, 'value') else int(n.node_type)
            label = _CHART_NODE_NAMES.get(nt, f"TYPE_{nt}")
            if nt == 1:
                print(f"  [{i:5d}]  {label:<11}  grid=({n.grid_x:4d},{n.grid_y:4d})"
                      f"  scene={n.body.scene_id:5d}  colour={n.body.colour}"
                      f"  \"{_strz(n.body.title)}\"")
            elif nt == 2:
                print(f"  [{i:5d}]  {label:<11}  grid=({n.grid_x:4d},{n.grid_y:4d})"
                      f"  icon=row{n.body.icon_row}/col{n.body.icon_col}")
            else:
                print(f"  [{i:5d}]  {label:<11}  grid=({n.grid_x:4d},{n.grid_y:4d})"
                      f"  param={n.body.param}")


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
    higu = is_higu(snr)

    print(f"SNR file      : {path}  ({len(data)} bytes)")
    if higu:
        print(f"format        : higurashi (header 0x{snr.header.header_size:02x}, "
              f"{snr.header.num_slots + 2} section slots)")
    print(f"bytecode off  : {snr.header.off_bytecode:#010x}")
    print(f"sjis decode   : {'on (half-width kana expanded)' if _DECODE_SJIS else 'off (raw)'}")
    print(f"BGM tracks    : {snr.bgm_section.num_records}")
    print(f"SE/bg sounds  : {snr.se_bg_section.num_records}")
    print(f"Voice clips   : {snr.voice_section.num_records}")
    print(f"Movies        : {snr.movie_section.num_records}")
    print(f"Masks         : {snr.mask_section.num_records}")
    print(f"Pictures      : {snr.pic_section.num_records}")
    print(f"Bustup sprites: {snr.bustup_section.num_records}")
    if not higu:
        print(f"Anime clips   : {snr.anime_section.num_records}")
    print(f"CG gallery     : {snr.picturebox_section.num_cg_entries}")
    if higu:
        print(f"Music box     : {snr.musicbox_section.num_records}")
        print(f"Tips entries  : {snr.tips_section.num_tips}")
        print(f"Chart nodes   : {len(snr.chart_section.payload.nodes)}")

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
