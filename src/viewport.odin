package main



Window :: struct {
    id:         int,
    buffer:     ^Buffer,
    cursor:     Cursor,
    scroll_row: int,
    scroll_col: int,
    top:        int,
    left:       int,
    width:      int,
    height:     int,
    is_active:  bool,
}

window_init :: proc(w: ^Window, buf: ^Buffer) {
    w.buffer = buf
    cursor_init(&w.cursor)
    w.scroll_row = 0
    w.scroll_col = 0
    w.top = 0
    w.left = 0
    w.width = 80
    w.height = 24
    w.is_active = false
}

scroll_into_view :: proc(w: ^Window) {
    if w.height <= 0 { return }

    scrolloff := SCROLLOFF
    sidescrolloff := SIDESCROLLOFF

    buf := w.buffer
    target_row := w.cursor.row

    if target_row < w.scroll_row + scrolloff {
        w.scroll_row = max(0, target_row - scrolloff)
    }

    if target_row >= w.scroll_row + w.height - scrolloff {
        w.scroll_row = min(max(0, target_row - w.height + scrolloff + 1), buf.piece_table.line_count - 1)
    }

    w.scroll_row = clamp(w.scroll_row, 0, max(0, buf.piece_table.line_count - w.height))

    disp_col := char_to_display_col(buf, w.cursor.row, w.cursor.col)

    if disp_col < w.scroll_col + sidescrolloff {
        w.scroll_col = max(0, disp_col - sidescrolloff)
    }

    if disp_col >= w.scroll_col + w.width - sidescrolloff {
        w.scroll_col = disp_col - w.width + sidescrolloff + 1
    }

    w.scroll_col = max(0, w.scroll_col)
}

scroll_lines :: proc(w: ^Window, lines: int) {
    w.scroll_row = clamp(w.scroll_row + lines, 0, max(0, w.buffer.piece_table.line_count - w.height))
}

scroll_half_screen :: proc(w: ^Window, dir: int) {
    half := max(1, w.height / 2)
    scroll_lines(w, half * dir)
}

scroll_full_screen :: proc(w: ^Window, dir: int) {
    scroll_lines(w, w.height * dir)
}

center_cursor :: proc(w: ^Window) {
    w.scroll_row = max(0, w.cursor.row - w.height / 2)
}

cursor_to_top :: proc(w: ^Window) {
    w.scroll_row = max(0, w.cursor.row)
}

cursor_to_bottom :: proc(w: ^Window) {
    w.scroll_row = max(0, w.cursor.row - w.height + 1)
}
