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
    unnamed_register: string,
    undo_stack:       Undo_Stack,
    last_change:      Last_Change,
    message:          string,
    term_cols:        int,
    term_rows:        int,
    term_state:       Terminal_State,
    output_buf:       Output_Buffer,
    current_screen:   Screen,
    desired_screen:   Screen,
    running:          bool,
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
    case .Insert, .Replace:
        insert_mode_handle_key(ed, key)
    case .Command, .Search_Forward, .Search_Backward:
        command_mode_handle_key(ed, key)
    case .Visual_Char, .Visual_Line, .Visual_Block:
        if key.special == .Escape {
            ed.mode = .Normal
            clear_visual(ed)
        } else {
            normal_mode_handle_key(ed, key)
        }
    case .Operator_Pending:
        ed.mode = .Normal
        normal_mode_handle_key(ed, key)
    }
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
        execute_command(ed, cmd)
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

    case key.codepoint != 0:
        if ed.command_buf_len < cap(ed.command_buf) {
            ch := u8(key.codepoint)
            append(&ed.command_buf, ch)
            ed.command_buf_len += 1
        }
    }
}

execute_command :: proc(ed: ^Editor, cmd: string) {
    if cmd == "" { return }

    switch {
    case cmd == "q" || strings.has_prefix(cmd, "q"):
        if strings.contains(cmd, "!") {
            ed.running = false
        } else {
            modified := false
            for buf in ed.buffers {
                if buf.modified { modified = true; break }
            }
            if modified {
                ed.message = "No write since last change (add ! to force)"
                return
            }
            ed.running = false
        }

    case strings.has_prefix(cmd, "w") || cmd == "x":
        save_cmd := cmd
        space_idx := strings.index(save_cmd, " ")
        save_path := ""
        if space_idx != -1 {
            save_path = save_cmd[space_idx + 1:]
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

    case cmd == "wq":
        if ed.active_window != nil && ed.active_window.buffer != nil {
            buf := ed.active_window.buffer
            err := buffer_save(buf, buf.filepath)
            if err != nil {
                ed.message = fmt.tprintf("Error saving: %v", err)
                return
            }
        }
        modified := false
        for b in ed.buffers { if b.modified { modified = true; break } }
        if !modified { ed.running = false }

    case strings.has_prefix(cmd, "e ") || strings.has_prefix(cmd, "edit "):
        space_idx := strings.index(cmd, " ")
        if space_idx != -1 {
            path := strings.trim_space(cmd[space_idx + 1:])
            buf, err := buffer_open(path)
            if err != nil {
                ed.message = fmt.tprintf("Cannot open '%s': %v", path, err)
            } else {
                append(&ed.buffers, buf)
                ed.active_window.buffer = buf
                cursor_init(&ed.active_window.cursor)
                ed.active_window.scroll_row = 0
                ed.active_window.scroll_col = 0
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

    case strings.has_prefix(cmd, "noh") || cmd == "nohlsearch":
        ed.message = ""

    case strings.has_prefix(cmd, "h") || strings.has_prefix(cmd, "help"):
        ed.message = "kine - Odin Modal Text Editor (Phase 1)"

    case strings.has_prefix(cmd, "version"):
        ed.message = "kine v0.1.0 - Odin dev-2026-05"

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
    ed.last_change = Last_Change{}

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
