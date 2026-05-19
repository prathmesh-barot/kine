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

cursor_move_WORD_forward :: proc(c: ^Cursor, buf: ^Buffer) {
    line := pt_get_line(&buf.piece_table, c.row)
    pos := c.col
    for pos < len(line) && !is_non_whitespace(line[pos]) {
        pos += 1
    }
    if pos >= len(line) && c.row < buf.piece_table.line_count - 1 {
        c.row += 1
        pos = 0
        line = pt_get_line(&buf.piece_table, c.row)
    }
    for pos < len(line) && is_non_whitespace(line[pos]) {
        pos += 1
    }
    c.col = min(pos, len(line))
    c.preferred_col = c.col
}

cursor_move_WORD_backward :: proc(c: ^Cursor, buf: ^Buffer) {
    line := pt_get_line(&buf.piece_table, c.row)
    pos := c.col - 1
    for pos >= 0 && !is_non_whitespace(line[pos]) {
        pos -= 1
    }
    if pos < 0 && c.row > 0 {
        c.row -= 1
        line = pt_get_line(&buf.piece_table, c.row)
        pos = len(line) - 1
    }
    for pos >= 0 && is_non_whitespace(line[pos]) {
        pos -= 1
    }
    c.col = max(0, pos + 1)
    c.preferred_col = c.col
}

cursor_move_word_end_forward :: proc(c: ^Cursor, buf: ^Buffer) {
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
    c.col = max(0, pos)
    c.preferred_col = c.col
}

cursor_move_word_end_backward :: proc(c: ^Cursor, buf: ^Buffer) {
    line := pt_get_line(&buf.piece_table, c.row)
    pos := c.col - 1
    for pos >= 0 && is_word_char(line[pos]) {
        pos -= 1
    }
    for pos >= 0 && !is_word_char(line[pos]) {
        pos -= 1
    }
    if pos < 0 && c.row > 0 {
        c.row -= 1
        line = pt_get_line(&buf.piece_table, c.row)
        pos = len(line) - 1
        for pos >= 0 && is_word_char(line[pos]) {
            pos -= 1
        }
        pos = max(0, pos)
    }
    c.col = max(0, pos)
    c.preferred_col = c.col
}

cursor_move_WORD_end_forward :: proc(c: ^Cursor, buf: ^Buffer) {
    line := pt_get_line(&buf.piece_table, c.row)
    pos := c.col
    for pos < len(line) && !is_non_whitespace(line[pos]) {
        pos += 1
    }
    if pos >= len(line) && c.row < buf.piece_table.line_count - 1 {
        c.row += 1
        pos = 0
        line = pt_get_line(&buf.piece_table, c.row)
    }
    for pos < len(line) && is_non_whitespace(line[pos]) {
        pos += 1
    }
    c.col = max(0, pos)
    c.preferred_col = c.col
}

cursor_move_WORD_end_backward :: proc(c: ^Cursor, buf: ^Buffer) {
    line := pt_get_line(&buf.piece_table, c.row)
    pos := c.col - 1
    for pos >= 0 && is_non_whitespace(line[pos]) {
        pos -= 1
    }
    for pos >= 0 && !is_non_whitespace(line[pos]) {
        pos -= 1
    }
    if pos < 0 && c.row > 0 {
        c.row -= 1
        line = pt_get_line(&buf.piece_table, c.row)
        pos = len(line) - 1
        for pos >= 0 && is_non_whitespace(line[pos]) {
            pos -= 1
        }
        pos = max(0, pos)
    }
    c.col = max(0, pos)
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

cursor_move_to_line_end_insert :: proc(c: ^Cursor, buf: ^Buffer) {
    line := pt_get_line(&buf.piece_table, c.row)
    c.col = len(line)
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

cursor_move_to_next_line_first_nonblank :: proc(c: ^Cursor, buf: ^Buffer) {
    if c.row < buf.piece_table.line_count - 1 {
        c.row += 1
        cursor_move_to_first_nonblank(c, buf)
    }
}

cursor_move_to_prev_line_first_nonblank :: proc(c: ^Cursor, buf: ^Buffer) {
    if c.row > 0 {
        c.row -= 1
        cursor_move_to_first_nonblank(c, buf)
    }
}

cursor_move_to_percent :: proc(c: ^Cursor, buf: ^Buffer, percent: int) {
    target := (percent * buf.piece_table.line_count) / 100
    c.row = clamp(target, 0, buf.piece_table.line_count - 1)
    c.col = 0
    c.preferred_col = 0
}

cursor_move_to_window_top :: proc(c: ^Cursor, buf: ^Buffer, w: ^Window) {
    target := w.scroll_row
    c.row = clamp(target, 0, buf.piece_table.line_count - 1)
    cursor_move_to_first_nonblank(c, buf)
}

cursor_move_to_window_middle :: proc(c: ^Cursor, buf: ^Buffer, w: ^Window) {
    target := w.scroll_row + w.height / 2
    c.row = clamp(target, 0, buf.piece_table.line_count - 1)
    cursor_move_to_first_nonblank(c, buf)
}

cursor_move_to_window_bottom :: proc(c: ^Cursor, buf: ^Buffer, w: ^Window) {
    target := w.scroll_row + w.height - 1
    c.row = clamp(target, 0, buf.piece_table.line_count - 1)
    cursor_move_to_first_nonblank(c, buf)
}

cursor_move_find_char :: proc(c: ^Cursor, buf: ^Buffer, char: u8, direction: int) -> bool {
    line := pt_get_line(&buf.piece_table, c.row)
    pos := c.col
    if direction > 0 {
        for pos < len(line) - 1 {
            pos += 1
            if line[pos] == char {
                c.col = pos
                c.preferred_col = c.col
                return true
            }
        }
    } else {
        for pos > 0 {
            pos -= 1
            if line[pos] == char {
                c.col = pos
                c.preferred_col = c.col
                return true
            }
        }
    }
    return false
}

cursor_move_till_char :: proc(c: ^Cursor, buf: ^Buffer, char: u8, direction: int) -> bool {
    line := pt_get_line(&buf.piece_table, c.row)
    pos := c.col
    if direction > 0 {
        for pos < len(line) - 1 {
            pos += 1
            if line[pos] == char {
                c.col = pos - 1
                c.preferred_col = c.col
                return true
            }
        }
    } else {
        for pos > 0 {
            pos -= 1
            if line[pos] == char {
                c.col = pos + 1
                c.preferred_col = c.col
                return true
            }
        }
    }
    return false
}

cursor_move_to_matching_bracket :: proc(c: ^Cursor, buf: ^Buffer) -> bool {
    line := pt_get_line(&buf.piece_table, c.row)
    if c.col >= len(line) { return false }

    ch := line[c.col]
    match: u8
    dir: int
    switch ch {
    case '(': match = ')'; dir = 1
    case ')': match = '('; dir = -1
    case '[': match = ']'; dir = 1
    case ']': match = '['; dir = -1
    case '{': match = '}'; dir = 1
    case '}': match = '{'; dir = -1
    case: return false
    }

    depth := 0
    pos := c.col
    for pos >= 0 && pos < len(line) {
        if line[pos] == ch {
            depth += 1
        } else if line[pos] == match {
            depth -= 1
            if depth == 0 {
                c.col = pos
                c.preferred_col = c.col
                return true
            }
        }
        pos += dir
    }
    return false
}

cursor_move_paragraph_forward :: proc(c: ^Cursor, buf: ^Buffer) {
    for c.row < buf.piece_table.line_count - 1 {
        c.row += 1
        line := pt_get_line(&buf.piece_table, c.row)
        if len(line) == 0 {
            c.col = 0
            c.preferred_col = 0
            return
        }
    }
    c.col = 0
    c.preferred_col = 0
}

cursor_move_paragraph_backward :: proc(c: ^Cursor, buf: ^Buffer) {
    for c.row > 0 {
        c.row -= 1
        line := pt_get_line(&buf.piece_table, c.row)
        if len(line) == 0 {
            c.col = 0
            c.preferred_col = 0
            return
        }
    }
    c.col = 0
    c.preferred_col = 0
}

last_find_char: u8
last_find_dir: int
last_find_till: bool

cursor_find_char :: proc(c: ^Cursor, buf: ^Buffer, char: u8, direction: int, till: bool) -> bool {
    last_find_char = char
    last_find_dir = direction
    last_find_till = till
    if till {
        return cursor_move_till_char(c, buf, char, direction)
    }
    return cursor_move_find_char(c, buf, char, direction)
}

cursor_repeat_find :: proc(c: ^Cursor, buf: ^Buffer, direction: int) -> bool {
    if last_find_char == 0 { return false }
    dir := last_find_dir * direction
    if last_find_till {
        return cursor_move_till_char(c, buf, last_find_char, dir)
    }
    return cursor_move_find_char(c, buf, last_find_char, dir)
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

line_is_blank :: proc(buf: ^Buffer, line: int) -> bool {
    text := pt_get_line(&buf.piece_table, line)
    for c in text {
        if c != ' ' && c != '\t' { return false }
    }
    return true
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
