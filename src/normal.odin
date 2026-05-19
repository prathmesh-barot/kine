package main

import "core:fmt"

normal_mode_handle_key :: proc(ed: ^Editor, key: Key) {
    w := ed.active_window
    if w == nil { return }

    if key.mods == nil && key.special >= .F1 && key.special <= .F12 {
        return
    }

    if key.special == .Escape {
        if ed.count_buf_len > 0 {
            ed.count_buf_len = 0
        } else {
            clear_visual(ed)
            ed.pending_op = nil
        }
        return
    }

    count := ed_get_count(ed)

    switch {
    case key.special == .Arrow_Left || (key.codepoint == 'h' && key.mods == nil):
        cursor_move_left(&w.cursor, w.buffer)
        scroll_into_view(w)

    case key.special == .Arrow_Down || (key.codepoint == 'j' && key.mods == nil):
        cursor_move_down(&w.cursor, w.buffer, count)
        scroll_into_view(w)

    case key.special == .Arrow_Up || (key.codepoint == 'k' && key.mods == nil):
        cursor_move_up(&w.cursor, w.buffer, count)
        scroll_into_view(w)

    case key.special == .Arrow_Right || (key.codepoint == 'l' && key.mods == nil):
        cursor_move_right(&w.cursor, w.buffer)
        scroll_into_view(w)

    case key.codepoint == 'w':
        cursor_move_word_forward(&w.cursor, w.buffer)
        scroll_into_view(w)

    case key.codepoint == 'W':
        cursor_move_WORD_forward(&w.cursor, w.buffer)
        scroll_into_view(w)

    case key.codepoint == 'b':
        cursor_move_word_backward(&w.cursor, w.buffer)
        scroll_into_view(w)

    case key.codepoint == 'B':
        cursor_move_WORD_backward(&w.cursor, w.buffer)
        scroll_into_view(w)

    case key.codepoint == 'e':
        cursor_move_word_end_forward(&w.cursor, w.buffer)
        scroll_into_view(w)

    case key.codepoint == 'E':
        cursor_move_WORD_end_forward(&w.cursor, w.buffer)
        scroll_into_view(w)

    case key.codepoint == '0' && key.mods == nil:
        cursor_move_to_line_start(&w.cursor, w.buffer)

    case key.codepoint == '^' && key.mods == nil:
        cursor_move_to_first_nonblank(&w.cursor, w.buffer)

    case key.codepoint == '$' && key.mods == nil:
        cursor_move_to_line_end(&w.cursor, w.buffer)

    case key.codepoint == 'g':
        ed_pending_two_key(ed, "g", proc(ed: ^Editor, key: Key) {
            w := ed.active_window
            switch key.codepoint {
            case 'g':
                cursor_move_to_first_line(&w.cursor, w.buffer)
                scroll_into_view(w)
            case 'e':
                cursor_move_word_end_backward(&w.cursor, w.buffer)
                scroll_into_view(w)
            case 'E':
                cursor_move_WORD_end_backward(&w.cursor, w.buffer)
                scroll_into_view(w)
            }
        })

    case key.codepoint == 'G' && key.mods == nil:
        if ed.count_buf_len > 0 {
            cursor_move_to_line(&w.cursor, w.buffer, count - 1)
        } else {
            cursor_move_to_last_line(&w.cursor, w.buffer)
        }
        scroll_into_view(w)

    case key.special == .Page_Up || key.special == .Page_Down:
        dir := -1 if key.special == .Page_Up else 1
        scroll_full_screen(w, dir)
        w.cursor.row = clamp(w.cursor.row + dir * w.height, 0, w.buffer.piece_table.line_count - 1)
        scroll_into_view(w)

    case key.special == .Home:
        cursor_move_to_line_start(&w.cursor, w.buffer)

    case key.special == .End:
        cursor_move_to_line_end(&w.cursor, w.buffer)

    case key.codepoint == 'H' && key.mods == nil:
        cursor_move_to_window_top(&w.cursor, w.buffer, w)
        scroll_into_view(w)

    case key.codepoint == 'M' && key.mods == nil:
        cursor_move_to_window_middle(&w.cursor, w.buffer, w)
        scroll_into_view(w)

    case key.codepoint == 'L' && key.mods == nil:
        cursor_move_to_window_bottom(&w.cursor, w.buffer, w)
        scroll_into_view(w)

    case key.codepoint == '{':
        cursor_move_paragraph_backward(&w.cursor, w.buffer)
        scroll_into_view(w)

    case key.codepoint == '}':
        cursor_move_paragraph_forward(&w.cursor, w.buffer)
        scroll_into_view(w)

    case key.codepoint == '%' && key.mods == nil:
        cursor_move_to_matching_bracket(&w.cursor, w.buffer)
        scroll_into_view(w)

    case key.codepoint == '|' && key.mods == nil:
        c := count
        w.cursor.col = min(c - 1, max(0, line_byte_length(w.buffer, w.cursor.row) - 1))
        w.cursor.preferred_col = w.cursor.col
        scroll_into_view(w)

    case key.codepoint == '+' && key.mods == nil:
        for i := 0; i < count; i += 1 {
            cursor_move_to_next_line_first_nonblank(&w.cursor, w.buffer)
        }
        scroll_into_view(w)

    case key.codepoint == '-' && key.mods == nil:
        for i := 0; i < count; i += 1 {
            cursor_move_to_prev_line_first_nonblank(&w.cursor, w.buffer)
        }
        scroll_into_view(w)

    case key.codepoint == 'f' && key.mods == nil:
        ed_pending_two_key(ed, "f", proc(ed: ^Editor, key: Key) {
            if key.codepoint != 0 {
                cursor_find_char(&ed.active_window.cursor, ed.active_window.buffer, u8(key.codepoint), 1, false)
                scroll_into_view(ed.active_window)
            }
        })

    case key.codepoint == 'F' && key.mods == nil:
        ed_pending_two_key(ed, "F", proc(ed: ^Editor, key: Key) {
            if key.codepoint != 0 {
                cursor_find_char(&ed.active_window.cursor, ed.active_window.buffer, u8(key.codepoint), -1, false)
                scroll_into_view(ed.active_window)
            }
        })

    case key.codepoint == 't' && key.mods == nil:
        ed_pending_two_key(ed, "t", proc(ed: ^Editor, key: Key) {
            if key.codepoint != 0 {
                cursor_find_char(&ed.active_window.cursor, ed.active_window.buffer, u8(key.codepoint), 1, true)
                scroll_into_view(ed.active_window)
            }
        })

    case key.codepoint == 'T' && key.mods == nil:
        ed_pending_two_key(ed, "T", proc(ed: ^Editor, key: Key) {
            if key.codepoint != 0 {
                cursor_find_char(&ed.active_window.cursor, ed.active_window.buffer, u8(key.codepoint), -1, true)
                scroll_into_view(ed.active_window)
            }
        })

    case key.codepoint == ';' && key.mods == nil:
        cursor_repeat_find(&w.cursor, w.buffer, 1)
        scroll_into_view(w)

    case key.codepoint == ',' && key.mods == nil:
        cursor_repeat_find(&w.cursor, w.buffer, -1)
        scroll_into_view(w)

    case key.codepoint == 'n' && key.mods == nil:
        search_forward(ed, w.buffer, ed.search_direction)
        scroll_into_view(w)

    case key.codepoint == 'N' && key.mods == nil:
        search_forward(ed, w.buffer, -ed.search_direction)
        scroll_into_view(w)

    case key.codepoint == '*' && key.mods == nil:
        search_word_under_cursor(ed, 1)
        scroll_into_view(w)

    case key.codepoint == '#' && key.mods == nil:
        search_word_under_cursor(ed, -1)
        scroll_into_view(w)

    case .Ctrl in key.mods && key.codepoint == 'o':
        jump_back(ed)
        scroll_into_view(w)

    case .Ctrl in key.mods && (key.codepoint == 'i' || key.special == .Tab):
        jump_forward(ed)
        scroll_into_view(w)

    case key.codepoint == 'i':
        ed.mode = .Insert
        ed.prev_mode = .Normal

    case key.codepoint == 'a':
        cursor_move_right(&w.cursor, w.buffer)
        ed.mode = .Insert
        ed.prev_mode = .Normal

    case key.codepoint == 'I':
        cursor_move_to_first_nonblank(&w.cursor, w.buffer)
        ed.mode = .Insert
        ed.prev_mode = .Normal

    case key.codepoint == 'A':
        cursor_move_to_line_end(&w.cursor, w.buffer)
        if w.cursor.col < line_byte_length(w.buffer, w.cursor.row) {
            w.cursor.col += 1
        }
        ed.mode = .Insert
        ed.prev_mode = .Normal

    case key.codepoint == 'o' && key.mods == nil:
        buf := w.buffer
        pos := line_to_abs_pos(buf, w.cursor.row) + line_byte_length(buf, w.cursor.row)
        if pos > 0 && pt_char_at(&buf.piece_table, pos - 1) != '\n' {
            pt_insert(&buf.piece_table, pos, "\n")
            pos += 1
        } else if pos < buf.piece_table.char_count && pt_char_at(&buf.piece_table, pos) != '\n' {
            pt_insert(&buf.piece_table, pos, "\n")
        } else {
            pt_insert(&buf.piece_table, pos, "\n")
        }
        pos += 1
        buf.modified = true
        w.cursor.row += 1
        w.cursor.col = 0
        w.cursor.preferred_col = 0
        scroll_into_view(w)
        ed.mode = .Insert
        ed.prev_mode = .Normal

    case key.codepoint == 'O':
        buf := w.buffer
        pos := line_to_abs_pos(buf, w.cursor.row)
        pt_insert(&buf.piece_table, pos, "\n")
        buf.modified = true
        w.cursor.col = 0
        w.cursor.preferred_col = 0
        scroll_into_view(w)
        ed.mode = .Insert
        ed.prev_mode = .Normal

    case key.codepoint == 's' && key.mods == nil:
        buf := w.buffer
        pos := line_cursor_to_abs(buf, w.cursor)
        if pos < buf.piece_table.char_count {
            pt_delete(&buf.piece_table, pos, 1)
            buf.modified = true
        }
        insert_mode_enter(ed)
        ed.mode = .Insert
        ed.prev_mode = .Normal

    case key.codepoint == 'S' && key.mods == nil:
        buf := w.buffer
        pos := line_to_abs_pos(buf, w.cursor.row)
        line_len := line_byte_length(buf, w.cursor.row)
        end_pos := pos + line_len + 1
        if end_pos > buf.piece_table.char_count {
            end_pos = buf.piece_table.char_count
        }
        if end_pos > pos {
            pt_delete(&buf.piece_table, pos, end_pos - pos)
            buf.modified = true
        }
        insert_mode_enter(ed)
        ed.mode = .Insert
        ed.prev_mode = .Normal

    case key.codepoint == 'x' && key.mods == nil:
        buf := w.buffer
        if w.cursor.row < buf.piece_table.line_count {
            pos := line_cursor_to_abs(buf, w.cursor)
            if pos < buf.piece_table.char_count {
                ch := pt_char_at(&buf.piece_table, pos)
                if ch == '\n' {
                    if w.cursor.row < buf.piece_table.line_count - 1 {
                        pt_delete(&buf.piece_table, pos, 1)
                        buf.modified = true
                    }
                } else {
                    pt_delete(&buf.piece_table, pos, 1)
                    buf.modified = true
                }
            }
        }
        scroll_into_view(w)

    case key.codepoint == 'X' && key.mods == nil:
        buf := w.buffer
        pos := line_cursor_to_abs(buf, w.cursor)
        if pos > 0 {
            pt_delete(&buf.piece_table, pos - 1, 1)
            buf.modified = true
            if w.cursor.col > 0 {
                w.cursor.col -= 1
            }
        }
        scroll_into_view(w)

    case (key.codepoint == 'd' && key.mods == nil):
        if ed.count_buf_len > 0 && count > 0 {
            buf := w.buffer
            pos := line_to_abs_pos(buf, w.cursor.row)
            end_line := min(w.cursor.row + count - 1, buf.piece_table.line_count - 1)
            end_pos := line_to_abs_pos(buf, end_line) + line_byte_length(buf, end_line) + 1
            if end_pos > buf.piece_table.char_count { end_pos = buf.piece_table.char_count }
            if end_pos > pos {
                text := pt_substring(&buf.piece_table, pos, end_pos - pos)
                ed.unnamed_register = text
                pt_delete(&buf.piece_table, pos, end_pos - pos)
                buf.modified = true
            }
            if w.cursor.row >= buf.piece_table.line_count {
                w.cursor.row = buf.piece_table.line_count - 1
            }
            w.cursor.col = 0
            w.cursor.preferred_col = 0
        } else {
            ed.mode = .Operator_Pending
            ed.pending_op = Pending_Op{kind = .Delete, count = count}
        }
        scroll_into_view(w)

    case key.codepoint == 'D' && key.mods == nil:
        buf := w.buffer
        pos := line_cursor_to_abs(buf, w.cursor)
        line_len := line_byte_length(buf, w.cursor.row)
        from_col := pos + w.cursor.col
        to_col := pos + line_len
        if to_col > from_col {
            text := pt_substring(&buf.piece_table, from_col, to_col - from_col)
            ed.unnamed_register = text
            pt_delete(&buf.piece_table, from_col, to_col - from_col)
            buf.modified = true
        }
        scroll_into_view(w)

    case (key.codepoint == 'c' && key.mods == nil):
        ed.mode = .Operator_Pending
        ed.pending_op = Pending_Op{kind = .Change, count = count}

    case key.codepoint == 'C' && key.mods == nil:
        buf := w.buffer
        pos := line_cursor_to_abs(buf, w.cursor)
        line_len := line_byte_length(buf, w.cursor.row)
        from_col := pos + w.cursor.col
        to_col := pos + line_len
        if to_col > from_col {
            text := pt_substring(&buf.piece_table, from_col, to_col - from_col)
            ed.unnamed_register = text
            pt_delete(&buf.piece_table, from_col, to_col - from_col)
            buf.modified = true
        }
        insert_mode_enter(ed)
        ed.mode = .Insert
        ed.prev_mode = .Normal
        scroll_into_view(w)

    case (key.codepoint == 'y' && key.mods == nil):
        ed.mode = .Operator_Pending
        ed.pending_op = Pending_Op{kind = .Yank, count = count}

    case key.codepoint == 'Y' && key.mods == nil:
        buf := w.buffer
        pos := line_to_abs_pos(buf, w.cursor.row)
        line_len := line_byte_length(buf, w.cursor.row)
        end_pos := pos + line_len + 1
        if end_pos > buf.piece_table.char_count {
            end_pos = buf.piece_table.char_count
        }
        yanked_text := pt_substring(&buf.piece_table, pos, end_pos - pos)
        ed.unnamed_register = yanked_text

    case key.codepoint == 'p':
        if ed.unnamed_register != "" {
            buf := w.buffer
            pos := line_cursor_to_abs(buf, w.cursor) + 1
            if pos > buf.piece_table.char_count {
                pos = buf.piece_table.char_count
            }
            pt_insert(&buf.piece_table, pos, ed.unnamed_register)
            buf.modified = true
            scroll_into_view(w)
        }

    case key.codepoint == 'P':
        if ed.unnamed_register != "" {
            buf := w.buffer
            pos := line_cursor_to_abs(buf, w.cursor)
            pt_insert(&buf.piece_table, pos, ed.unnamed_register)
            buf.modified = true
            scroll_into_view(w)
        }

    case key.codepoint == '>' && key.mods == nil:
        buf := w.buffer
        pos := line_to_abs_pos(buf, w.cursor.row)
        pt_insert(&buf.piece_table, pos, "\t")
        buf.modified = true
        w.cursor.col += 1
        w.cursor.preferred_col = w.cursor.col
        scroll_into_view(w)

    case key.codepoint == '<' && key.mods == nil:
        buf := w.buffer
        pos := line_to_abs_pos(buf, w.cursor.row)
        if pos < buf.piece_table.char_count {
            ch := pt_char_at(&buf.piece_table, pos)
            if ch == '\t' || ch == ' ' {
                pt_delete(&buf.piece_table, pos, 1)
                buf.modified = true
                if w.cursor.col > 0 {
                    w.cursor.col -= 1
                    w.cursor.preferred_col = w.cursor.col
                }
            }
        }
        scroll_into_view(w)

    case key.codepoint == '=' && key.mods == nil:
        ed.mode = .Operator_Pending
        ed.pending_op = Pending_Op{kind = .AutoIndent, count = count}

    case key.codepoint == 'u' && key.mods == nil:
        undo_handler(ed)

    case key.special == .Delete:
        buf := w.buffer
        pos := line_cursor_to_abs(buf, w.cursor)
        if pos < buf.piece_table.char_count {
            pt_delete(&buf.piece_table, pos, 1)
            buf.modified = true
        }
        scroll_into_view(w)

    case key.special == .Backspace:
        buf := w.buffer
        pos := line_cursor_to_abs(buf, w.cursor)
        if pos > 0 {
            pt_delete(&buf.piece_table, pos - 1, 1)
            buf.modified = true
            if w.cursor.col > 0 {
                w.cursor.col -= 1
            }
        }
        scroll_into_view(w)

    case key.codepoint == ':' && key.mods == nil:
        ed.mode = .Command
        ed.prev_mode = .Normal
        ed.command_buf_len = 0
        ed.command_buf = {}

    case key.codepoint == '/' && key.mods == nil:
        ed.mode = .Search_Forward
        ed.search_direction = 1
        ed.command_buf_len = 0
        ed.command_buf = {}

    case key.codepoint == '?' && key.mods == nil:
        ed.mode = .Search_Backward
        ed.search_direction = -1
        ed.command_buf_len = 0
        ed.command_buf = {}

    case key.codepoint == 'v' && key.mods == nil:
        if ed.mode == .Visual_Char {
            ed.mode = .Normal
        } else {
            ed.mode = .Visual_Char
            w.cursor.visual_start = Vec2{w.cursor.row, w.cursor.col}
            w.cursor.visual_active = true
        }

    case key.codepoint == 'V' && key.mods == nil:
        if ed.mode == .Visual_Line {
            ed.mode = .Normal
        } else {
            ed.mode = .Visual_Line
            w.cursor.visual_start = Vec2{w.cursor.row, w.cursor.col}
            w.cursor.visual_active = true
        }

    case .Ctrl in key.mods && (key.codepoint == 'v' || key.codepoint == 22):
        if ed.mode == .Visual_Block {
            ed.mode = .Normal
        } else {
            ed.mode = .Visual_Block
            w.cursor.visual_start = Vec2{w.cursor.row, w.cursor.col}
            w.cursor.visual_active = true
        }

    case .Ctrl in key.mods && key.codepoint == 'd':
        scroll_half_screen(w, 1)

    case .Ctrl in key.mods && key.codepoint == 'u':
        scroll_half_screen(w, -1)

    case .Ctrl in key.mods && key.codepoint == 'f':
        scroll_full_screen(w, 1)

    case .Ctrl in key.mods && key.codepoint == 'b':
        scroll_full_screen(w, -1)

    case .Ctrl in key.mods && key.codepoint == 'r':
        redo_handler(ed)

    case key.codepoint == 'J':
        join_lines(ed)

    case key.codepoint == 'r':
        ed_pending_two_key(ed, "r", proc(ed: ^Editor, key: Key) {
            w := ed.active_window
            buf := w.buffer
            pos := line_cursor_to_abs(buf, w.cursor)
            if pos < buf.piece_table.char_count {
                pt_delete(&buf.piece_table, pos, 1)
                if key.codepoint != 0 {
                    r := key.codepoint
                    if r < 256 {
                        ch := u8(r)
                        pt_insert(&buf.piece_table, pos, string([]u8{ch}))
                    }
                }
                buf.modified = true
            }
        })

    case key.codepoint == '.':
        repeat_last_change(ed)

    case key.codepoint == 'z':
        ed_pending_two_key(ed, "z", proc(ed: ^Editor, key: Key) {
            w := ed.active_window
            switch {
            case key.codepoint == 'z':
                center_cursor(w)
            case key.codepoint == 't':
                cursor_to_top(w)
            case key.codepoint == 'b':
                cursor_to_bottom(w)
            }
        })

    case .Ctrl in key.mods && key.codepoint == 'e':
        scroll_lines(ed.active_window, 1)

    case .Ctrl in key.mods && key.codepoint == 'y':
        scroll_lines(ed.active_window, -1)

    case .Ctrl in key.mods && key.codepoint == 'g':
        buf := w.buffer
        ed.message = fmt.tprintf("%s  %dL  %dC  (%d%%)", buf.name, buf.piece_table.line_count, buf.piece_table.char_count,
            (w.cursor.row * 100) / max(1, buf.piece_table.line_count))

    case key.codepoint >= '1' && key.codepoint <= '9':
        ed_add_count_digit(ed, int(key.codepoint - '0'))

    case key.codepoint == '0' && ed.count_buf_len > 0:
        ed_add_count_digit(ed, 0)

    case:
        if key.codepoint != 0 {
            log_debug(fmt.tprintf("unhandled normal key: codepoint=%d char='%c' special=%v mods=%v",
                key.codepoint, key.codepoint, key.special, key.mods))
        } else {
            log_debug(fmt.tprintf("unhandled normal key: special=%v mods=%v", key.special, key.mods))
        }
    }
}

clear_visual :: proc(ed: ^Editor) {
    if ed.active_window != nil {
        ed.active_window.cursor.visual_active = false
        ed.active_window.cursor.visual_start = nil
    }
}

line_to_abs_pos :: proc(buf: ^Buffer, line: int) -> int {
    if line < 0 || line >= buf.piece_table.line_count { return 0 }
    return buf.piece_table.line_starts[line]
}

line_cursor_to_abs :: proc(buf: ^Buffer, c: Cursor) -> int {
    line_start := line_to_abs_pos(buf, c.row)
    return line_start + c.col
}

join_lines :: proc(ed: ^Editor) {
    w := ed.active_window
    buf := w.buffer
    if w.cursor.row >= buf.piece_table.line_count - 1 { return }

    line_end := line_to_abs_pos(buf, w.cursor.row) + line_byte_length(buf, w.cursor.row)

    if pt_char_at(&buf.piece_table, line_end) == '\n' {
        pt_delete(&buf.piece_table, line_end, 1)
        buf.modified = true
    }
    if w.cursor.col > line_byte_length(buf, w.cursor.row) {
        w.cursor.col = line_byte_length(buf, w.cursor.row)
    }
}

undo_handler :: proc(ed: ^Editor) {
    maybe_rec := undo_stack_undo(&ed.undo_stack)
    rec, ok := maybe_rec.?
    if !ok { return }
    w := ed.active_window
    buf := w.buffer
    if rec.kind == .Insert {
        pt_delete(&buf.piece_table, rec.pos, len(rec.text))
    } else {
        pt_insert(&buf.piece_table, rec.pos, rec.text)
    }
    buf.modified = true
    w.cursor.row = rec.cursor_before.x
    w.cursor.col = rec.cursor_before.y
    w.cursor.preferred_col = w.cursor.col
    scroll_into_view(w)
}

redo_handler :: proc(ed: ^Editor) {
    maybe_rec := undo_stack_redo(&ed.undo_stack)
    rec, ok := maybe_rec.?
    if !ok { return }
    w := ed.active_window
    buf := w.buffer
    if rec.kind == .Insert {
        pt_insert(&buf.piece_table, rec.pos, rec.text)
    } else {
        pt_delete(&buf.piece_table, rec.pos, len(rec.text))
    }
    buf.modified = true
    w.cursor.row = rec.cursor_after.x
    w.cursor.col = rec.cursor_after.y
    w.cursor.preferred_col = w.cursor.col
    scroll_into_view(w)
}

repeat_last_change :: proc(ed: ^Editor) {
    if ed.last_change.text == "" { return }
    w := ed.active_window
    buf := w.buffer
    pos := line_cursor_to_abs(buf, w.cursor)

    if ed.last_change.kind == .Insert {
        pt_insert(&buf.piece_table, pos, ed.last_change.text)
        buf.modified = true
        w.cursor.row = ed.last_change.cursor_after.x
        w.cursor.col = ed.last_change.cursor_after.y
    } else {
        pt_delete(&buf.piece_table, pos, len(ed.last_change.text))
        buf.modified = true
    }
    scroll_into_view(w)
}
