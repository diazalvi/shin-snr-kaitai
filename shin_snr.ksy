meta:
  id: shin_snr
  title: "shin:: SNR scenario/script file (Umineko + Higurashi PS3)"
  file-extension: snr
  endian: le

doc: |
  shin:: engine SNR file format.

  TWO FORMAT VARIANTS are supported by this spec:

    * `umineko`   — Umineko no Naku Koro ni Chiru PS3 (EBOOT.ELF / EBOOT-CHIRU.elf).
                    14 section-offset slots at 0x20..0x54, first section at 0x58.
    * `higurashi` — Higurashi no Naku Koro ni Sui PS3 (EBOOT-HIGURASHI.elf).
                    12 section-offset slots at 0x20..0x4C, first section at 0x50.

  ── Version detection ───────────────────────────────────────────────────────
  There is NO version field in the header.  This was checked exhaustively:
  neither the magic nor any header scalar is ever compared against a constant
  in EBOOT.ELF, EBOOT-CHIRU.elf or EBOOT-HIGURASHI.elf.  The magic bytes
  "SNR " never appear as an instruction operand in any of the three binaries,
  and `ScenarioFile::ScenarioFile @ 00080fa4` (Higurashi) reads exactly one
  header field — the size at +0x04 — with no validation and no error path.
  Each engine build simply hardcodes its own layout.

  The variant is therefore derived from the header itself:  `off_mask`
  (u4 @ 0x24) is the first section pointer and equals the header size.

      off_mask == 0x58  ->  umineko    (14 slots)
      off_mask == 0x50  ->  higurashi  (12 slots)

  Slot count is `(off_mask - 0x20) / 4`, so the test degrades gracefully.

  ── Section-slot drift ──────────────────────────────────────────────────────
  Higurashi drops `anime`, which shifts every slot from `bgm` onward down one,
  and replaces Umineko's `charflags`/`chars` pair with a single `chart`
  (episode flowchart) section:

      slot   umineko                    higurashi
      0x20   bytecode                   bytecode
      0x24   mask                       mask
      0x28   pic                        pic
      0x2C   bustup                     bustup
      0x30   anime                      bgm
      0x34   bgm                        sebg  (path is /se/, not /sebg/)
      0x38   sebg                       movie
      0x3C   movie                      voice
      0x40   voice                      picturebox
      0x44   picturebox                 musicbox
      0x48   musicbox                   tips
      0x4C   tips                       chart
      0x50   charflags                  —
      0x54   chars                      —

  Sections are NOT laid out contiguously in a defined order — always seek by
  the header pointer, never by "end of the previous section".  Known
  inter-section padding: umineko pic(+2), movie(+2), chars(+2), charflags(+2);
  higurashi pic(+2), bustup(+2), chart(+4 before the bytecode).

  ── Bytecode ────────────────────────────────────────────────────────────────
  The opcode table was renumbered wholesale between the two games: MSGQUAKE
  was inserted at 0x8B (shifting LOGSET/SELECT/WIPE/WIPEWAIT by +1), the audio
  block moved from 0x9C.. down to 0x90.., nine new commands were added, and
  MASKLOAD / CANVAS* / SCREEN* / MSGBOX / SNAPSHOT / BGMPLAY2 / BGMVOL2 / CHAR
  were dropped.  `instruction` therefore switches on `opcode + 0x100` for
  higurashi so a single flat case table covers both games.

seq:
  - id: header
    type: snr_header

instances:
  # ── Version shortcuts (used by the record types below) ────────────────────
  version:
    value: header.version
    enum: snr_version
  is_umineko:
    value: header.is_umineko
  is_higurashi:
    value: header.is_higurashi

  # ── Asset-name table helpers (cross-referenced from instructions) ─────────
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
    if: is_umineko
    doc: Umineko only — Higurashi has no anime layer type and no anime assets.
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
    if: is_umineko
  charflags_section:
    pos: header.off_charflags
    type: charflags_section
    if: is_umineko
  chart_section:
    pos: header.off_chart
    type: chart_section
    if: is_higurashi
    doc: Higurashi only — the episode flowchart drawn over /chart.txa.

  # ── Bytecode ──────────────────────────────────────────────────────────────
  bytecode:
    pos: header.off_bytecode
    type: bytecode_stream

# ═══════════════════════════════════════════════════════════════════════════
# Header
# ═══════════════════════════════════════════════════════════════════════════

types:

  operand:
    doc: |
      "NumberSpec" wire word.  A raw s16 below -0x4000 is a variable reference
      (logical index = raw + 0x8000); anything else is a literal.
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
      value_layer_wait_anim_type:
        value: raw
        enum: layer_wait_anim_type
      value_justification:
        value: raw
        enum: justification
      value_msg_style:
        value: raw
        enum: msg_style

  snr_header:
    doc: |
      Fixed prefix (0x00..0x27) followed by a variable-length section-offset
      table whose length is implied by `off_mask`.
    seq:
      - id: magic
        size: 4
        doc: '"SNR " (0x53 0x4E 0x52 0x20) in both games. Never validated by the engine.'
      - id: file_size
        type: u4
        doc: |
          Total file size in bytes.  Read by ScenarioFile::ScenarioFile
          @ 00080fa4 (Higurashi) as the memcpy length.  NOT a version.
      - id: num_msg_flags
        type: u4
        doc: |
          +0x08.  Umineko 32539, Higurashi 155467.  Write-only in every
          binary (Higurashi byteswaps it in Load and never reads it again;
          Umineko/Chiru never touch it).  Magnitude and bounds match the
          message read-flag bitset capacity in both games (Umineko 36000
          bits, Higurashi 160000 bits), so almost certainly the count of
          MSGGET/MSGCHECK read-flags — but that is inference, not code.
      - id: unk_0c
        type: u4
        doc: '+0x0C.  Umineko 1, Higurashi 65.  No reader in any binary; meaning unknown.'
      - id: unk_10
        type: u4
        doc: '+0x10.  Umineko 1, Higurashi 135.  No reader in any binary; meaning unknown.'
      - id: reserved
        size: 12
        doc: '+0x14..+0x1F.  Zero in both files; not even byteswapped by Load.'
      - id: off_bytecode
        type: u4
        doc: '+0x20.  Entry point; execution always starts here (no entry argument).'
      - id: off_mask
        type: u4
        doc: '+0x24.  First section pointer; its value is also the header size.'
      - id: slots
        type: u4
        repeat: expr
        repeat-expr: num_slots
        doc: 'Remaining section pointers, +0x28 onward.'
    instances:
      header_size:
        value: off_mask
      num_slots:
        value: (off_mask - 0x28) / 4
        doc: '10 for umineko (0x28..0x54), 8 for higurashi (0x28..0x4C).'
      is_higurashi:
        value: off_mask == 0x50
      is_umineko:
        value: off_mask != 0x50
      version:
        value: 'off_mask == 0x50 ? 1 : 0'
        enum: snr_version
      # ── Named slots ────────────────────────────────────────────────────────
      off_pic:
        value: slots[0]
      off_bustup:
        value: slots[1]
      off_anime:
        value: slots[2]
        if: is_umineko
      off_bgm:
        value: 'is_umineko ? slots[3] : slots[2]'
      off_sebg:
        value: 'is_umineko ? slots[4] : slots[3]'
      off_movie:
        value: 'is_umineko ? slots[5] : slots[4]'
      off_voice:
        value: 'is_umineko ? slots[6] : slots[5]'
      off_picturebox:
        value: 'is_umineko ? slots[7] : slots[6]'
      off_musicbox:
        value: 'is_umineko ? slots[8] : slots[7]'
      off_tips:
        value: 'is_umineko ? slots[9] : slots[8]'
      off_charflags:
        value: slots[10]
        if: is_umineko
      off_chars:
        value: slots[11]
        if: is_umineko
      off_chart:
        value: slots[9]
        if: is_higurashi

# ═══════════════════════════════════════════════════════════════════════════
# Asset-name sections
# ═══════════════════════════════════════════════════════════════════════════

  bgm_section:
    doc: 'Identical in both games. /bgm/<filename>.at3'
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
        doc: Shift-JIS display title shown in the music box.

  se_bg_section:
    doc: |
      Identical in both games (stride 0x18).  Umineko builds /sebg/<name>,
      Higurashi builds /se/<name>.at3 — the section name here is Umineko's.
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
    doc: |
      Identical in both games (stride 0x18).  `filename` is a wildcard pattern
      ('*', '?') matched against clip names by FindVoiceEntryByName; the two
      u4s form a 64-bit character bitmask consumed by the lip-sync code
      (VoiceManager::GetCharacterVoiceLevel tests bit `char_id`).
      In Higurashi the set bits are exactly the bustup_record.char_id domain.
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
      - id: char_mask_lo
        type: u4
        doc: Characters 0..31.
      - id: char_mask_hi
        type: u4
        doc: Characters 32..63.

  movie_section:
    doc: |
      Stride 0x12 in both games.  Umineko has a 2-byte trailing pad;
      Higurashi does not.
    seq:
      - id: num_records
        type: u4
      - id: records
        type: movie_record
        repeat: expr
        repeat-expr: num_records
      - id: pad
        size: 2
        if: _root.is_umineko
  movie_record:
    doc: |
      The name occupies only 0x0c bytes; the remaining three u16s are numeric
      and are byteswapped by ScenarioFile::Load at record +0x0C/+0x0E/+0x10.
      `bgm_id` unlocks a music-box track when the movie is watched
      (ADV::MOVIE::Run, TitleDemo::Start).  Same shape in both games.
    seq:
      - id: name
        size: 0x0c
      - id: unk_0c
        type: u2
      - id: bgm_id
        type: s2
        doc: BGM unlocked by watching this movie; -1 = none.
      - id: unused_10
        type: s2
        doc: -1 in every record of both games.

  mask_section:
    doc: 'Identical in both games. /mask/<name>.msk'
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
    doc: 'Identical in both games (stride 0x1A). /picture/<name>.pic'
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
        doc: |
          CG-gallery cross-link, -1 = none.  Displaying this picture also
          unlocks the CG slot owned by picture `next_id` (the picture-layer
          factory calls FindCGGroupByPicId twice, once per id).  It is a
          single hop, not a chain: in both games every link target itself
          has -1.

  bustup_section:
    seq:
      - id: num_records
        type: u4
      - id: records
        type: bustup_record
        repeat: expr
        repeat-expr: num_records
      - id: pad
        size: 2
        if: _root.is_higurashi
  bustup_record:
    doc: |
      Umineko stride 0x28; Higurashi 0x2A with a trailing character id.
      Umineko `emotion` strings are Shift-JIS, Higurashi's are ASCII romaji
      (the BUP3 -> BUP4 format change).
    seq:
      - id: name
        size: 0x18
      - id: emotion
        size: 0x10
      - id: char_id
        type: u2
        if: _root.is_higurashi
        doc: |
          Lip-sync character id, 0..49, sharing an id space with the voice
          section's char_mask bits.  Passed to BustupLayerLoader and used
          each frame to pick the mouth animation chunk.  0 = no lip-sync.

  anime_section:
    doc: Umineko only.
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
    doc: |
      CG gallery.  Each entry is one gallery group listing the pic ids that
      belong to it; the running flat index across all groups is the global
      save-flag index.
    seq:
      - id: num_cg_entries
        type: u4
      - id: cg_entries
        type: picturebox_cg_entry
        repeat: expr
        repeat-expr: num_cg_entries
  picturebox_cg_entry:
    doc: |
      Byte-identical encoding in both games, spelled differently by the two
      engines: Umineko reads {u8 count, u8 type}, Higurashi reads one u16
      whose bit 0x8000 is a flag and whose low 15 bits are the count.
      The flag marks a bonus / non-story group — in Umineko exactly one
      group of 60 sets it (the final CONGRA / PACKAGE02 pair); no Higurashi
      group sets it.
    seq:
      - id: num_values_u8
        type: u1
        if: _root.is_umineko
      - id: type
        type: u1
        if: _root.is_umineko
      - id: len_raw
        type: u2
        if: _root.is_higurashi
      - id: values
        type: u2
        repeat: expr
        repeat-expr: num_values
        doc: Indexes into pic_section.records.
    instances:
      num_values:
        value: '_root.is_umineko ? num_values_u8 : (len_raw & 0x7fff)'
      is_bonus:
        value: '_root.is_umineko ? (type == 0x80) : ((len_raw & 0x8000) != 0)'

  musicbox_section:
    seq:
      - id: num_records
        type: u4
      - id: records
        type: musicbox_record
        repeat: expr
        repeat-expr: num_records
  musicbox_record:
    doc: |
      Same 3 x u16 layout in both games.  The record's *position* in this
      list (not bgm_id) is the save-flag index.
    seq:
      - id: bgm_id
        type: u2
        doc: Index into bgm_section.records.
      - id: title_strip
        type: u2
        doc: |
          Title-sprite selector for /bgmmode.txa: bits[15:5] pick the
          "title0".."title3" sheet, bits[4:0] pick the row (32 rows, 44 px).
          Locked tracks fall back to strip 0 (the "???" row).
      - id: flags
        type: u2
        doc: '1 on every vocal song track, 0 otherwise.'
    instances:
      title_sheet:
        value: title_strip >> 5
      title_row:
        value: title_strip & 0x1f

  tips_section:
    seq:
      - id: num_tips
        type: u4
      - id: tips
        type: tips_entry
        repeat: expr
        repeat-expr: num_tips
  tips_entry:
    doc: |
      Completely different between the games.

      Umineko: variable-length.  `props` packs episode (bits 15:12) and the
      total record length in bytes (bits 11:0), followed by inline Shift-JIS.
      NOTE this model does not tile Umineko's tips section cleanly and is
      preserved as-is; the section is not exercised by the disassembler.

      Higurashi: fixed 0x12 stride.  `props` is a title-sprite selector with
      the same bit layout as musicbox_record.title_strip (sheets
      "title0".."title5" in /tipsget.txa and /tipsmode.txa).  The 0x10 bytes
      after it hold an ASCII "tips/NNN.txa" path that the engine never reads
      — an authoring-tool leftover; there is no /tips/ path builder in the
      binary.  The tip *text* is not in this section at all: it lives in the
      bytecode, reached by jumping to scenario (tips_index + 1000).
    seq:
      - id: props
        type: u2
      - id: text
        size: length - 2
        if: _root.is_umineko
      - id: txa_path
        size: 0x10
        if: _root.is_higurashi
    instances:
      episode:
        value: props >> 12
        if: _root.is_umineko
      length:
        value: props & 0x0fff
        if: _root.is_umineko
      title_sheet:
        value: props >> 5
        if: _root.is_higurashi
      title_row:
        value: props & 0x1f
        if: _root.is_higurashi

  chars_section:
    doc: Umineko only — the character-profile tree.
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
        terminator: 0

  charflags_section:
    doc: Umineko only.
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
# Chart section (Higurashi only)
# ═══════════════════════════════════════════════════════════════════════════

  chart_section:
    doc: |
      Episode flowchart rendered over /chart.txa.  NOTE the leading u4 is the
      PAYLOAD SIZE IN BYTES, not a node count — nodes are variable-size and
      must be walked.  The chart has 5 pages; a page-marker node opens each.
      Grid cell = 0x18 px horizontally, 0x26 px vertically.
    seq:
      - id: len_payload
        type: u4
      - id: payload
        type: chart_payload
        size: len_payload
  chart_payload:
    seq:
      - id: nodes
        type: chart_node
        repeat: eos
  chart_node:
    doc: |
      grid_x / grid_y are relative to the most recent group node's origin
      (a group node sets the origin for everything that follows it).
    seq:
      - id: node_type
        type: u2
        enum: chart_node_type
      - id: grid_x
        type: s2
      - id: grid_y
        type: s2
      - id: body
        type:
          switch-on: node_type
          cases:
            'chart_node_type::titled_box': chart_node_titled
            _: chart_node_plain
  chart_node_plain:
    doc: |
      8-byte node.  `param` meaning by type:
        group        chapter id — visibility is a global save flag OR
                     membership in the cleared-chapters list
        icon_box     packed icon selector: row = param >> 4, col = param & 0xF.
                     col == 0 means "draw nothing" (invisible spacer).
        vline        length in cells (drawn param * 0x26 px tall)
        hline        length in cells (drawn param * 0x18 px wide)
        page_marker  page index 0..4; grid_x/grid_y unused
    seq:
      - id: param
        type: u2
    instances:
      icon_row:
        value: param >> 4
      icon_col:
        value: param & 0x0f
  chart_node_titled:
    doc: '0x2A-byte node: a 3-cell-wide labelled box that jumps to a scenario.'
    seq:
      - id: scene_id
        type: s2
        doc: 'Target scenario id. NEGATIVE means the box is locked / unselectable.'
      - id: colour
        type: u2
        doc: 'Index 0..6 into the 7-entry ARGB palette at 0x001271B8.'
      - id: title
        size: 0x20
        doc: Inline Shift-JIS, NUL-padded.

# ═══════════════════════════════════════════════════════════════════════════
# Bytecode stream
# ═══════════════════════════════════════════════════════════════════════════

  bytecode_stream:
    seq:
      - id: instructions
        type: instruction
        repeat: eos

  instruction:
    doc: |
      Opcode byte plus a payload whose shape depends on BOTH the opcode and
      the game.  The switch key is `opcode` for umineko and `opcode + 0x100`
      for higurashi, which keeps one flat case table for both.

      Opcodes with no case listed take no payload: RET, MSGSIGNAL, MSGCLOSE,
      WIPEWAIT, EVBEGIN(umi)/EVEND, AUTOSAVE, LAYERCLEAR, CANVASINIT,
      SCREENINIT, KAKERA, FAKESELECT, and every scriptTrue stub slot.
    seq:
      - id: opcode
        type: u1
      - id: payload
        type:
          switch-on: 'opcode + (_root.is_higurashi ? 0x100 : 0)'
          cases:
            # ═══════════ UMINEKO ═══════════════════════════════════════════
            # ── Logic / Memory ────────────────────────────────────────────
            0x40: payload_unary
            0x41: payload_alu
            0x42: payload_stack
            0x43: payload_set_vars_mult_range
            0x44: payload_set_var_from_array
            0x45: payload_set_vars_mult_array
            # ── Flow Control ──────────────────────────────────────────────
            0x46: payload_jump_cond
            0x47: payload_jump_abs
            0x48: payload_call
            0x4a: payload_switch
            0x4b: payload_switch
            # ── Utilities ─────────────────────────────────────────────────
            0x4c: payload_rand_range
            0x4d: payload_push_mult
            0x4e: payload_pop_mult
            # ── System / Message / Scene ──────────────────────────────────
            0x80: payload_exit
            0x81: payload_sget
            0x82: payload_sset
            0x83: payload_wait
            0x84: payload_waitkey
            0x85: payload_msginit
            0x86: payload_msgget
            0x87: payload_msgwait
            0x8a: payload_msgcheck
            0x8b: payload_logset
            0x8c: payload_select
            0x8d: payload_wipe
            # ── Audio ─────────────────────────────────────────────────────
            0x9c: payload_bgm_play
            0x9d: payload_bgm_stop
            0x9e: payload_bgm_vol
            0x9f: payload_bgm_wait
            0xa0: payload_se_play
            0xa1: payload_se_stop
            0xa2: payload_se_stop_all
            0xa3: payload_se_vol
            0xa4: payload_se_wait
            0xa5: payload_se_once
            0xa6: payload_vibrate
            # ── Misc ──────────────────────────────────────────────────────
            0xb0: payload_saveinfo
            0xb1: payload_movie
            0xb2: payload_bgm_sync
            0xb7: payload_bgm_play2
            0xb8: payload_bgm_vol2
            0xb9: payload_voice_play
            0xba: payload_voice_wait
            0xbd: payload_tipsget
            # ── Layer / Canvas / Screen ───────────────────────────────────
            0xbe: payload_thropy
            0xbf: payload_char
            0xc1: payload_layer_load
            0xc2: payload_layer_ctrl
            0xc3: payload_layer_wait
            0xc4: payload_mask_load
            0xc5: payload_canvas
            0xc7: payload_canvas_ctrl
            0xc8: payload_canvas_wait
            0xca: payload_screen_ctrl
            0xcb: payload_screen_wait
            # ── Debug / Utility ───────────────────────────────────────────
            0xf0: payload_msgbox
            0xf1: payload_snapshot

            # ═══════════ HIGURASHI (opcode + 0x100) ════════════════════════
            # ── Logic / Memory — byte-identical encodings ─────────────────
            0x140: payload_unary
            0x141: payload_alu
            0x142: payload_stack
            0x143: payload_set_vars_mult_range
            0x144: payload_set_var_from_array
            0x145: payload_set_vars_mult_array
            # ── Flow Control ──────────────────────────────────────────────
            0x146: payload_jump_cond
            0x147: payload_jump_abs
            0x148: payload_call
            0x14a: payload_switch
            0x14b: payload_switch
            # ── Utilities ─────────────────────────────────────────────────
            0x14c: payload_rand_range
            0x14d: payload_push_mult
            0x14e: payload_pop_mult
            # ── System / Message / Scene ──────────────────────────────────
            0x180: payload_exit
            0x181: payload_sget
            0x182: payload_sset
            0x183: payload_wait
            0x184: payload_waitkey        # KEYWAIT — sizeof grew, wire did not
            0x185: payload_msginit
            0x186: payload_msgget         # MSGSET — same wire as Umineko MSGGET
            0x187: payload_msgwait
            0x18a: payload_msgcheck
            0x18b: payload_msgquake       # NEW
            0x18c: payload_logset
            0x18d: payload_select
            0x18e: payload_wipe_higu      # 2 lead bytes, mode-dependent gating
            # ── Audio (relocated from 0x9C.. to 0x90..) ───────────────────
            0x190: payload_bgm_play
            0x191: payload_bgm_stop
            0x192: payload_bgm_vol
            0x193: payload_bgm_wait
            0x194: payload_bgm_sync
            0x195: payload_se_play
            0x196: payload_se_stop
            0x197: payload_se_stop_all
            0x198: payload_se_vol
            0x199: payload_se_wait
            0x19a: payload_se_once
            0x19b: payload_vibrate        # decoded, but the ADV side is a no-op
            # ── Misc ──────────────────────────────────────────────────────
            0x1a0: payload_saveinfo_higu  # str8, not NUL-terminated
            0x1a1: payload_movie
            0x1a2: payload_evbegin        # gained one operand vs Umineko
            0x1a6: payload_voice_play_higu
            0x1a7: payload_voice_wait
            0x1aa: payload_tipsget
            0x1ac: payload_charsel        # NEW
            0x1ad: payload_otsuget        # NEW
            0x1ae: payload_chart_cmd      # NEW
            0x1af: payload_snrsel         # NEW
            0x1b1: payload_kakeraget      # NEW
            0x1b2: payload_quiz           # NEW
            0x1b4: payload_thropy         # TROPHY
            # ── Layer ─────────────────────────────────────────────────────
            0x1c1: payload_layer_load_higu   # one extra word before the mask
            0x1c2: payload_layer_ctrl
            0x1c3: payload_layer_wait
    instances:
      op_umi:
        value: opcode
        enum: op_code_umi
      op_higu:
        value: opcode
        enum: op_code_higu

# ═══════════════════════════════════════════════════════════════════════════
# Payload types — Logic / Memory  (identical in both games)
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

  payload_stack:
    doc: |
      0x42 OP_STACK — dst_var:u16, then RPN op stream.
      Stream is a series of s8 op_code bytes; a byte with bit 7 set terminates
      (and is consumed).  PUSH (0x00) is followed by a u16 operand.
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
# Payload types — Flow Control  (identical in both games)
# ═══════════════════════════════════════════════════════════════════════════

  payload_jump_cond:
    doc: "JMP_COND — mode:u8, op1:u16, op2:u16, target_addr:u32"
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
    doc: "JMP_ABS — target_addr:u32"
    seq:
      - id: target_addr
        type: u4

  payload_call:
    doc: "CALL — target_addr:u32"
    seq:
      - id: target_addr
        type: u4

  payload_switch:
    doc: "SWITCH/SWITCH_CALL — index_src:u16, table_size:u16, entries[table_size]:u32"
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
# Payload types — Utilities  (identical in both games)
# ═══════════════════════════════════════════════════════════════════════════

  payload_rand_range:
    doc: "RAND_RANGE — dst_var:u16, op1:u16, op2:u16"
    seq:
      - id: dst_var
        type: operand
      - id: op1
        type: operand
      - id: op2
        type: u2

  payload_push_mult:
    doc: "PUSH_MULT — num_records:u8, operands[num_records]:u16"
    seq:
      - id: num_operands
        type: u1
      - id: operands
        type: operand
        repeat: expr
        repeat-expr: num_operands

  payload_pop_mult:
    doc: "POP_MULT — num_records:u8, var_idx[num_records]:u16"
    seq:
      - id: num_var_idx
        type: u1
      - id: var_idx
        type: operand
        repeat: expr
        repeat-expr: num_var_idx

# ═══════════════════════════════════════════════════════════════════════════
# Payload types — System / Message / Scene
# ═══════════════════════════════════════════════════════════════════════════

  payload_exit:
    seq:
      - id: exit_code_src
        type: operand

  payload_sget:
    doc: |
      CMD_SGET — read a system/state flag into a script variable.
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
        doc: Logical variable index after encodeVariableRef bias.

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
    doc: 'Umineko WAITKEY / Higurashi KEYWAIT. One operand in both.'
    seq:
      - id: mode_src
        type: operand

  payload_msginit:
    seq:
      - id: msg_style
        type: operand
        doc: "Text presentation style: 0 = ADV (textbox), 1 = NVL (fullscreen)."
      - id: justification
        type: operand

  payload_msgget:
    doc: |
      Umineko CMD_MSGGET (0x86) / Higurashi CMD_MSGSET (0x86) — same wire.
      packed_header: lower 24 bits = base_flag_idx+1; bit 24 = is_sync.
      Followed by a u16-length-prefixed dialogue string (the length INCLUDES
      the trailing NUL).
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
      is_sync:
        value: (packed_header >> 24) & 1

  payload_msgwait:
    seq:
      - id: mode_src
        type: operand

  payload_msgcheck:
    doc: "Lower 24 bits of packed_id = base_flag_idx+1"
    seq:
      - id: packed_id
        type: u4
    instances:
      base_flag_idx:
        value: (packed_id & 0x00ffffff) - 1

  payload_msgquake:
    doc: 'Higurashi only (0x8B). Single operand. Never occurs in main.snr.'
    seq:
      - id: op1
        type: operand

  payload_logset:
    doc: "CMD_LOGSET — u16-length-prefixed inline string (length includes the NUL)"
    seq:
      - id: len_log_str
        type: u2
      - id: log_str
        size: len_log_str

  payload_select:
    doc: |
      CMD_SELECT (Umineko 0x8C / Higurashi 0x8D) — identical wire layout.
      choice_base_flag_idc: u16, flag_base_raw: u16, script_var_num: u16,
      visibility_bitmask: u16, then a str8 title and a str8 choices blob
      (null-delimited segments).
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

  payload_wipe:
    doc: |
      Umineko CMD_WIPE (0x8D).
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

  payload_wipe_higu:
    doc: |
      Higurashi CMD_WIPE (0x8E) — TWO leading bytes, and the mask gating is
      mode-dependent:
        mode == 0 → bits 0..3 each gate one operand word (as Umineko)
        mode != 0 → only bit 0 gates a word; bits 1..3 are ignored
      Every WIPE in Higurashi's main.snr has mode == 0, so the mode != 0
      branch is read off the handler at 0008466C but is not data-verified.
    seq:
      - id: mode
        type: u1
      - id: bitmask
        type: u1
      - id: mask_snr_id
        type: operand
        if: (bitmask & 0x01) != 0
      - id: duration_ticks
        type: operand
        if: 'mode == 0 and (bitmask & 0x02) != 0'
      - id: wipe_height
        type: operand
        if: 'mode == 0 and (bitmask & 0x04) != 0'
      - id: direction_flags
        type: operand
        if: 'mode == 0 and (bitmask & 0x08) != 0'
    instances:
      wait_for_completion:
        value: (bitmask >> 7) & 1

# ═══════════════════════════════════════════════════════════════════════════
# Payload types — Audio  (identical wire in both games)
# ═══════════════════════════════════════════════════════════════════════════

  payload_bgm_play:
    doc: "CMD_BGMPLAY — song_id, loop_num_records, volume_raw (0-255→/255.0f), fade_duration"
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
    doc: "CMD_SEPLAY — stream_id, se_id (→ se_bg_section), loop_num_records, volume_raw, fade_duration"
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
    doc: "CMD_SEONCE — sound_effect_id (→ se_bg_section), volume_raw, do_preload"
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
# Payload types — Misc
# ═══════════════════════════════════════════════════════════════════════════

  payload_saveinfo:
    doc: |
      Umineko CMD_SAVEINFO (0xB0) — type:u16 then a string.
      The handler actually uses SkipString8b (a u8 length prefix), but because
      the stored length always equals strlen+1, scanning to the NUL consumes
      exactly the same number of bytes.  Modelled as NUL-terminated here to
      stay byte-for-byte compatible with the existing decompiled output;
      `saveinfo_str` therefore carries the length byte as its first character.
    seq:
      - id: type
        type: u2
      - id: saveinfo_str
        terminator: 0

  payload_saveinfo_higu:
    doc: 'Higurashi CMD_SAVEINFO (0xA0) — operand type, then a str8 (length includes the NUL).'
    seq:
      - id: type
        type: operand
      - id: len_saveinfo_str
        type: u1
      - id: saveinfo_str
        size: len_saveinfo_str

  payload_movie:
    doc: "CMD_MOVIE — movie_id → movie_section"
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

  payload_evbegin:
    doc: |
      Higurashi CMD_EVBEGIN (0xA2) — one operand.  Umineko's EVBEGIN (0xB3)
      takes none; this is a genuine wire change (verified by falsification:
      assuming zero operands desyncs after 41,386 instructions).
    seq:
      - id: event_id
        type: operand

  payload_bgm_play2:
    doc: "Umineko CMD_BGMPLAY2 (0xB7) — new_song_id, old_song_id (both → bgm_section), loop_num_records, volume_raw, crossfade_delay"
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
    doc: Umineko only.
    seq:
      - id: volume_raw
        type: u2
      - id: fade_duration
        type: u2

  payload_voice_play:
    doc: |
      Umineko CMD_VOICEPLAY (0xB9) — modelled as five u16 operands
      (stream_id, voice_id → voice_section, loop, volume, fade).
      NOTE: the Umineko handler at 0008f370 in fact reads only a str8; this
      opcode does not occur in Umineko's main.snr, so the layout is untested
      and is kept as-is for output compatibility.
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

  payload_voice_play_higu:
    doc: |
      Higurashi CMD_VOICEPLAY (0xA6) — str8 clip path, then volume and a
      boolean flag operand.  The extra two words are the +8 sizeof growth
      seen on the ADV command object; a 5 x u16 reading desyncs after
      42,099 instructions.
    seq:
      - id: len_path
        type: u1
      - id: path
        size: len_path
        doc: 'e.g. "S10/40/430100047" plus a NUL — the length includes it.'
      - id: volume_raw
        type: operand
      - id: flag
        type: operand

  payload_voice_wait:
    seq:
      - id: wait_flags
        type: operand

  payload_tipsget:
    doc: "CMD_TIPSGET — num_records:u8, then num_records operand words (→ tips_section)"
    seq:
      - id: num_operands
        type: u1
      - id: operands
        type: operand
        repeat: expr
        repeat-expr: num_operands

# ═══════════════════════════════════════════════════════════════════════════
# Payload types — Higurashi-only commands
# ═══════════════════════════════════════════════════════════════════════════

  payload_charsel:
    doc: |
      Higurashi CMD_CHARSEL (0xAC) — the character-select overlay.
      Word 1 is stored as value-1 (a flag base index, not operand-resolved).
      Word 2 is +0x8000 var-ref encoded (the destination variable).
      Word 3 is read and its value discarded, but the read still advances PC.
      Word 4 is a resolved operand.  Occurs once in main.snr.
    seq:
      - id: flag_base_raw
        type: u2
      - id: dst_var_raw
        type: s2
      - id: unused
        type: u2
      - id: op1
        type: operand
    instances:
      flag_base_id:
        value: flag_base_raw - 1
      dst_var_idx:
        value: dst_var_raw + 0x8000

  payload_otsuget:
    doc: 'Higurashi CMD_OTSUGET (0xAD) — one operand. 21 occurrences.'
    seq:
      - id: op1
        type: operand

  payload_chart_cmd:
    doc: |
      Higurashi CMD_CHART (0xAE) — chart_kind:u8, then a count-prefixed
      operand list.  Observed chart_kind values are 0 and 1 only.
      843 occurrences, counts 1..2.
    seq:
      - id: chart_kind
        type: u1
      - id: num_operands
        type: u1
      - id: operands
        type: operand
        repeat: expr
        repeat-expr: num_operands

  payload_snrsel:
    doc: 'Higurashi CMD_SNRSEL (0xAF) — scenario select. One operand. 5 occurrences.'
    seq:
      - id: op1
        type: operand

  payload_kakeraget:
    doc: |
      Higurashi CMD_KAKERAGET (0xB1) — one operand, then a count-prefixed
      operand list.  116 occurrences, counts 1..6.
      (CMD_KAKERA 0xB0 and CMD_FAKESELECT 0xB3 take no operands at all.)
    seq:
      - id: op1
        type: operand
      - id: num_operands
        type: u1
      - id: operands
        type: operand
        repeat: expr
        repeat-expr: num_operands

  payload_quiz:
    doc: |
      Higurashi CMD_QUIZ (0xB2) — dst_var_raw is +0x8000 var-ref encoded
      (the answer destination); the remaining three are resolved operands.
      4 occurrences.
    seq:
      - id: dst_var_raw
        type: s2
      - id: op1
        type: operand
      - id: op2
        type: operand
      - id: op3
        type: operand
    instances:
      dst_var_idx:
        value: dst_var_raw + 0x8000

# ═══════════════════════════════════════════════════════════════════════════
# Payload types — Layer / Canvas / Screen
# ═══════════════════════════════════════════════════════════════════════════

  payload_thropy:
    doc: 'Umineko THROPY (0xBE) / Higurashi TROPHY (0xB4). The class is TROPHY in both.'
    seq:
      - id: thropy_id
        type: operand

  payload_char:
    doc: Umineko only (0xBF).
    seq:
      - id: char_tree_snapshot
        type: operand
        doc: Char tree snapshot description index.
      - id: starting_page
        type: operand
        doc: Starting page for the char display tree.

  payload_layer_load:
    doc: |
      Umineko CMD_LAYERLOAD (0xC1).
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

  payload_layer_load_higu:
    doc: |
      Higurashi CMD_LAYERLOAD (0xC1) — one EXTRA operand word before the
      field mask (the +4 sizeof growth on the ADV command object).  The mask
      still gates exactly 8 optional words: the decode loop is
      `do {...} while (i < 8)` at 00086578, same shape as Umineko's.
      Reading only two words before the mask desyncs after 605 instructions.
      Masks observed in main.snr are 0x00, 0x01 and 0x03 only, so bits 3-7
      are structurally certain but not data-verified.
    seq:
      - id: layer_id
        type: operand
      - id: layer_type
        type: operand
      - id: extra
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
    doc: "CMD_LAYERCTRL (0xC2) — identical wire in both games."
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
    doc: "Umineko CMD_MASKLOAD (0xC4) — mask_id (→ mask_section), param1. Dropped in Higurashi."
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
    doc: Umineko only.
    seq:
      - id: canvas_id
        type: operand

  payload_canvas_ctrl:
    doc: "Umineko CMD_CANVASCTRL (0xC7) — anim_type:u16, field_mask:u8, 0-8 optional operand words"
    seq:
      - id: anim_type
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
    doc: Umineko only.
    seq:
      - id: anim_type
        type: operand

  payload_screen_ctrl:
    doc: "Umineko CMD_SCREENCTR (0xCA) — anim_type:u16, field_mask:u8, 0-8 optional operand words"
    seq:
      - id: anim_type
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

  payload_screen_wait:
    doc: Umineko only.
    seq:
      - id: anim_type
        type: operand

# ═══════════════════════════════════════════════════════════════════════════
# Payload types — Debug / Utility (Umineko only)
# ═══════════════════════════════════════════════════════════════════════════

  payload_msgbox:
    doc: "Umineko CMD_MSGBOX (0xF0) — str8: u8 length prefix + string body"
    seq:
      - id: len_message
        type: u1
      - id: message
        size: len_message

  payload_snapshot:
    doc: "Umineko CMD_SNAPSHOT (0xF1) — str8 filename_base, index:u16; output: <base>_%05d.bmp"
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
  snr_version:
    0: umineko
    1: higurashi

  chart_node_type:
    0: group
    1: titled_box
    2: icon_box
    3: vline
    4: hline
    5: page_marker

  # ── Umineko opcode table (EBOOT.ELF / EBOOT-CHIRU.elf) ────────────────────
  op_code_umi:
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

  # ── Higurashi opcode table (EBOOT-HIGURASHI.elf) ──────────────────────────
  # Names are the RTTI class names of the ADV command each handler builds.
  op_code_higu:
    # 0x00–0x3F: scriptTrue no-op stubs
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
    0x84: cmd_keywait
    0x85: cmd_msginit
    0x86: cmd_msgset
    0x87: cmd_msgwait
    0x88: cmd_msgsignal
    0x89: cmd_msgclose
    0x8a: cmd_msgcheck
    0x8b: cmd_msgquake
    0x8c: cmd_logset
    0x8d: cmd_select
    0x8e: cmd_wipe
    0x8f: cmd_wipewait
    0x90: cmd_bgmplay
    0x91: cmd_bgmstop
    0x92: cmd_bgmvol
    0x93: cmd_bgmwait
    0x94: cmd_bgmsync
    0x95: cmd_seplay
    0x96: cmd_sestop
    0x97: cmd_sestopall
    0x98: cmd_sevol
    0x99: cmd_sewait
    0x9a: cmd_seonce
    0x9b: cmd_vibrate
    # 0x9C–0x9F: vacated by the audio block move
    0xa0: cmd_saveinfo
    0xa1: cmd_movie
    0xa2: cmd_evbegin
    0xa3: cmd_evend
    # 0xA4: hole
    0xa5: cmd_autosave
    0xa6: cmd_voiceplay
    0xa7: cmd_voicewait
    # 0xA8–0xA9: stubs
    0xaa: cmd_tipsget
    # 0xAB: stub
    0xac: cmd_charsel
    0xad: cmd_otsuget
    0xae: cmd_chart
    0xaf: cmd_snrsel
    0xb0: cmd_kakera
    0xb1: cmd_kakeraget
    0xb2: cmd_quiz
    0xb3: cmd_fakeselect
    0xb4: cmd_trophy
    # 0xB5–0xBF: vacated by the moves above
    0xc0: cmd_layerclear
    0xc1: cmd_layerload
    0xc2: cmd_layerctrl
    0xc3: cmd_layerwait
    # 0xC4–0xFF: scriptTrue stubs (MASKLOAD, CANVAS*, SCREEN*, MSGBOX and
    #            SNAPSHOT are all gone)

  anim_type:
    0x00: z_order                    # used solely to determine layer stable ordering in canvas drawing
    0x01: fade_alpha
    0x02: fade_blue
    0x03: fade_green
    0x04: fade_red
    0x05: image_filter
    0x06: blend_mode
    0x07: x_pos
    0x08: y_pos
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
    0x13: butsup_lipsync_enable
    0x14: rain_particle_spawn_rate   # Permille, max 50 concurrent for raindrop, 5 for hanabira
    0x15: rain_particle_size         # Permille, normalized to [0.0, 1.0] -> scale [0.0, 1.125]
    0x16: rain_particle_rotation_z   # Permille, normalized to [-1.0, 1.0] --> [-pi/3, pi/3] radians -> [-60º, 60º]
                                     #   with random values up to 66º raindrop, 88º hanabira
    0x17: rain_anim_paused
    0x18: swirl_phase
    0x19: swirl_strength
    0x1a: swirl_shrink
    0x1b: ripple_x_frequency
    0x1c: ripple_x_strength
    0x1d: ripple_x_phase_delta
    0x1e: ripple_y_frequency
    0x1f: ripple_y_strength
    0x20: ripple_y_phase_delta
    0x21: pixellate                  # size of the pixel blocks, must be >0
    0x22: gaussian_blur_sigma        # multiplied by 0.001 and squared
    0x23: breakup
    0x24: effectlayer_flip
    0x25: screen_oscillator_enabled
    0x26: screen_freeze_zoom         # Permille, zoom screen freeze buffer into fugue
                                     #   point at the center for transitions 1000 = full screen, 0 = point
    0x27: screen_freeze_alpha        # 0-255 direct alpha of the freeze screen buffer

  layer_type:
    0x01: layer_type_tile
    0x02: layer_type_picture
    0x03: layer_type_bustup
    0x04: layer_type_anime
    0x05: layer_type_rain
    0x06: layer_type_effect

  msg_style:
    0: adv
    1: nvl

  justification:
    0: line_left_justify
    2: line_center_align
    3: line_right_justify

  layer_wait_anim_type:
    0x00: z_order
    0x01: alpha
    0x02: blue
    0x03: green
    0x04: red
    0x05: x_pos
    0x06: y_pos
    0x07: x_pivot
    0x08: y_pivot
    0x09: x_scale
    0x0a: y_scale
    0x0b: rotation_z
    0x0c: shake_amplitude
    0x0d: shake_duration
    0x0e: bob_amplitude
    0x0f: bob_duration
    0x10: anime
    0x11: rain_spawn_rate
    0x12: rain_particle_size
    0x13: rain_particle_rot_z
    0x14: swirl_phase
    0x15: swirl_strength
    0x16: swirl_shrink
    0x17: ripple_x_frequency
    0x18: ripple_x_strength
    0x19: ripple_x_phase_delta
    0x1a: ripple_y_offset
    0x1b: ripple_y_strength
    0x1c: ripple_y_phase_delta
    0x1d: pixellate
    0x1e: gaussian_blur_sigma
    0x1f: breakup
    0x20: screen_freeze_zoom
    0x21: screen_freeze_alpha
