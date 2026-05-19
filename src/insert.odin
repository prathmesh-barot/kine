package main

import "core:fmt"

insert_start_text: [dynamic]u8

insert_mode_enter :: proc(ed: ^Editor) {
    clear(&insert_start_text)
}

insert_mode_handle_key :: proc(ed: ^Editor, key: Key) {
    w := ed.active_window
    buf := w.buffer
    pos := line_cursor_to_abs(buf, w.cursor)

    switch {
    case key.special == .Escape || (key.codepoint == 0x1b && key.mods == nil):
        if len(insert_start_text) > 0 {
            change := string(insert_start_text[:])
            undo_stack_push(&ed.undo_stack, .Insert, pos - len(change), change,
                Vec2{w.cursor.row, w.cursor.col - 1},
                Vec2{w.cursor.row, w.cursor.col})
            ed.last_change = Last_Change{kind = .Insert, text = change,
                cursor_after = Vec2{w.cursor.row, w.cursor.col}}
        }
        ed.mode = .Normal
        ansi_cursor_shape_block(&ed.output_buf)

    case key.codepoint == 0x1b && key.mods == {.Alt}:
        return

    case key.special == .Enter || key.codepoint == '\n' || key.codepoint == '\r':
        pt_insert(&buf.piece_table, pos, "\n")
        append(&insert_start_text, '\n')
        buf.modified = true
        w.cursor.row += 1
        w.cursor.col = 0
        w.cursor.preferred_col = 0
        scroll_into_view(w)

    case key.special == .Backspace || key.codepoint == 0x7f:
        if pos > 0 {
            if w.cursor.col > 0 {
                pt_delete(&buf.piece_table, pos - 1, 1)
                buf.modified = true
                w.cursor.col -= 1
                w.cursor.preferred_col = w.cursor.col
                if len(insert_start_text) > 0 {
                    resize(&insert_start_text, len(insert_start_text) - 1)
                }
            } else if w.cursor.row > 0 {
                line_end := line_byte_length(buf, w.cursor.row - 1)
                from_pos := line_to_abs_pos(buf, w.cursor.row - 1) + line_end
                pt_delete(&buf.piece_table, from_pos, 1)
                buf.modified = true
                w.cursor.row -= 1
                w.cursor.col = line_end
                w.cursor.preferred_col = w.cursor.col
                if len(insert_start_text) > 0 {
                    resize(&insert_start_text, len(insert_start_text) - 1)
                }
            }
        }

    case key.special == .Tab || key.codepoint == '\t' || (key.special == .Tab && key.mods == nil):
        insert_text := "\t"
        pt_insert(&buf.piece_table, pos, insert_text)
        append(&insert_start_text, ..transmute([]u8)insert_text)
        buf.modified = true
        w.cursor.col += 1
        w.cursor.preferred_col = w.cursor.col
        scroll_into_view(w)

    case key.codepoint != 0:
        ch := u8(key.codepoint)
        if key.codepoint > 0x7F {
            r := key.codepoint
            utf8_buf: [4]u8
            n := utf8_encode_rune(r, utf8_buf[:])
            text := string(utf8_buf[:n])
            pt_insert(&buf.piece_table, pos, text)
            append(&insert_start_text, ..utf8_buf[:n])
            w.cursor.col += 1
            w.cursor.preferred_col = w.cursor.col
            scroll_into_view(w)
        } else if ch >= 32 {
            text := string([]u8{ch})
            pt_insert(&buf.piece_table, pos, text)
            append(&insert_start_text, ch)
            buf.modified = true
            w.cursor.col += 1
            w.cursor.preferred_col = w.cursor.col
            scroll_into_view(w)
        }

    case:
        if key.codepoint != 0 {
            log_debug(fmt.tprintf("unhandled insert key: codepoint=%d special=%v mods=%v",
                key.codepoint, key.special, key.mods))
        }
    }
}
