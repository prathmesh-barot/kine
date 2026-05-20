package main

import "core:fmt"
import "core:os"
import "core:strings"

Last_Change :: struct {
    kind:         Undo_Kind,
    text:         string,
    cursor_after: Vec2,
}

Pending_Two_Key :: struct {
    prefix: string,
    handler: proc(ed: ^Editor, key: Key),
}

Operator_Kind :: enum {
    None,
    Delete,
    Change,
    Yank,
    Indent,
    Dedent,
    AutoIndent,
    Uppercase,
    Lowercase,
    ToggleCase,
}

Pending_Op :: struct {
    kind:      Operator_Kind,
    count:     int,
    motion:    proc(ed: ^Editor, w: ^Window, buf: ^Buffer, count: int) -> (int, int),
    text_obj:  bool,
}

Jump_Entry :: struct {
    buf_id: int,
    row:    int,
    col:    int,
}

Editor :: struct {
    buffers:          [dynamic]^Buffer,
    windows:          [dynamic]^Window,
    tabs:             [dynamic]Tab,
    active_tab:       int,
    active_window:    ^Window,
    mode:             Mode,
    prev_mode:        Mode,
    command_buf:      [dynamic]u8,
    command_buf_len:  int,
    command_history:  [dynamic]string,
    count_buf:        [16]u8,
    count_buf_len:    int,
    pending_two_key:  Maybe(Pending_Two_Key),
    pending_op:       Maybe(Pending_Op),
    unnamed_register: string,
    undo_stack:       Undo_Stack,
    last_change:      Last_Change,
    message:          string,
    color_mode:       Color_Mode,
    term_cols:        int,
    term_rows:        int,
    term_state:       Terminal_State,
    output_buf:       Output_Buffer,
    current_screen:   Screen,
    desired_screen:   Screen,
    running:          bool,
    search_pattern:   string,
    search_direction: int,
    jumplist:         [dynamic]Jump_Entry,
    jump_idx:         int,
}

Tab :: struct {
    name: string,
}

next_buffer_id: int = 1

editor_next_buffer_id :: proc() -> int {
    id := next_buffer_id
    next_buffer_id += 1
    return id
}

editor_add_count_digit :: proc(ed: ^Editor, digit: int) {
    if ed.count_buf_len < len(ed.count_buf) {
        ed.count_buf[ed.count_buf_len] = u8('0' + digit)
        ed.count_buf_len += 1
    }
}

ed_add_count_digit :: proc(ed: ^Editor, digit: int) {
    editor_add_count_digit(ed, digit)
}

ed_get_count :: proc(ed: ^Editor) -> int {
    if ed.count_buf_len == 0 { return 1 }
    count := 0
    for i in 0 ..< ed.count_buf_len {
        count = count * 10 + int(ed.count_buf[i] - '0')
    }
    ed.count_buf_len = 0
    return max(1, count)
}

ed_pending_two_key :: proc(ed: ^Editor, prefix: string, handler: proc(ed: ^Editor, key: Key)) {
    ed.pending_two_key = Pending_Two_Key{prefix = prefix, handler = handler}
}

insert_mode_enter_wrapper :: proc(ed: ^Editor) {
    insert_mode_enter(ed)
}

process_key :: proc(ed: ^Editor, key: Key) {
    if pending, ok := ed.pending_two_key.?; ok {
        ed.pending_two_key = nil
        pending.handler(ed, key)
        return
    }

    switch ed.mode {
    case .Normal:
        normal_mode_handle_key(ed, key)
    case .Insert, .Replace, .Insert_Completion:
        insert_mode_handle_key(ed, key)
    case .Command, .Search_Forward, .Search_Backward:
        command_mode_handle_key(ed, key)
    case .Visual_Char, .Visual_Line, .Visual_Block:
        if key.special == .Escape {
            ed.mode = .Normal
            clear_visual(ed)
        } else {
            visual_mode_handle_key(ed, key)
        }
    case .Operator_Pending:
        operator_pending_handle_key(ed, key)
    }
}

operator_pending_handle_key :: proc(ed: ^Editor, key: Key) {
    w := ed.active_window
    if w == nil { ed.mode = .Normal; return }

    if key.special == .Escape {
        ed.mode = .Normal
        ed.pending_op = nil
        return
    }

    op, has_op := ed.pending_op.?
    if !has_op { ed.mode = .Normal; return }

    buf := w.buffer
    count := op.count

    switch {
    case key.codepoint == 'w':
        start := line_cursor_to_abs(buf, w.cursor)
        for i := 0; i < count; i += 1 {
            cursor_move_word_forward(&w.cursor, buf)
        }
        end := line_cursor_to_abs(buf, w.cursor)
        apply_operator(ed, op.kind, start, end)

    case key.codepoint == 'b':
        start := line_cursor_to_abs(buf, w.cursor)
        for i := 0; i < count; i += 1 {
            cursor_move_word_backward(&w.cursor, buf)
        }
        end := line_cursor_to_abs(buf, w.cursor)
        if end > start { end, start = start, end }
        apply_operator(ed, op.kind, end, start)

    case key.codepoint == 'W':
        start := line_cursor_to_abs(buf, w.cursor)
        for i := 0; i < count; i += 1 {
            cursor_move_WORD_forward(&w.cursor, buf)
        }
        end := line_cursor_to_abs(buf, w.cursor)
        apply_operator(ed, op.kind, start, end)

    case key.codepoint == 'B':
        start := line_cursor_to_abs(buf, w.cursor)
        for i := 0; i < count; i += 1 {
            cursor_move_WORD_backward(&w.cursor, buf)
        }
        end := line_cursor_to_abs(buf, w.cursor)
        if end > start { end, start = start, end }
        apply_operator(ed, op.kind, end, start)

    case key.codepoint == 'e':
        start := line_cursor_to_abs(buf, w.cursor)
        for i := 0; i < count; i += 1 {
            cursor_move_word_end_forward(&w.cursor, buf)
        }
        end := line_cursor_to_abs(buf, w.cursor) + 1
        apply_operator(ed, op.kind, start, end)

    case key.codepoint == 'E':
        start := line_cursor_to_abs(buf, w.cursor)
        for i := 0; i < count; i += 1 {
            cursor_move_WORD_end_forward(&w.cursor, buf)
        }
        end := line_cursor_to_abs(buf, w.cursor) + 1
        apply_operator(ed, op.kind, start, end)

    case key.codepoint == 'h' || key.special == .Arrow_Left:
        start := line_cursor_to_abs(buf, w.cursor)
        cursor_move_left(&w.cursor, buf)
        end := line_cursor_to_abs(buf, w.cursor)
        apply_operator(ed, op.kind, end, start)

    case key.codepoint == 'l' || key.special == .Arrow_Right:
        start := line_cursor_to_abs(buf, w.cursor)
        cursor_move_right(&w.cursor, buf)
        end := line_cursor_to_abs(buf, w.cursor)
        apply_operator(ed, op.kind, start, end)

    case key.codepoint == 'j' || key.special == .Arrow_Down:
        start := line_cursor_to_abs(buf, w.cursor)
        cursor_move_down(&w.cursor, buf, count)
        end := line_to_abs_pos(buf, w.cursor.row) + w.cursor.col
        apply_operator(ed, op.kind, start, end)

    case key.codepoint == 'k' || key.special == .Arrow_Up:
        start := line_cursor_to_abs(buf, w.cursor)
        cursor_move_up(&w.cursor, buf, count)
        end := line_to_abs_pos(buf, w.cursor.row) + w.cursor.col
        if end > start { end, start = start, end }
        apply_operator(ed, op.kind, end, start)

    case key.codepoint == '0':
        start := line_cursor_to_abs(buf, w.cursor)
        end := line_to_abs_pos(buf, w.cursor.row)
        apply_operator(ed, op.kind, end, start)

    case key.codepoint == '$':
        start := line_cursor_to_abs(buf, w.cursor)
        line := pt_get_line(&buf.piece_table, w.cursor.row)
        end := line_to_abs_pos(buf, w.cursor.row) + len(line)
        apply_operator(ed, op.kind, start, end)

    case key.codepoint == '^':
        start := line_cursor_to_abs(buf, w.cursor)
        cursor_move_to_first_nonblank(&w.cursor, buf)
        end := line_cursor_to_abs(buf, w.cursor)
        apply_operator(ed, op.kind, end, start)

    case key.codepoint == 'G':
        start := line_cursor_to_abs(buf, w.cursor)
        if ed.count_buf_len > 0 {
            cursor_move_to_line(&w.cursor, buf, count - 1)
        } else {
            cursor_move_to_last_line(&w.cursor, buf)
        }
        end := line_cursor_to_abs(buf, w.cursor) + line_byte_length(buf, w.cursor.row)
        apply_operator(ed, op.kind, start, end)

    case key.codepoint == 'g':
        ed_pending_two_key(ed, "g", proc(ed: ^Editor, key: Key) {
            if key.codepoint == 'g' {
                op, _ := ed.pending_op.?
                w := ed.active_window
                buf := w.buffer
                start := line_cursor_to_abs(buf, w.cursor)
                cursor_move_to_first_line(&w.cursor, buf)
                end := line_cursor_to_abs(buf, w.cursor) + line_byte_length(buf, w.cursor.row)
                apply_operator(ed, op.kind, start, end)
            }
        })

    case key.codepoint == 'w' || key.codepoint == 'W' ||
         key.codepoint == 'i' || key.codepoint == 'a':
        handle_text_object(ed, key)

    case:
        ed.mode = .Normal
        ed.pending_op = nil
    }
}

apply_operator :: proc(ed: ^Editor, kind: Operator_Kind, start, end: int) {
    w := ed.active_window
    buf := w.buffer
    if end <= start { ed.mode = .Normal; ed.pending_op = nil; return }

    pos := min(start, end)
    length := abs(end - start)

    #partial switch kind {
    case .Delete:
        text := pt_substring(&buf.piece_table, pos, length)
        ed.unnamed_register = text
        pt_delete(&buf.piece_table, pos, length)
        buf.modified = true
        if w.cursor.row >= buf.piece_table.line_count {
            w.cursor.row = buf.piece_table.line_count - 1
        }

    case .Yank:
        text := pt_substring(&buf.piece_table, pos, length)
        ed.unnamed_register = text

    case .Change:
        text := pt_substring(&buf.piece_table, pos, length)
        ed.unnamed_register = text
        pt_delete(&buf.piece_table, pos, length)
        buf.modified = true
        if w.cursor.row >= buf.piece_table.line_count {
            w.cursor.row = buf.piece_table.line_count - 1
        }
        insert_mode_enter(ed)
        ed.mode = .Insert
        ed.prev_mode = .Normal

    case:
        ed.mode = .Normal
    }

    ed.pending_op = nil
    scroll_into_view(w)
}

command_mode_handle_key :: proc(ed: ^Editor, key: Key) {
    switch {
    case key.special == .Escape:
        ed.mode = ed.prev_mode
        ed.command_buf_len = 0

    case key.special == .Enter || key.codepoint == '\n' || key.codepoint == '\r':
        cmd := string(ed.command_buf[:ed.command_buf_len])
        if len(cmd) > 0 {
            append(&ed.command_history, strings.clone(cmd))
        }
        if ed.mode == .Search_Forward || ed.mode == .Search_Backward {
            search_execute(ed, cmd)
        } else {
            execute_command(ed, cmd)
        }
        ed.command_buf_len = 0
        if ed.mode != .Normal && ed.mode != .Insert {
            ed.mode = .Normal
        }

    case key.special == .Backspace || key.codepoint == 0x7f:
        if ed.command_buf_len > 0 {
            ed.command_buf_len -= 1
        }

    case key.codepoint == 'u' && key.mods == {.Ctrl}:
        ed.command_buf_len = 0

    case key.codepoint == 'w' && key.mods == {.Ctrl}:
        for ed.command_buf_len > 0 {
            if ed.command_buf[ed.command_buf_len - 1] == ' ' { break }
            ed.command_buf_len -= 1
        }

    case key.special == .Tab:
        tab_complete(ed)

    case key.codepoint != 0:
        if ed.command_buf_len < cap(ed.command_buf) {
            ch := u8(key.codepoint)
            append(&ed.command_buf, ch)
            ed.command_buf_len += 1
        }
    }
}

tab_complete :: proc(ed: ^Editor) {
    if ed.command_buf_len == 0 { return }
    cmd := string(ed.command_buf[:ed.command_buf_len])
    commands := []string{"q", "q!", "w", "wq", "x", "e ", "edit ", "bn", "bnext", "bp", "bprev", "b ", "ls", "buffers", "noh", "nohlsearch", "help", "version", "sp", "vsp", "new", "vnew", "tabnew", "tabc", "tabn", "tabp", "set", "colorscheme", "source"}

    for c in commands {
        if strings.has_prefix(c, cmd) && c != cmd {
            clear(&ed.command_buf)
            append(&ed.command_buf, ..transmute([]u8)c)
            ed.command_buf_len = len(c)
            return
        }
    }
}

execute_command :: proc(ed: ^Editor, cmd: string) {
    if cmd == "" { return }

    switch {
    case strings.has_prefix(cmd, "noh") || cmd == "nohlsearch":
        ed.message = ""
        clear_search_highlight(ed)

    case cmd == "wq" || cmd == "x":
        if ed.active_window != nil && ed.active_window.buffer != nil {
            buf := ed.active_window.buffer
            err := buffer_save(buf, buf.filepath)
            if err != nil {
                ed.message = fmt.tprintf("Error saving: %v", err)
                return
            }
        }
        ed.running = false

    case cmd == "q!":
        ed.running = false

    case cmd == "q" || strings.has_prefix(cmd, "quit"):
        modified := false
        for buf in ed.buffers {
            if buf.modified { modified = true; break }
        }
        if modified {
            ed.message = "No write since last change (add ! to force)"
            return
        }
        ed.running = false

    case cmd == "qa" || cmd == "qa!":
        ed.running = false

    case cmd == "wa":
        for buf in ed.buffers {
            if buf.filepath != "" {
                buffer_save(buf, buf.filepath)
            }
        }
        ed.message = "All buffers saved"

    case strings.has_prefix(cmd, "w ") || cmd == "w":
        save_cmd := cmd
        space_idx := strings.index(save_cmd, " ")
        save_path := ""
        if space_idx != -1 {
            save_path = strings.trim_space(save_cmd[space_idx + 1:])
        }
        if ed.active_window != nil && ed.active_window.buffer != nil {
            buf := ed.active_window.buffer
            path := buf.filepath
            if save_path != "" {
                path = save_path
            }
            err := buffer_save(buf, path)
            if err != nil {
                ed.message = fmt.tprintf("Error saving: %v", err)
            } else {
                written := buf.piece_table.char_count
                ed.message = fmt.tprintf("'%s' %dL %dB written", buf.name, buf.piece_table.line_count, written)
            }
        }

    case strings.has_prefix(cmd, "e ") || strings.has_prefix(cmd, "edit "):
        space_idx := strings.index(cmd, " ")
        if space_idx != -1 {
            path := strings.trim_space(cmd[space_idx + 1:])
            buf, err := buffer_open(path)
            if err != nil {
                ed.message = fmt.tprintf("Cannot open '%s': %v", path, err)
            } else {
                if ed.active_window != nil {
                    ed.active_window.buffer = buf
                    cursor_init(&ed.active_window.cursor)
                    ed.active_window.scroll_row = 0
                    ed.active_window.scroll_col = 0
                }
                append(&ed.buffers, buf)
                ed.message = fmt.tprintf("'%s' %dL, %dB", buf.name, buf.piece_table.line_count, buf.piece_table.char_count)
            }
        }

    case strings.has_prefix(cmd, "bn") || strings.has_prefix(cmd, "bnext"):
        cycle_buffer(ed, 1)

    case strings.has_prefix(cmd, "bp") || strings.has_prefix(cmd, "bprev"):
        cycle_buffer(ed, -1)

    case strings.has_prefix(cmd, "b "):
        space_idx := strings.index(cmd, " ")
        if space_idx != -1 {
            name := strings.trim_space(cmd[space_idx + 1:])
            for buf in ed.buffers {
                if buf.name == name || strings.contains(buf.filepath, name) {
                    ed.active_window.buffer = buf
                    cursor_init(&ed.active_window.cursor)
                    ed.active_window.scroll_row = 0
                    ed.active_window.scroll_col = 0
                    break
                }
            }
        }

    case strings.has_prefix(cmd, "ls") || strings.has_prefix(cmd, "buffers"):
        list_buffers(ed)

    case strings.has_prefix(cmd, "h") || strings.has_prefix(cmd, "help"):
        ed.message = "kine - Odin Modal Text Editor (Phase 1)"

    case strings.has_prefix(cmd, "version"):
        ed.message = "kine v0.1.0 - Odin dev-2026-05"

    case strings.has_prefix(cmd, "set "):
        space_idx := strings.index(cmd, " ")
        if space_idx != -1 {
            opt := strings.trim_space(cmd[space_idx + 1:])
            ed.message = fmt.tprintf("Option '%s' not yet implemented", opt)
        }

    case:
        ed.message = fmt.tprintf("Unknown command: %s", strings.split(cmd, " ")[0])
    }
}

cycle_buffer :: proc(ed: ^Editor, dir: int) {
    if len(ed.buffers) <= 1 { return }
    current_buf := ed.active_window.buffer
    idx := -1
    for b, i in ed.buffers {
        if b.id == current_buf.id { idx = i; break }
    }
    if idx < 0 { return }
    new_idx := (idx + dir) % len(ed.buffers)
    if new_idx < 0 { new_idx += len(ed.buffers) }
    ed.active_window.buffer = ed.buffers[new_idx]
    cursor_init(&ed.active_window.cursor)
    ed.active_window.scroll_row = 0
    ed.active_window.scroll_col = 0
}

list_buffers :: proc(ed: ^Editor) {
    buf := strings.Builder{}
    strings.builder_init(&buf)
    for b, i in ed.buffers {
        fmt.sbprintf(&buf, "%3d %s %s\n", i + 1,
            b.modified ? "+" : " ",
            b.name)
    }
    ed.message = strings.to_string(buf)
}

editor_init :: proc() -> bool {
    ed := &editor
    ed.buffers = make([dynamic]^Buffer, 0, 4)
    ed.windows = make([dynamic]^Window, 0, 4)
    ed.tabs = make([dynamic]Tab, 0, 4)
    ed.command_buf = make([dynamic]u8, 0, 256)
    ed.command_history = make([dynamic]string, 0, 64)
    ed.mode = .Normal
    ed.prev_mode = .Normal
    ed.running = true
    ed.message = ""
    ed.unnamed_register = ""
    ed.count_buf_len = 0
    ed.pending_two_key = nil
    ed.pending_op = nil
    ed.last_change = Last_Change{}
    ed.color_mode = detect_color_mode()
    ed.search_pattern = ""
    ed.search_direction = 1
    ed.jumplist = make([dynamic]Jump_Entry, 0, 100)
    ed.jump_idx = -1
    log_init()

    if !enter_raw_mode(&ed.term_state) {
        fmt.eprintln("Failed to enter raw mode")
        return false
    }

    signal_setup()

    cols, rows, ok := get_terminal_size()
    if !ok {
        cols, rows = 80, 24
    }
    ed.term_cols = cols
    ed.term_rows = rows

    ed.active_tab = 0
    append(&ed.tabs, Tab{name = "1"})

    ob_init(&ed.output_buf)

    ansi_enter_alt_screen(&ed.output_buf)
    ansi_cursor_hide(&ed.output_buf)
    ansi_cursor_shape_block(&ed.output_buf)
    ob_flush(&ed.output_buf)

    screen_init(&ed.current_screen, rows, cols)
    screen_init(&ed.desired_screen, rows, cols)

    undo_stack_init(&ed.undo_stack)
    insert_start_text = make([dynamic]u8, 0, 256)

    buf, _ := buffer_new_scratch()
    append(&ed.buffers, buf)

    w := new(Window)
    window_init(w, buf)
    w.id = 0
    w.top = 0
    w.left = 0
    w.width = cols
    w.height = rows - 2
    w.is_active = true
    append(&ed.windows, w)
    ed.active_window = w

    if len(os.args) > 1 {
        file_buf, err := buffer_open(os.args[1])
        if err == nil {
            ed.active_window.buffer = file_buf
            _, has_scratch := find_scratch_buffer()
            if has_scratch {
                for b, i in ed.buffers {
                    if b.filepath == "" && !b.modified {
                        buffer_close(b)
                        ordered_remove(&ed.buffers, i)
                        break
                    }
                }
            }
            append(&ed.buffers, file_buf)
        }
    }

    return true
}

editor_shutdown :: proc() {
    ed := &editor

    ansi_cursor_show(&ed.output_buf)
    ansi_cursor_shape_block(&ed.output_buf)
    ansi_exit_alt_screen(&ed.output_buf)
    ob_flush(&ed.output_buf)

    exit_raw_mode(&ed.term_state)
    log_destroy()
}

editor_resize :: proc() {
    cols, rows, ok := get_terminal_size()
    if !ok { return }

    ed := &editor
    if cols == ed.term_cols && rows == ed.term_rows { return }

    ed.term_cols = cols
    ed.term_rows = rows

    screen_destroy(&ed.current_screen)
    screen_destroy(&ed.desired_screen)
    screen_init(&ed.current_screen, rows, cols)
    screen_init(&ed.desired_screen, rows, cols)

    for w in ed.windows {
        w.width = cols
        w.height = rows - 2
    }
}

find_scratch_buffer :: proc() -> (^Buffer, bool) {
    for buf in editor.buffers {
        if buf.filepath == "" && !buf.modified {
            return buf, true
        }
    }
    return nil, false
}

editor: Editor

ordered_remove :: proc(arr: ^[dynamic]$T, index: int) {
    for i := index; i < len(arr) - 1; i += 1 {
        arr[i] = arr[i + 1]
    }
    resize(arr, len(arr) - 1)
}

clear_search_highlight :: proc(ed: ^Editor) {
    ed.search_pattern = ""
}

search_execute :: proc(ed: ^Editor, pattern: string) {
    if pattern == "" { return }
    ed.search_pattern = strings.clone(pattern)
    w := ed.active_window
    buf := w.buffer
    search_forward(ed, buf, 1)
}

search_forward :: proc(ed: ^Editor, buf: ^Buffer, dir: int) {
    if ed.search_pattern == "" { return }
    w := ed.active_window
    pattern := ed.search_pattern
    start := line_cursor_to_abs(buf, w.cursor) + (1 if dir > 0 else 0)
    total := buf.piece_table.char_count
    dir_sign := dir

    if dir_sign > 0 {
        for pos := start; pos < total; pos += 1 {
            if pos + len(pattern) <= total {
                match := true
                for i := 0; i < len(pattern); i += 1 {
                    if pt_char_at(&buf.piece_table, pos + i) != pattern[i] {
                        match = false
                        break
                    }
                }
                if match {
                    line := 0
                    for ls in buf.piece_table.line_starts {
                        if ls > pos { break }
                        line += 1
                    }
                    line -= 1
                    line_start := buf.piece_table.line_starts[line]
                    w.cursor.row = line
                    w.cursor.col = pos - line_start
                    w.cursor.preferred_col = w.cursor.col
                    scroll_into_view(w)
                    return
                }
            }
        }
        for pos := 0; pos < start; pos += 1 {
            if pos + len(pattern) <= total {
                match := true
                for i := 0; i < len(pattern); i += 1 {
                    if pt_char_at(&buf.piece_table, pos + i) != pattern[i] {
                        match = false
                        break
                    }
                }
                if match {
                    line := 0
                    for ls in buf.piece_table.line_starts {
                        if ls > pos { break }
                        line += 1
                    }
                    line -= 1
                    line_start := buf.piece_table.line_starts[line]
                    w.cursor.row = line
                    w.cursor.col = pos - line_start
                    w.cursor.preferred_col = w.cursor.col
                    scroll_into_view(w)
                    return
                }
            }
        }
    } else {
        for pos := start - 1; pos >= 0; pos -= 1 {
            if pos + len(pattern) <= total {
                match := true
                for i := 0; i < len(pattern); i += 1 {
                    if pt_char_at(&buf.piece_table, pos + i) != pattern[i] {
                        match = false
                        break
                    }
                }
                if match {
                    line := 0
                    for ls in buf.piece_table.line_starts {
                        if ls > pos { break }
                        line += 1
                    }
                    line -= 1
                    line_start := buf.piece_table.line_starts[line]
                    w.cursor.row = line
                    w.cursor.col = pos - line_start
                    w.cursor.preferred_col = w.cursor.col
                    scroll_into_view(w)
                    return
                }
            }
        }
        for pos := total - 1; pos >= start; pos -= 1 {
            if pos + len(pattern) <= total {
                match := true
                for i := 0; i < len(pattern); i += 1 {
                    if pt_char_at(&buf.piece_table, pos + i) != pattern[i] {
                        match = false
                        break
                    }
                }
                if match {
                    line := 0
                    for ls in buf.piece_table.line_starts {
                        if ls > pos { break }
                        line += 1
                    }
                    line -= 1
                    line_start := buf.piece_table.line_starts[line]
                    w.cursor.row = line
                    w.cursor.col = pos - line_start
                    w.cursor.preferred_col = w.cursor.col
                    scroll_into_view(w)
                    return
                }
            }
        }
    }
    ed.message = fmt.tprintf("Pattern not found: %s", pattern)
}

search_word_under_cursor :: proc(ed: ^Editor, dir: int) {
    w := ed.active_window
    buf := w.buffer
    line := pt_get_line(&buf.piece_table, w.cursor.row)
    if len(line) == 0 { return }

    start := w.cursor.col
    for start > 0 && is_word_char(line[start]) { start -= 1 }
    if !is_word_char(line[start]) && start < len(line) - 1 { start += 1 }

    end := w.cursor.col
    for end < len(line) && is_word_char(line[end]) { end += 1 }

    if end > start {
        word := strings.clone(line[start:end])
        ed.search_pattern = word
        w.cursor.col = start
        w.cursor.preferred_col = start
        search_forward(ed, buf, dir)
    }
}

// jump_back :: proc(ed: ^Editor) {
//     if ed.jump_idx > 0 {
//         ed.jump_idx -= 1
//         entry := ed.jumplist[ed.jump_idx]
//         for buf in ed.buffers {
//             if buf.id == entry.buf_id {
//                 ed.active_window.buffer = buf
//                 ed.active_window.cursor.row = entry.row
//                 ed.active_window.cursor.col = entry.col
//                 ed.active_window.cursor.preferred_col = entry.col
//                 break
//             }
//         }
//     }
// }

// jump_forward :: proc(ed: ^Editor) {
//     if ed.jump_idx < len(ed.jumplist) - 1 {
//         ed.jump_idx += 1
//         entry := ed.jumplist[ed.jump_idx]
//         for buf in ed.buffers {
//             if buf.id == entry.buf_id {
//                 ed.active_window.buffer = buf
//                 ed.active_window.cursor.row = entry.row
//                 ed.active_window.cursor.col = entry.col
//                 ed.active_window.cursor.preferred_col = entry.col
//                 break
//             }
//         }
//     }
// }

visual_mode_handle_key :: proc(ed: ^Editor, key: Key) {
    w := ed.active_window
    if w == nil { ed.mode = .Normal; return }

    buf := w.buffer

    switch {
    case key.special == .Escape:
        ed.mode = .Normal
        clear_visual(ed)

    case key.codepoint == 'v' && key.mods == nil:
        if ed.mode == .Visual_Char {
            ed.mode = .Normal
            clear_visual(ed)
        }

    case key.codepoint == 'V' && key.mods == nil:
        if ed.mode == .Visual_Line {
            ed.mode = .Normal
            clear_visual(ed)
        }

    case .Ctrl in key.mods && (key.codepoint == 'v' || key.codepoint == 22):
        if ed.mode == .Visual_Block {
            ed.mode = .Normal
            clear_visual(ed)
        }

    case key.codepoint == 'd' || key.codepoint == 'x' || key.special == .Delete:
        vs, has_vs := w.cursor.visual_start.?
        if has_vs {
            start := min(vs.x, w.cursor.row)
            end := max(vs.x, w.cursor.row) + 1
            abs_start := line_to_abs_pos(buf, start)
            abs_end := line_to_abs_pos(buf, end)
            if abs_end > buf.piece_table.char_count { abs_end = buf.piece_table.char_count }
            if abs_end > abs_start {
                text := pt_substring(&buf.piece_table, abs_start, abs_end - abs_start)
                ed.unnamed_register = text
                pt_delete(&buf.piece_table, abs_start, abs_end - abs_start)
                buf.modified = true
            }
        }
        clear_visual(ed)
        ed.mode = .Normal
        scroll_into_view(w)

    case key.codepoint == 'y' || key.codepoint == 'Y':
        vs, has_vs := w.cursor.visual_start.?
        if has_vs {
            start := min(vs.x, w.cursor.row)
            end := max(vs.x, w.cursor.row) + 1
            abs_start := line_to_abs_pos(buf, start)
            abs_end := line_to_abs_pos(buf, end)
            if abs_end > buf.piece_table.char_count { abs_end = buf.piece_table.char_count }
            if abs_end > abs_start {
                text := pt_substring(&buf.piece_table, abs_start, abs_end - abs_start)
                ed.unnamed_register = text
            }
        }
        clear_visual(ed)
        ed.mode = .Normal

    case key.codepoint == 'c':
        vs, has_vs := w.cursor.visual_start.?
        if has_vs {
            start := min(vs.x, w.cursor.row)
            end := max(vs.x, w.cursor.row) + 1
            abs_start := line_to_abs_pos(buf, start)
            abs_end := line_to_abs_pos(buf, end)
            if abs_end > buf.piece_table.char_count { abs_end = buf.piece_table.char_count }
            if abs_end > abs_start {
                text := pt_substring(&buf.piece_table, abs_start, abs_end - abs_start)
                ed.unnamed_register = text
                pt_delete(&buf.piece_table, abs_start, abs_end - abs_start)
                buf.modified = true
            }
        }
        clear_visual(ed)
        insert_mode_enter(ed)
        ed.mode = .Insert
        ed.prev_mode = .Normal
        w.cursor.col = 0
        w.cursor.preferred_col = 0
        scroll_into_view(w)

    case key.codepoint == '>' && key.mods == nil:
        vs, has_vs := w.cursor.visual_start.?
        if has_vs {
            start := min(vs.x, w.cursor.row)
            end := max(vs.x, w.cursor.row)
            for line := start; line <= end; line += 1 {
                pos := line_to_abs_pos(buf, line)
                pt_insert(&buf.piece_table, pos, "\t")
                buf.modified = true
            }
        }
        clear_visual(ed)
        ed.mode = .Normal
        scroll_into_view(w)

    case key.codepoint == '<' && key.mods == nil:
        vs, has_vs := w.cursor.visual_start.?
        if has_vs {
            start := min(vs.x, w.cursor.row)
            end := max(vs.x, w.cursor.row)
            for line := start; line <= end; line += 1 {
                pos := line_to_abs_pos(buf, line)
                if pos < buf.piece_table.char_count {
                    ch := pt_char_at(&buf.piece_table, pos)
                    if ch == '\t' || ch == ' ' {
                        pt_delete(&buf.piece_table, pos, 1)
                        buf.modified = true
                    }
                }
            }
        }
        clear_visual(ed)
        ed.mode = .Normal
        scroll_into_view(w)

    case:
        normal_mode_handle_key(ed, key)
        if ed.mode != .Visual_Char && ed.mode != .Visual_Line && ed.mode != .Visual_Block {
            ed.mode = .Visual_Char
        }
    }
}

handle_text_object :: proc(ed: ^Editor, key: Key) {
    _ = ed.active_window
    op, has_op := ed.pending_op.?
    if !has_op { ed.mode = .Normal; return }
    _ = op // Explicitly suppress unused compiler warning

    _ = key.codepoint // Suppress unused code assignment
    ed_pending_two_key(ed, "text_obj", proc(ed: ^Editor, second_key: Key) {
        w := ed.active_window
        buf := w.buffer
        op, _ := ed.pending_op.?

        // Retrieve op_type from the first key (stored in pending_two_key context)
        // For now, we'll determine inner/outer from the second key context
        // This is a simplified version - full implementation would need proper closure capture
        inner: bool = false
        kind := second_key.codepoint

        line := pt_get_line(&buf.piece_table, w.cursor.row)
        _ = line_cursor_to_abs(buf, w.cursor)
        line_start := line_to_abs_pos(buf, w.cursor.row)

        start, end: int = 0, 0

        switch kind {
        case 'w':
            if inner {
                s := w.cursor.col
                for s > 0 && is_word_char(line[s - 1]) { s -= 1 }
                e := w.cursor.col
                for e < len(line) && is_word_char(line[e]) { e += 1 }
                if e <= s { ed.mode = .Normal; return }
                start = line_start + s
                end = line_start + e
            } else {
                s := w.cursor.col
                for s > 0 && is_word_char(line[s - 1]) { s -= 1 }
                e := w.cursor.col
                for e < len(line) && is_word_char(line[e]) { e += 1 }
                for s > 0 && !is_word_char(line[s - 1]) { s -= 1 }
                for e < len(line) && !is_word_char(line[e]) { e += 1 }
                start = line_start + s
                end = line_start + e
            }

        case '(', ')', 'b':
            open := u8('('); close := u8(')')
            d := 0; found := false
            for i := w.cursor.col; i >= 0; i -= 1 {
                if line[i] == close { d += 1 }
                if line[i] == open { d -= 1; if d < 0 { start = line_start + i; found = true; break } }
            }
            if !found { ed.mode = .Normal; return }
            d = 0; found = false
            for i := w.cursor.col; i < len(line); i += 1 {
                if line[i] == open { d += 1 }
                if line[i] == close { d -= 1; if d < 0 { end = line_start + i + 1; found = true; break } }
            }
            if !found { ed.mode = .Normal; return }
            if !inner { start -= 1; end += 1 }

        case '[', ']':
            open := u8('['); close := u8(']')
            d := 0; found := false
            for i := w.cursor.col; i >= 0; i -= 1 {
                if line[i] == close { d += 1 }
                if line[i] == open { d -= 1; if d < 0 { start = line_start + i; found = true; break } }
            }
            if !found { ed.mode = .Normal; return }
            d = 0; found = false
            for i := w.cursor.col; i < len(line); i += 1 {
                if line[i] == open { d += 1 }
                if line[i] == close { d -= 1; if d < 0 { end = line_start + i + 1; found = true; break } }
            }
            if !found { ed.mode = .Normal; return }
            if !inner { start -= 1; end += 1 }

        case '{', '}', 'B':
            open := u8('{'); close := u8('}')
            d := 0; found := false
            for i := w.cursor.col; i >= 0; i -= 1 {
                if line[i] == close { d += 1 }
                if line[i] == open { d -= 1; if d < 0 { start = line_start + i; found = true; break } }
            }
            if !found { ed.mode = .Normal; return }
            d = 0; found = false
            for i := w.cursor.col; i < len(line); i += 1 {
                if line[i] == open { d += 1 }
                if line[i] == close { d -= 1; if d < 0 { end = line_start + i + 1; found = true; break } }
            }
            if !found { ed.mode = .Normal; return }
            if !inner { start -= 1; end += 1 }

        case '\'', '\"', '`':
            kind_u8 := u8(kind)
            for i := w.cursor.col - 1; i >= 0; i -= 1 {
                if line[i] == kind_u8 { start = line_start + i; break }
            }
            for i := w.cursor.col; i < len(line); i += 1 {
                if line[i] == kind_u8 { end = line_start + i + 1; break }
            }
            if !inner { start -= 1; end += 1 }

        case:
            ed.mode = .Normal
            ed.pending_op = nil
            return
        }

        if end > start {
            apply_operator(ed, op.kind, start, end)
        }
    })
}

add_jump :: proc(ed: ^Editor) {
    w := ed.active_window
    buf := w.buffer
    entry := Jump_Entry{buf_id = buf.id, row = w.cursor.row, col = w.cursor.col}
    if ed.jump_idx < len(ed.jumplist) - 1 {
        resize(&ed.jumplist, ed.jump_idx + 1)
    }
    append(&ed.jumplist, entry)
    if len(ed.jumplist) > 100 {
        ordered_remove(&ed.jumplist, 0)
    }
    ed.jump_idx = len(ed.jumplist) - 1
}

jump_back :: proc(ed: ^Editor) {
    if ed.jump_idx <= 0 { return }
    w := ed.active_window
    buf := w.buffer
    current := Jump_Entry{buf_id = buf.id, row = w.cursor.row, col = w.cursor.col}
    if ed.jump_idx >= len(ed.jumplist) {
        append(&ed.jumplist, current)
    } else {
        ed.jumplist[ed.jump_idx] = current
    }
    ed.jump_idx -= 1
    entry := ed.jumplist[ed.jump_idx]
    if entry.buf_id == buf.id {
        w.cursor.row = entry.row
        w.cursor.col = entry.col
        w.cursor.preferred_col = entry.col
        scroll_into_view(w)
    }
}

jump_forward :: proc(ed: ^Editor) {
    if ed.jump_idx >= len(ed.jumplist) - 1 { return }
    w := ed.active_window
    buf := w.buffer
    ed.jump_idx += 1
    entry := ed.jumplist[ed.jump_idx]
    if entry.buf_id == buf.id {
        w.cursor.row = entry.row
        w.cursor.col = entry.col
        w.cursor.preferred_col = entry.col
        scroll_into_view(w)
    }
}
