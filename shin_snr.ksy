meta:
  id: shin_snr
  title: "shin:: SNR scenario/script file"
  file-extension: snr
  endian: le

doc: |
  shin:: engine SNR file format (Umineko PS3 and related titles).
  Contains a header with section-offset pointers, asset-name tables for BGM,
  SE-bg, voice, mask, picture, bustup, anime, and movie assets, plus the
  raw bytecode stream that drives the script VM.

  The bytecode section is parsed into a flat sequence of Instruction records
  whose payload structs vary by opcode.  Where an instruction payload contains
  an asset_id field it is cross-referenced to the appropriate name table via
  the instances defined at the top level.

seq:
  - id: header
    type: snr_header

instances:
  # ── Asset-name table helpers (cross-reference from instructions) ──────────
  bgm_section:
    pos: header.off_bgm
    type: bgm_section
  se_bg_section:
    pos: header.off_sebg
    type: se_bg_section
  voice_section:
    pos: header.off_voice
    type: voice_section
  movie_section:
    pos: header.off_movie
    type: movie_section
  mask_section:
    pos: header.off_mask
    type: mask_section
  pic_section:
    pos: header.off_pic
    type: pic_section
  bustup_section:
    pos: header.off_bustup
    type: bustup_section
  anime_section:
    pos: header.off_anime
    type: anime_section
  picturebox_section:
    pos: header.off_picturebox
    type: picturebox_section
  musicbox_section:
    pos: header.off_musicbox
    type: musicbox_section
  tips_section:
    pos: header.off_tips
    type: tips_section
  chars_section:
    pos: header.off_chars
    type: chars_section
  charflags_section:
    pos: header.off_charflags
    type: charflags_section
  # ── Bytecode ──────────────────────────────────────────────────────────────
  bytecode:
    pos: header.off_bytecode
    type: bytecode_stream

# ═══════════════════════════════════════════════════════════════════════════
# Header
# ═══════════════════════════════════════════════════════════════════════════

types:

  operand:
    seq:
      - id: raw
        type: s2
    instances:
      is_var:
        value: raw < -0x4000
      var_idx:
        value: raw + 0x8000
        if: is_var
      value:
        value: raw
        if: not is_var
      value_layer_type:
        value: raw
        enum: layer_type
      value_anim_type:
        value: raw
        enum: anim_type
  snr_header:
    seq:
      - id: magic
        size: 3
        doc: Should be "SNR" or similar magic bytes.
      - id: pad
        size: 0x1d
      - id: off_bytecode
        type: u4
      - id: off_mask
        type: u4
      - id: off_pic
        type: u4
      - id: off_bustup
        type: u4
      - id: off_anime
        type: u4
      - id: off_bgm
        type: u4
      - id: off_sebg
        type: u4
      - id: off_movie
        type: u4
      - id: off_voice
        type: u4
      - id: off_picturebox
        type: u4
      - id: off_musicbox
        type: u4
      - id: off_tips
        type: u4
      - id: off_charflags
        type: u4
      - id: off_chars
        type: u4

# ═══════════════════════════════════════════════════════════════════════════
# Asset-name sections
# ═══════════════════════════════════════════════════════════════════════════

  bgm_section:
    seq:
      - id: num_records
        type: u4
      - id: records
        type: bgm_record
        repeat: expr
        repeat-expr: num_records
  bgm_record:
    seq:
      - id: filename
        size: 0x0c
      - id: title
        size: 0x28

  se_bg_section:
    seq:
      - id: num_records
        type: u4
      - id: records
        type: se_bg_record
        repeat: expr
        repeat-expr: num_records
  se_bg_record:
    seq:
      - id: name
        size: 0x18

  voice_section:
    seq:
      - id: num_records
        type: u4
      - id: records
        type: voice_record
        repeat: expr
        repeat-expr: num_records
  voice_record:
    seq:
      - id: filename
        size: 0x10
      - id: param1
        type: u4
      - id: param2
        type: u4

  movie_section:
    seq:
      - id: num_records
        type: u4
      - id: records
        type: movie_record
        repeat: expr
        repeat-expr: num_records
      - id: pad
        size: 2
  movie_record:
    seq:
      - id: name
        size: 0x12

  mask_section:
    seq:
      - id: num_records
        type: u4
      - id: records
        type: mask_record
        repeat: expr
        repeat-expr: num_records
  mask_record:
    seq:
      - id: name
        size: 0x0c

  pic_section:
    seq:
      - id: num_records
        type: u4
      - id: records
        type: pic_record
        repeat: expr
        repeat-expr: num_records
  pic_record:
    seq:
      - id: name
        size: 0x18
      - id: next_id
        type: s2

  bustup_section:
    seq:
      - id: num_records
        type: u4
      - id: records
        type: bustup_record
        repeat: expr
        repeat-expr: num_records
  bustup_record:
    seq:
      - id: name
        size: 0x18
      - id: emotion
        size: 0x10

  anime_section:
    seq:
      - id: num_records
        type: u4
      - id: records
        type: anime_record
        repeat: expr
        repeat-expr: num_records
  anime_record:
    seq:
      - id: name
        size: 0x24

  picturebox_section:
    seq:
      - id: num_records
        type: u4
      - id: records
        type: picturebox_record
        repeat: expr
        repeat-expr: num_records
  picturebox_record:
    seq:
      - id: num_values
        type: u1
      - id: type
        type: u1
      - id: values
        type: u2
        repeat: expr
        repeat-expr: num_values

  musicbox_section:
    seq:
      - id: num_records
        type: u4
      - id: records
        type: musicbox_record
        repeat: expr
        repeat-expr: num_records
  musicbox_record:
    seq:
      - id: data
        size: 6

  tips_section:
    seq:
      - id: num_tips
        type: u4
      - id: tips
        type: tips_entry
        repeat: expr
        repeat-expr: num_tips
  tips_entry:
    seq:
      - id: props
        type: u2
      - id: text
        size: length - 2
    instances:
      episode:
        value: props >> 12
      length:
        value: props & 0x0fff

  chars_section:
    seq:
      - id: num_entries
        type: u4
      - id: entries
        type: char_entry
        repeat: expr
        repeat-expr: num_entries
      - id: pad
        size: 2
  char_entry:
    seq:
      - id: props
        type: u2
      - id: body
        size: len_body
        type: char_body
    instances:
      len_body:
        value: (props & 0x0fff) - 2

  char_body:
    seq:
      - id: versions
        type: char_version
        repeat: eos

  char_version:
    seq:
      - id: type_word
        type: u2
      - id: payload
        type:
          switch-on: opcode
          cases:
            2: char_version_name
            3: char_version_desc
    instances:
      opcode:
        value: type_word >> 12
      rest:
        value: type_word & 0x0fff
  char_version_name:
    seq:
      - id: char_name
        size: 8
      - id: char_version
        size: 0x10
  char_version_desc:
    seq:
      - id: description
        # rest - 2 bytes already consumed by type_word
        terminator: 0

  charflags_section:
    seq:
      - id: num_entries
        type: u4
      - id: entries
        type: charflags_entry
        repeat: expr
        repeat-expr: num_entries
      - id: pad
        size: 2
  charflags_entry:
    seq:
      - id: size
        type: u2
      - id: fields
        type: u4
        repeat: expr
        repeat-expr: (size - 2) / 4

# ═══════════════════════════════════════════════════════════════════════════
# Bytecode stream
# ═══════════════════════════════════════════════════════════════════════════

  bytecode_stream:
    seq:
      - id: instructions
        type: instruction
        repeat: eos

  instruction:
    seq:
      - id: opcode
        type: u1
        enum: op_code
      - id: payload
        type:
          switch-on: opcode
          cases:
            # ── Logic / Memory ────────────────────────────────────────────
            'op_code::op_unary':              payload_unary
            'op_code::op_alu':                payload_alu
            'op_code::op_stack':              payload_stack
            'op_code::set_vars_mult_range':   payload_set_vars_mult_range
            'op_code::set_var_from_array':    payload_set_var_from_array
            'op_code::set_vars_mult_array':   payload_set_vars_mult_array
            # ── Flow Control ──────────────────────────────────────────────
            'op_code::jmp_cond':              payload_jump_cond
            'op_code::jmp_abs':               payload_jump_abs
            'op_code::call':                  payload_call
            'op_code::switch':                payload_switch
            'op_code::switch_call':           payload_switch
            # ── Utilities ─────────────────────────────────────────────────
            'op_code::rand_range':            payload_rand_range
            'op_code::push_mult':             payload_push_mult
            'op_code::pop_mult':              payload_pop_mult
            # ── System / Message / Scene ──────────────────────────────────
            'op_code::cmd_exit':              payload_exit
            'op_code::cmd_sget':              payload_sget
            'op_code::cmd_sset':              payload_sset
            'op_code::cmd_wait':              payload_wait
            'op_code::cmd_waitkey':           payload_waitkey
            'op_code::cmd_msginit':           payload_msginit
            'op_code::cmd_msgget':            payload_msgget
            'op_code::cmd_msgwait':           payload_msgwait
            'op_code::cmd_msgcheck':          payload_msgcheck
            'op_code::cmd_logset':            payload_logset
            'op_code::cmd_select':            payload_select
            'op_code::cmd_wipe':              payload_wipe
            # ── Audio ─────────────────────────────────────────────────────
            'op_code::cmd_bgmplay':           payload_bgm_play
            'op_code::cmd_bgmstop':           payload_bgm_stop
            'op_code::cmd_bgmvol':            payload_bgm_vol
            'op_code::cmd_bgmwait':           payload_bgm_wait
            'op_code::cmd_seplay':            payload_se_play
            'op_code::cmd_sestop':            payload_se_stop
            'op_code::cmd_sestopall':         payload_se_stop_all
            'op_code::cmd_sevol':             payload_se_vol
            'op_code::cmd_sewait':            payload_se_wait
            'op_code::cmd_seonce':            payload_se_once
            'op_code::cmd_vibrate':           payload_vibrate
            # ── Misc ──────────────────────────────────────────────────────
            'op_code::cmd_saveinfo':          payload_saveinfo
            'op_code::cmd_movie':             payload_movie
            'op_code::cmd_bgmsync':           payload_bgm_sync
            'op_code::cmd_bgmplay2':          payload_bgm_play2
            'op_code::cmd_bgmvol2':           payload_bgm_vol2
            'op_code::cmd_voiceplay':         payload_voice_play
            'op_code::cmd_voicewait':         payload_voice_wait
            'op_code::cmd_tipsget':           payload_tipsget
            # ── Layer / Canvas / Screen ───────────────────────────────────
            'op_code::cmd_thropy':            payload_thropy
            'op_code::cmd_char':              payload_char
            'op_code::cmd_layerload':         payload_layer_load
            'op_code::cmd_layerctrl':         payload_layer_ctrl
            'op_code::cmd_layerwait':         payload_layer_wait
            'op_code::cmd_maskload':          payload_mask_load
            'op_code::cmd_canvas':            payload_canvas
            'op_code::cmd_canvasctrl':        payload_canvas_ctrl
            'op_code::cmd_canvaswait':        payload_canvas_wait
            'op_code::cmd_screenctr':         payload_screen_ctrl
            'op_code::cmd_screenwait':        payload_screen_wait
            # ── Debug / Utility ───────────────────────────────────────────
            'op_code::cmd_msgbox':            payload_msgbox
            'op_code::cmd_snapshot':          payload_snapshot
            # All scriptTrue no-op stubs: fall through to default (no payload)

# ═══════════════════════════════════════════════════════════════════════════
# Payload types — Logic / Memory (0x40–0x4E)
# ═══════════════════════════════════════════════════════════════════════════

  payload_unary:
    doc: "0x40 OP_UNARY — mode:u8, op1:u16, [op2:u16 if mode>=0x80]"
    seq:
      - id: mode
        type: u1
      - id: op1
        type: operand
      - id: op2
        type: operand
        if: mode >= 0x80

  payload_alu:
    doc: |
      0x41 OP_ALU — mode:u8, dst_var:s16, src_a:s16, [src_b:s16 if ternary].

      Wire layout (always present): mode(u8)  dst_var(s16)  src_a(s16)
      Optional fourth word:         src_b(s16)  — only when is_ternary.

      Encoding:
        mode bit 7 clear → Binary  format: result = dst_var_resolved  OP src_a_resolved
        mode bit 7 set   → Ternary format: result = src_a_resolved    OP src_b_resolved

      In both cases the result is written to the variable identified by dst_var
      via setVar(dst_var, result) — dst_var is the RAW operand word (a var-ref),
      NOT resolved through resolveOperand.

      Operations (base_op = mode & 0x7F):
        0x00  ASSIGN  result = src_a                (binary only; sets dst = resolved src_a)
        0x01  MOV     result = dst_var_resolved      (binary only; src_a not present)
        0x02  ADD     result = lhs + rhs
        0x03  SUB     result = lhs - rhs
        0x04  MUL     result = lhs * rhs
        0x05  DIV     result = (s16)lhs / (s16)rhs
        0x06  MOD     result = lhs - (lhs/rhs)*rhs   (signed)
        0x07  AND     result = lhs & rhs
        0x08  OR      result = lhs | rhs
        0x09  XOR     result = lhs ^ rhs
        0x0A  SHL     result = lhs << (rhs & 0x3F)
        0x0B  SHR     result = (s16)lhs >> (rhs & 0x3F)
    seq:
      - id: mode
        type: u1
      - id: dst_var
        type: operand
        doc: |
          Always the destination: passed raw (as index) to setVar().
          In binary mode it is also the first ALU input (lhs = resolveOperand(dst_var)).
      - id: op1
        type: operand
        doc: |
          Binary mode: second ALU input (rhs)
          Ternary mode: first ALU input (lhs); always present.
      - id: op2
        type: operand
        doc: "Ternary mode only: second ALU input (rhs)."
        if: (mode & 0x80) != 0
    instances:
      base_op:
        value: mode & 0x7f
        doc: "Operation selector (low 7 bits of mode)."
      is_ternary:
        value: (mode & 0x80) != 0
        doc: "true → ternary format; false → binary format."

  # OP_STACK (0x42) requires reading s8 opcodes until a negative terminator,
  # which Kaitai cannot express with a fixed repeat-until on a signed byte
  # without a workaround.  We capture the body as a raw byte sequence up to a
  # practical maximum and leave higher-level decoding to the consumer.
  payload_stack:
    doc: |
      0x42 OP_STACK — dst_var:u16, then RPN op stream.
      Stream is a series of s8 op_code bytes; a negative byte terminates.
      PUSH (0x00) is followed by a u16 operand.
      Decoded here as a repeated stack_op until the terminator is consumed.
    seq:
      - id: dst_var
        type: operand
      - id: ops
        type: stack_op
        repeat: until
        repeat-until: _.is_terminal

  stack_op:
    seq:
      - id: op_code
        type: s1
      - id: operand
        type: operand
        if: op_code == 0    # PUSH
    instances:
      is_terminal:
        value: op_code < 0

  payload_set_vars_mult_range:
    doc: "0x43 SET_VARS_MULT_RANGE — value_src:u16, num_records:u8, var_idx[num_records]:u16"
    seq:
      - id: value_src
        type: operand
      - id: num_var_idx
        type: u1
      - id: var_idx
        type: u2
        repeat: expr
        repeat-expr: num_var_idx

  payload_set_var_from_array:
    doc: "0x44 SET_VAR_FROM_ARRAY — dst_var:u16, index_src:u16, table_size:u8, table_data[table_size]:u16"
    seq:
      - id: dst_var
        type: u2
      - id: index_src
        type: operand
      - id: num_table_data
        type: u1
      - id: table_data
        type: u2
        repeat: expr
        repeat-expr: num_table_data

  payload_set_vars_mult_array:
    doc: "0x45 SET_VARS_MULT_ARRAY — value_src:u16, index_src:u16, table_size:u8, var_index_table[table_size]:u16"
    seq:
      - id: value_src
        type: operand
      - id: index_src
        type: operand
      - id: num_var_index_table
        type: u1
      - id: var_index_table
        type: u2
        repeat: expr
        repeat-expr: num_var_index_table

# ═══════════════════════════════════════════════════════════════════════════
# Payload types — Flow Control (0x46–0x4B)
# ═══════════════════════════════════════════════════════════════════════════

  payload_jump_cond:
    doc: "0x46 JMP_COND — mode:u8, op1:u16, op2:u16, target_addr:u32"
    seq:
      - id: mode
        type: u1
      - id: op1
        type: operand
      - id: op2
        type: operand
      - id: target_addr
        type: u4

  payload_jump_abs:
    doc: "0x47 JMP_ABS — target_addr:u32"
    seq:
      - id: target_addr
        type: u4

  payload_call:
    doc: "0x48 CALL — target_addr:u32"
    seq:
      - id: target_addr
        type: u4

  # 0x49 RET — no payload (handled by default case)

  payload_switch:
    doc: "0x4A/0x4B SWITCH/SWITCH_CALL — index_src:u16, table_size:u16, entries[table_size]:u32"
    seq:
      - id: index_src
        type: operand
      - id: num_entries
        type: u2
      - id: entries
        type: u4
        repeat: expr
        repeat-expr: num_entries

# ═══════════════════════════════════════════════════════════════════════════
# Payload types — Utilities (0x4C–0x4E)
# ═══════════════════════════════════════════════════════════════════════════

  payload_rand_range:
    doc: "0x4C RAND_RANGE — dst_var:u16, op1:u16, op2:u16"
    seq:
      - id: dst_var
        type: operand
      - id: op1
        type: operand
      - id: op2
        type: u2

  payload_push_mult:
    doc: "0x4D PUSH_MULT — num_records:u8, operands[num_records]:u16"
    seq:
      - id: num_operands
        type: u1
      - id: operands
        type: operand
        repeat: expr
        repeat-expr: num_operands

  payload_pop_mult:
    doc: "0x4E POP_MULT — num_records:u8, var_idx[num_records]:u16"
    seq:
      - id: num_var_idx
        type: u1
      - id: var_idx
        type: operand
        repeat: expr
        repeat-expr: num_var_idx

# ═══════════════════════════════════════════════════════════════════════════
# Payload types — System / Message / Scene (0x80–0x8E)
# ═══════════════════════════════════════════════════════════════════════════

  payload_exit:
    seq:
      - id: exit_code_src
        type: operand

  payload_sget:
    doc: |
      0x81 CMD_SGET — read a system/state flag into a script variable.
      dst_var_raw: s16 variable reference, always a var (never a literal).
        The engine calls encodeVariableRef(raw) = raw + 0x8000 to obtain the
        var_num stored in SGETData; var_idx below mirrors that.
      flag_id_src: operand — the state-flag number to read (may be var or literal).
    seq:
      - id: dst_var_raw
        type: s2
        doc: Raw wire word; always negative (< -0x4000), encoding a var index.
      - id: flag_id_src
        type: operand
    instances:
      dst_var_idx:
        value: dst_var_raw + 0x8000
        doc: Logical variable index after encodeVariableRef bias (matches SGETData.var_num).

  payload_sset:
    seq:
      - id: value_src
        type: operand
      - id: flag_id_src
        type: operand

  payload_wait:
    seq:
      - id: duration_src
        type: operand

  payload_waitkey:
    seq:
      - id: mode_src
        type: operand

  payload_msginit:
    seq:
      - id: window_type_src
        type: operand
      - id: justify_src
        type: operand

  payload_msgget:
    doc: |
      0x86 CMD_MSGGET.
      packed_header: lower 24 bits = base_flag_idx+1; bit 24 = bool1.
      Followed by a Pascal-style (u8 length-prefixed) dialogue string.
    seq:
      - id: packed_header
        type: u4
      - id: len_message_str
        type: u2
      - id: message_str
        size: len_message_str
    instances:
      base_flag_idx:
        value: (packed_header & 0x00ffffff) - 1
      bool1:
        value: (packed_header >> 24) & 1

  payload_msgwait:
    seq:
      - id: mode_src
        type: operand

  # 0x88 CMD_MSGSIGNAL — no payload
  # 0x89 CMD_MSGCLOSE  — no payload

  payload_msgcheck:
    doc: "Lower 24 bits of packed_id = base_flag_idx+1"
    seq:
      - id: packed_id
        type: u4
    instances:
      base_flag_idx:
        value: (packed_id & 0x00ffffff) - 1

  payload_logset:
    doc: "0x8B CMD_LOGSET — null-terminated inline string"
    seq:
      - id: len_log_str
        type: u2
      - id: log_str
        size: len_log_str

  payload_select:
    doc: |
      0x8C CMD_SELECT.
      choice_base_flag_idc: i16, flag_base_id: i16, script_var_num: i16,
      visibility_bitmask: i16, then str8 title and str8 choices blob
      (null-delimited segments, double-null terminated).
    seq:
      - id: choice_base_flag_idc
        type: u2
      - id: flag_base_raw
        type: u2
      - id: script_var_num
        type: operand
      - id: visibility_bitmask
        type: operand
      - id: len_title_str
        type: u1
      - id: title_str
        size: len_title_str
      - id: len_choices
        type: u1
      - id: choices
        size: len_choices
    instances:
      flag_base_id:
        value: flag_base_raw + 0x8000 - 1
        doc: Logical variable index after encodeVariableRef bias (matches SGETData.var_num).

  payload_wipe:
    doc: |
      0x8D CMD_WIPE.
      bitmask: u8; bits 0-3 gate optional u16 fields:
        bit 0 → mask_snr_id
        bit 1 → duration_ticks
        bit 2 → wipe_height
        bit 3 → direction_flags
        bit 7 → wait-for-completion flag (no extra word)
    seq:
      - id: bitmask
        type: u1
      - id: mask_snr_id
        type: operand
        if: (bitmask & 0x01) != 0
      - id: duration_ticks
        type: operand
        if: (bitmask & 0x02) != 0
      - id: wipe_height
        type: operand
        if: (bitmask & 0x04) != 0
      - id: direction_flags
        type: operand
        if: (bitmask & 0x08) != 0
    instances:
      wait_for_completion:
        value: (bitmask >> 7) & 1

# ═══════════════════════════════════════════════════════════════════════════
# Payload types — Audio (0x9C–0xA6)
# ═══════════════════════════════════════════════════════════════════════════

  payload_bgm_play:
    doc: "0x9C CMD_BGMPLAY — song_id, loop_num_records, volume_raw (0-255→/255.0f), fade_duration"
    seq:
      - id: song_id
        type: operand
      - id: loop_num_records
        type: operand
      - id: volume_raw
        type: operand
      - id: fade_duration
        type: operand
    instances:
      bgm_name:
        value: _root.bgm_section.records[song_id.value].filename
        if: song_id.value < _root.bgm_section.num_records
      bgm_title:
        value: _root.bgm_section.records[song_id.value].title
        if: song_id.value < _root.bgm_section.num_records

  payload_bgm_stop:
    seq:
      - id: fade_duration
        type: operand

  payload_bgm_vol:
    seq:
      - id: volume_raw
        type: operand
      - id: fade_duration
        type: operand

  payload_bgm_wait:
    seq:
      - id: duration_src
        type: u2

  payload_se_play:
    doc: "0xA0 CMD_SEPLAY — stream_id, se_id (→ se_bg_section), loop_num_records, volume_raw, fade_duration"
    seq:
      - id: stream_id
        type: operand
      - id: se_id
        type: operand
      - id: loop_num_records
        type: operand
      - id: volume_raw
        type: operand
      - id: fade_duration
        type: operand
    instances:
      se_name:
        value: _root.se_bg_section.records[se_id.value].name
        if: se_id.value < _root.se_bg_section.num_records

  payload_se_stop:
    seq:
      - id: stream_id
        type: operand
      - id: fade_duration
        type: operand

  payload_se_stop_all:
    seq:
      - id: fade_duration
        type: operand

  payload_se_vol:
    seq:
      - id: stream_id
        type: operand
      - id: volume_raw
        type: operand
      - id: fade_duration
        type: operand

  payload_se_wait:
    seq:
      - id: stream_id
        type: operand
      - id: do_preload
        type: operand

  payload_se_once:
    doc: "0xA5 CMD_SEONCE — sound_effect_id (→ se_bg_section), volume_raw, do_preload"
    seq:
      - id: sound_effect_id
        type: operand
      - id: volume_raw
        type: operand
      - id: do_preload
        type: operand
    instances:
      se_name:
        value: _root.se_bg_section.records[sound_effect_id.value].name
        if: sound_effect_id.value < _root.se_bg_section.num_records

  payload_vibrate:
    seq:
      - id: vibration_intensity
        type: operand
      - id: duration_ticks
        type: operand

# ═══════════════════════════════════════════════════════════════════════════
# Payload types — Misc (0xB0–0xBD)
# ═══════════════════════════════════════════════════════════════════════════

  payload_saveinfo:
    doc: "0xB0 CMD_SAVEINFO — type:u16, null-terminated string"
    seq:
      - id: type
        type: u2
      - id: saveinfo_str
        terminator: 0

  payload_movie:
    doc: "0xB1 CMD_MOVIE — movie_id → movie_section"
    seq:
      - id: movie_id
        type: u2
    instances:
      movie_name:
        value: _root.movie_section.records[movie_id].name
        if: movie_id < _root.movie_section.num_records

  payload_bgm_sync:
    seq:
      - id: threshold_duration
        type: u2

  # 0xB3 CMD_EVBEGIN — no payload
  # 0xB4 CMD_EVEND   — no payload
  # 0xB6 CMD_AUTOSAVE — no payload

  payload_bgm_play2:
    doc: "0xB7 CMD_BGMPLAY2 — new_song_id, old_song_id (both → bgm_section), loop_num_records, volume_raw, crossfade_delay"
    seq:
      - id: new_song_id
        type: u2
      - id: old_song_id
        type: u2
      - id: loop_num_records
        type: u2
      - id: volume_raw
        type: u2
      - id: crossfade_delay
        type: u2
    instances:
      new_bgm_name:
        value: _root.bgm_section.records[new_song_id].filename
        if: new_song_id < _root.bgm_section.num_records
      old_bgm_name:
        value: _root.bgm_section.records[old_song_id].filename
        if: old_song_id < _root.bgm_section.num_records

  payload_bgm_vol2:
    seq:
      - id: volume_raw
        type: u2
      - id: fade_duration
        type: u2

  payload_voice_play:
    doc: "0xB9 CMD_VOICEPLAY — stream_id, voice_id (→ voice_section), loop_num_records, volume_raw, fade_duration"
    seq:
      - id: stream_id
        type: u2
      - id: voice_id
        type: u2
      - id: loop_num_records
        type: u2
      - id: volume_raw
        type: u2
      - id: fade_duration
        type: u2
    instances:
      voice_name:
        value: _root.voice_section.records[voice_id].filename
        if: voice_id < _root.voice_section.num_records

  payload_voice_wait:
    seq:
      - id: wait_flags
        type: operand

  payload_tipsget:
    doc: "0xBD CMD_TIPSGET — num_records:u8, then num_records*u16 tip operand IDs (→ tips_section)"
    seq:
      - id: num_operands
        type: u1
      - id: operands
        type: operand
        repeat: expr
        repeat-expr: num_operands

# ═══════════════════════════════════════════════════════════════════════════
# Payload types — Layer / Canvas / Screen (0xBE–0xCB)
# ═══════════════════════════════════════════════════════════════════════════

  payload_thropy:
    seq:
      - id: thropy_id
        type: operand

  payload_char:
    seq:
      - id: num_entries
        type: operand
      - id: unnamed_operand
        type: operand

  # 0xC0 CMD_LAYERCLEAR — no payload

  payload_layer_load:
    doc: |
      0xC1 CMD_LAYERLOAD.
      layer_id: u16, layer_type: u16 (enum), field_mask: u8.
      Bits 0-7 of field_mask gate the 8 optional u16 parameter slots.
      asset_id (bit 0) is cross-referenced to the section implied by layer_type.
    seq:
      - id: layer_id
        type: operand
      - id: layer_type
        type: operand
      - id: field_mask
        type: u1
      - id: asset_id
        type: operand
        if: (field_mask & 0x01) != 0
      - id: paramb
        type: operand
        if: (field_mask & 0x02) != 0
      - id: width
        type: operand
        if: (field_mask & 0x04) != 0
      - id: height
        type: operand
        if: (field_mask & 0x08) != 0
      - id: x
        type: operand
        if: (field_mask & 0x10) != 0
      - id: y
        type: operand
        if: (field_mask & 0x20) != 0
      - id: paramc
        type: operand
        if: (field_mask & 0x40) != 0
      - id: paramd
        type: operand
        if: (field_mask & 0x80) != 0

  payload_layer_ctrl:
    doc: "0xC2 CMD_LAYERCTRL — structurally identical to LAYERLOAD but no layer_type; i1 purpose TBD."
    seq:
      - id: layer_id
        type: operand
      - id: anim_type
        type: operand
      - id: field_mask
        type: u1
      - id: end_value
        type: operand
        if: (field_mask & 0x01) != 0
      - id: duration_or_step
        type: operand
        if: (field_mask & 0x02) != 0
      - id: mode_and_easing
        type: operand
        if: (field_mask & 0x04) != 0
      - id: height
        type: operand
        if: (field_mask & 0x08) != 0
      - id: x
        type: operand
        if: (field_mask & 0x10) != 0
      - id: y
        type: operand
        if: (field_mask & 0x20) != 0
      - id: paramc
        type: operand
        if: (field_mask & 0x40) != 0
      - id: paramd
        type: operand
        if: (field_mask & 0x80) != 0

  payload_layer_wait:
    seq:
      - id: layer_id
        type: operand
      - id: anim_type
        type: operand

  payload_mask_load:
    doc: "0xC4 CMD_MASKLOAD — mask_id (→ mask_section), param1"
    seq:
      - id: mask_id
        type: operand
      - id: bool1
        type: operand
    instances:
      mask_name:
        value: _root.mask_section.records[mask_id.value].name
        if: mask_id.value < _root.mask_section.num_records

  payload_canvas:
    seq:
      - id: canvas_id
        type: operand

  # 0xC6 CMD_CANVASINIT — no payload

  payload_canvas_ctrl:
    doc: "0xC7 CMD_CANVASCTRL — num_entries:u16, field_mask:u8, 0–8 optional InterpolatorStep u16 words"
    seq:
      - id: num_entries
        type: operand
      - id: field_mask
        type: u1
      - id: param0
        type: operand
        if: (field_mask & 0x01) != 0
      - id: param1
        type: operand
        if: (field_mask & 0x02) != 0
      - id: param2
        type: operand
        if: (field_mask & 0x04) != 0
      - id: param3
        type: operand
        if: (field_mask & 0x08) != 0
      - id: param4
        type: operand
        if: (field_mask & 0x10) != 0
      - id: param5
        type: operand
        if: (field_mask & 0x20) != 0
      - id: param6
        type: operand
        if: (field_mask & 0x40) != 0
      - id: param7
        type: operand
        if: (field_mask & 0x80) != 0

  payload_canvas_wait:
    seq:
      - id: param0
        type: operand

  # 0xC9 CMD_SCREENINIT — no payload

  payload_screen_ctrl:
    doc: "0xCA CMD_SCREENCTR — canvas_id:u16, field_mask:u8, 0–8 optional u16 data words"
    seq:
      - id: canvas_id
        type: u2
      - id: field_mask
        type: u1
      - id: param0
        type: u2
        if: (field_mask & 0x01) != 0
      - id: param1
        type: u2
        if: (field_mask & 0x02) != 0
      - id: param2
        type: u2
        if: (field_mask & 0x04) != 0
      - id: param3
        type: u2
        if: (field_mask & 0x08) != 0
      - id: param4
        type: u2
        if: (field_mask & 0x10) != 0
      - id: param5
        type: u2
        if: (field_mask & 0x20) != 0
      - id: param6
        type: u2
        if: (field_mask & 0x40) != 0
      - id: param7
        type: u2
        if: (field_mask & 0x80) != 0

  payload_screen_wait:
    seq:
      - id: anim_type
        type: operand

# ═══════════════════════════════════════════════════════════════════════════
# Payload types — Debug / Utility (0xF0–0xF1)
# ═══════════════════════════════════════════════════════════════════════════

  payload_msgbox:
    doc: "0xF0 CMD_MSGBOX — str8: u8 length prefix + string body"
    seq:
      - id: len_message
        type: u1
      - id: message
        size: len_message

  payload_snapshot:
    doc: "0xF1 CMD_SNAPSHOT — str8 filename_base, index:u16; output: <base>_%05d.bmp"
    seq:
      - id: len_filename_base
        type: u1
      - id: filename_base
        size: len_filename_base
      - id: index
        type: operand

# ═══════════════════════════════════════════════════════════════════════════
# Enums
# ═══════════════════════════════════════════════════════════════════════════

enums:
  op_code:
    # 0x00–0x3F: scriptTrue no-op stubs (not enumerated individually)
    0x40: op_unary
    0x41: op_alu
    0x42: op_stack
    0x43: set_vars_mult_range
    0x44: set_var_from_array
    0x45: set_vars_mult_array
    0x46: jmp_cond
    0x47: jmp_abs
    0x48: call
    0x49: ret
    0x4a: switch
    0x4b: switch_call
    0x4c: rand_range
    0x4d: push_mult
    0x4e: pop_mult
    # 0x4F–0x7F: scriptTrue stubs
    0x80: cmd_exit
    0x81: cmd_sget
    0x82: cmd_sset
    0x83: cmd_wait
    0x84: cmd_waitkey
    0x85: cmd_msginit
    0x86: cmd_msgget
    0x87: cmd_msgwait
    0x88: cmd_msgsignal
    0x89: cmd_msgclose
    0x8a: cmd_msgcheck
    0x8b: cmd_logset
    0x8c: cmd_select
    0x8d: cmd_wipe
    0x8e: cmd_wipewait
    # 0x8F–0x9B: scriptTrue stubs
    0x9c: cmd_bgmplay
    0x9d: cmd_bgmstop
    0x9e: cmd_bgmvol
    0x9f: cmd_bgmwait
    0xa0: cmd_seplay
    0xa1: cmd_sestop
    0xa2: cmd_sestopall
    0xa3: cmd_sevol
    0xa4: cmd_sewait
    0xa5: cmd_seonce
    0xa6: cmd_vibrate
    # 0xA7–0xAF: scriptTrue stubs
    0xb0: cmd_saveinfo
    0xb1: cmd_movie
    0xb2: cmd_bgmsync
    0xb3: cmd_evbegin
    0xb4: cmd_evend
    # 0xB5: scriptTrue stub
    0xb6: cmd_autosave
    0xb7: cmd_bgmplay2
    0xb8: cmd_bgmvol2
    0xb9: cmd_voiceplay
    0xba: cmd_voicewait
    # 0xBB–0xBC: scriptTrue stubs
    0xbd: cmd_tipsget
    0xbe: cmd_thropy
    0xbf: cmd_char
    0xc0: cmd_layerclear
    0xc1: cmd_layerload
    0xc2: cmd_layerctrl
    0xc3: cmd_layerwait
    0xc4: cmd_maskload
    0xc5: cmd_canvas
    0xc6: cmd_canvasinit
    0xc7: cmd_canvasctrl
    0xc8: cmd_canvaswait
    0xc9: cmd_screeninit
    0xca: cmd_screenctr
    0xcb: cmd_screenwait
    # 0xCC–0xEF: scriptTrue stubs
    0xf0: cmd_msgbox
    0xf1: cmd_snapshot
    # 0xF2–0xFF: scriptTrue stubs

  anim_type:
    0x00: gradientb
    0x01: fade_alpha
    0x02: fade_blue
    0x03: fade_green
    0x04: fade_red
    0x05: image_filter
    0x06: blend_mode
    0x07: st2c_a
    0x08: st2c_b
    0x09: pivot_x
    0x0a: pivot_y
    0x0b: scale_x
    0x0c: scale_y
    0x0d: rotation_z
    0x0e: imagelayer_flip
    0x0f: shake_amplitude
    0x10: shake_duration
    0x11: bob_amplitude
    0x12: bob_duration
    0x13: butsup_anim_byte
    0x14: rain_particle_spawn_rate   # 0-1000, max 50 concurrent for raindrop, 5 for hanabira
    0x15: rain_particle_size         # 0-1000, normalized to [0.0, 1.0] -> scale [0.0, 1.125] 
    0x16: rain_particle_rotation_z   # 0-1000, normalized to [-1.0, 1.0] --> [-pi/3, pi/3] radians -> [-60º, 60º]
                                     # with random values up to 66º raindrop, 88º hanabira
    0x17: rain_anim_paused
    0x18: effect_2c0
    0x19: effect_2c1
    0x1a: effect_2c2
    0x1b: effect_2c3
    0x1c: effect_2c4
    0x1d: effect_2c5
    0x1e: effect_2c6
    0x1f: effect_2c7
    0x20: effect_2c8
    0x21: effect_5_lerp
    0x22: effect_2ca
    0x23: breakup
    0x24: effectlayer_flip
    0x25: screen_anim_uint
    0x26: screen_interpa
    0x27: screen_interpb

  layer_type:
    0x01: layer_type_tile
    0x02: layer_type_picture
    0x03: layer_type_bustup
    0x04: layer_type_anime
    0x05: layer_type_rain
    0x06: layer_type_effect
