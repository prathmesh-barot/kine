package main



Line_Mode :: enum {
    Absolute,
    Relative,
}

Cursor :: struct {
    row:           int,
    col:           int,
    preferred_col: int,
    visual_start:  Maybe(Vec2),
    visual_active: bool,
}

cursor_init :: proc(c: ^Cursor) {
    c.row = 0
    c.col = 0
    c.preferred_col = 0
    c.visual_start = nil
    c.visual_active = false
}

cursor_move_up :: proc(c: ^Cursor, buf: ^Buffer, count: int) {
    new_row := max(0, c.row - count)
    c.row = new_row
    line_len := line_display_width(buf, new_row)
    if c.preferred_col > 0 {
        c.col = min(c.preferred_col, max(0, line_len - 1))
    } else {
        c.col = min(c.col, max(0, line_len - 1))
    }
}

cursor_move_down :: proc(c: ^Cursor, buf: ^Buffer, count: int) {
    new_row := min(buf.piece_table.line_count - 1, c.row + count)
    c.row = new_row
    line_len := line_display_width(buf, new_row)
    if c.preferred_col > 0 {
        c.col = min(c.preferred_col, max(0, line_len - 1))
    } else {
        c.col = min(c.col, max(0, line_len - 1))
    }
}

cursor_move_left :: proc(c: ^Cursor, buf: ^Buffer) {
    if c.col > 0 {
        c.col -= 1
    } else if c.row > 0 {
        c.row -= 1
        line := pt_get_line(&buf.piece_table, c.row)
        c.col = len(line)
    }
    c.preferred_col = c.col
}

cursor_move_right :: proc(c: ^Cursor, buf: ^Buffer) {
    line := pt_get_line(&buf.piece_table, c.row)
    if c.col < len(line) {
        c.col += 1
    } else if c.row < buf.piece_table.line_count - 1 {
        c.row += 1
        c.col = 0
    }
    c.preferred_col = c.col
}

cursor_move_word_forward :: proc(c: ^Cursor, buf: ^Buffer) {
    line := pt_get_line(&buf.piece_table, c.row)
    pos := c.col

    for pos < len(line) && !is_word_char(line[pos]) {
        pos += 1
    }
    if pos >= len(line) && c.row < buf.piece_table.line_count - 1 {
        c.row += 1
        pos = 0
        line = pt_get_line(&buf.piece_table, c.row)
    }
    for pos < len(line) && is_word_char(line[pos]) {
        pos += 1
    }
    c.col = min(pos, len(line))
    c.preferred_col = c.col
}

cursor_move_word_backward :: proc(c: ^Cursor, buf: ^Buffer) {
    line := pt_get_line(&buf.piece_table, c.row)
    pos := c.col - 1

    for pos >= 0 && !is_word_char(line[pos]) {
        pos -= 1
    }
    if pos < 0 && c.row > 0 {
        c.row -= 1
        line = pt_get_line(&buf.piece_table, c.row)
        pos = len(line) - 1
    }
    for pos >= 0 && is_word_char(line[pos]) {
        pos -= 1
    }
    c.col = max(0, pos + 1)
    c.preferred_col = c.col
}

cursor_move_to_line_start :: proc(c: ^Cursor, buf: ^Buffer) {
    c.col = 0
    c.preferred_col = 0
}

cursor_move_to_line_end :: proc(c: ^Cursor, buf: ^Buffer) {
    line := pt_get_line(&buf.piece_table, c.row)
    c.col = len(line)
    if c.col > 0 { c.col -= 1 }
    c.preferred_col = c.col
}

cursor_move_to_first_nonblank :: proc(c: ^Cursor, buf: ^Buffer) {
    line := pt_get_line(&buf.piece_table, c.row)
    c.col = 0
    for c.col < len(line) && (line[c.col] == ' ' || line[c.col] == '\t') {
        c.col += 1
    }
    c.preferred_col = c.col
}

cursor_move_to_line :: proc(c: ^Cursor, buf: ^Buffer, line: int) {
    c.row = clamp(line, 0, buf.piece_table.line_count - 1)
    line_len := line_display_width(buf, c.row)
    c.col = min(c.preferred_col, max(0, line_len - 1))
}

cursor_move_to_first_line :: proc(c: ^Cursor, buf: ^Buffer) {
    c.row = 0
    c.col = 0
    c.preferred_col = 0
}

cursor_move_to_last_line :: proc(c: ^Cursor, buf: ^Buffer) {
    c.row = buf.piece_table.line_count - 1
    c.col = 0
    c.preferred_col = 0
}

is_word_char :: proc(b: u8) -> bool {
    return (b >= 'a' && b <= 'z') ||
           (b >= 'A' && b <= 'Z') ||
           (b >= '0' && b <= '9') ||
           b == '_'
}

line_display_width :: proc(buf: ^Buffer, line: int) -> int {
    text := pt_get_line(&buf.piece_table, line)
    width := 0
    for c in text {
        if c == '\t' {
            width += buf.tab_width
        } else {
            width += 1
        }
    }
    return width
}

line_byte_length :: proc(buf: ^Buffer, line: int) -> int {
    text := pt_get_line(&buf.piece_table, line)
    return len(text)
}

char_to_display_col :: proc(buf: ^Buffer, line: int, char_col: int) -> int {
    text := pt_get_line(&buf.piece_table, line)
    display := 0
    for i := 0; i < min(char_col, len(text)); i += 1 {
        if text[i] == '\t' {
            display += buf.tab_width
        } else {
            display += 1
        }
    }
    return display
}

display_to_char_col :: proc(buf: ^Buffer, line: int, display_col: int) -> int {
    text := pt_get_line(&buf.piece_table, line)
    display := 0
    for i := 0; i < len(text); i += 1 {
        if text[i] == '\t' {
            next_display := display + buf.tab_width
            if next_display > display_col {
                return i
            }
            display = next_display
        } else {
            if display >= display_col {
                return i
            }
            display += 1
        }
    }
    return len(text)
}
