package main

import "core:fmt"

Cell :: struct {
    char:    rune,
    fg:      Color,
    bg:      Color,
    bold:    bool,
    reverse: bool,
}

Screen :: struct {
    cells: []Cell,
    rows:  int,
    cols:  int,
}

FG_DEFAULT       :: Color(255)
BG_DEFAULT       :: Color(0)
FG_NORMAL        :: Color(7)
FG_STATUS        :: Color(15)
BG_STATUS        :: Color(236)
BG_ACTIVE_STATUS :: Color(238)
FG_COMMAND       :: Color(15)
BG_COMMAND       :: Color(236)
FG_LINE_NUM      :: Color(242)
BG_LINE_NUM      :: Color(235)
FG_TILDE         :: Color(239)
FG_CURSOR_LINE   :: Color(240)
FG_TAB_ACTIVE    :: Color(15)
BG_TAB_ACTIVE    :: Color(238)
FG_TAB_INACTIVE  :: Color(242)
BG_TAB_INACTIVE  :: Color(235)

screen_init :: proc(s: ^Screen, rows, cols: int) {
    s.rows = rows
    s.cols = cols
    s.cells = make([]Cell, rows * cols)
    screen_clear(s)
}

screen_destroy :: proc(s: ^Screen) {
    delete(s.cells)
}

screen_clear :: proc(s: ^Screen) {
    for i in 0 ..< len(s.cells) {
        s.cells[i] = Cell{char = ' ', fg = FG_DEFAULT, bg = BG_DEFAULT}
    }
}

screen_get :: proc(s: ^Screen, row, col: int) -> ^Cell {
    return &s.cells[row * s.cols + col]
}

screen_diff_and_flush :: proc(current, desired: ^Screen, ob: ^Output_Buffer) {
    if current.rows != desired.rows || current.cols != desired.cols {
        ansi_cursor_hide(ob)
        ansi_cursor_home(ob)
        for row in 0 ..< desired.rows {
            ansi_cursor_goto(ob, row, 0)
            for col in 0 ..< desired.cols {
                cell := screen_get(desired, row, col)
                ansi_reset(ob)
                if cell.bg != BG_DEFAULT { ansi_set_bg(ob, cell.bg) }
                if cell.fg != FG_DEFAULT { ansi_set_fg(ob, cell.fg) }
                if cell.bold { ansi_bold(ob) }
                if cell.reverse { ansi_reverse(ob) }
                if cell.char == 0 {
                    ob_write_byte(ob, ' ')
                } else {
                    buf: [4]u8
                    n := utf8_encode_rune(cell.char, buf[:])
                    ob_write(ob, string(buf[:n]))
                }
            }
        }
        screen_clear(current)
        for i in 0 ..< len(current.cells) {
            current.cells[i] = desired.cells[i]
        }
        return
    }

    for row in 0 ..< desired.rows {
        dcol := 0
        for dcol < desired.cols {
            idx := row * desired.cols + dcol
            c := current.cells[idx]
            d := desired.cells[idx]

            if c != d {
                ansi_cursor_goto(ob, row, dcol)
                ansi_reset(ob)
                if d.bg != BG_DEFAULT { ansi_set_bg(ob, d.bg) }
                if d.fg != FG_DEFAULT { ansi_set_fg(ob, d.fg) }
                if d.bold { ansi_bold(ob) }
                if d.reverse { ansi_reverse(ob) }

                if d.char == 0 {
                    ob_write_byte(ob, ' ')
                } else {
                    buf: [4]u8
                    n := utf8_encode_rune(d.char, buf[:])
                    ob_write(ob, string(buf[:n]))
                }
                current.cells[idx] = d
            }
            dcol += 1
        }
    }
}

render_frame :: proc(w: ^Window, current: ^Screen, desired: ^Screen, ob: ^Output_Buffer, ed: ^Editor) {
    screen_clear(desired)
    render_buffer(w, desired)
    render_status_line(w, desired, ed)
    render_command_bar(desired, ed)
    screen_diff_and_flush(current, desired, ob)
    render_cursor(w, ob, ed)
}

render_buffer :: proc(w: ^Window, desired: ^Screen) {
    buf := w.buffer

    ln_width := 1
    if buf.piece_table.line_count > 9 { ln_width = 2 }
    if buf.piece_table.line_count > 99 { ln_width = 3 }
    if buf.piece_table.line_count > 999 { ln_width = 4 }

    for row in 0 ..< w.height {
        buf_row := w.scroll_row + row
        desired_row := w.top + row
        if desired_row >= desired.rows { break }

        if buf_row >= buf.piece_table.line_count {
            cell := screen_get(desired, desired_row, 0)
            cell.char = '~'
            cell.fg = FG_TILDE
            continue
        }

        for col in 0 ..< ln_width + 1 {
            cell := screen_get(desired, desired_row, col)
            cell.bg = BG_LINE_NUM
            cell.fg = FG_LINE_NUM
            if col < ln_width {
                line_num := buf_row + 1
                if w.cursor.row == buf_row && w.is_active {
                    cell.fg = FG_STATUS
                }
                num_str := fmt.tprintf("%*d", ln_width, line_num)
                if col < len(num_str) {
                    cell.char = rune(num_str[col])
                }
            } else {
                cell.char = ' '
            }
        }

        line_text := pt_get_line(&buf.piece_table, buf_row)
        start_col := ln_width + 1

        for col := 0; col < w.width - start_col; col += 1 {
            buf_col := w.scroll_col + col
            screen_col := start_col + col
            cell := screen_get(desired, desired_row, screen_col)

            if buf_row == w.cursor.row && w.is_active {
                cell.bg = FG_CURSOR_LINE
            }

            if buf_col < len(line_text) {
                ch := line_text[buf_col]
                if ch >= 32 && ch <= 126 {
                    cell.char = rune(ch)
                } else if ch == '\t' {
                    cell.char = ' '
                } else {
                    cell.char = '.'
                }
            }
        }
    }
}

render_status_line :: proc(w: ^Window, desired: ^Screen, ed: ^Editor) {
    buf := w.buffer
    status_row := w.top + w.height
    if status_row >= desired.rows { return }

    bg := BG_STATUS
    if w.is_active {
        bg = BG_ACTIVE_STATUS
    }

    mode_str := mode_to_string(ed.mode)
    percent := 0
    if buf.piece_table.line_count > 0 {
        percent = (w.cursor.row * 100) / buf.piece_table.line_count
    }

    modified_flag := " "
    if buf.modified { modified_flag = " +" }

    left := fmt.tprintf(" %s %s%s  %s  %s",
        mode_str, buf.name, modified_flag, buf.filetype, buf.encoding)
    right := fmt.tprintf(" %d%%  %d:%d  %s ",
        percent, w.cursor.row + 1, w.cursor.col + 1, line_ending_string(buf.line_ending))

    for col in 0 ..< desired.cols {
        cell := screen_get(desired, status_row, col)
        cell.bg = bg
        cell.fg = FG_STATUS
        if col < len(left) {
            cell.char = rune(left[col])
        } else if col >= desired.cols - len(right) {
            rcol := col - (desired.cols - len(right))
            if rcol < len(right) {
                cell.char = rune(right[rcol])
            }
        } else {
            cell.char = ' '
        }
    }
}

render_command_bar :: proc(desired: ^Screen, ed: ^Editor) {
    cmd_row := desired.rows - 1
    if cmd_row < 0 { return }

    prompt := ""
    display_text := ""
    if ed.mode == .Command {
        prompt = ":"
        display_text = string(ed.command_buf[:ed.command_buf_len])
    } else if ed.mode == .Search_Forward {
        prompt = "/"
        display_text = string(ed.command_buf[:ed.command_buf_len])
    } else if ed.mode == .Search_Backward {
        prompt = "?"
        display_text = string(ed.command_buf[:ed.command_buf_len])
    } else if ed.message != "" {
        display_text = ed.message
    }

    full := fmt.tprintf("%s%s", prompt, display_text)

    for col in 0 ..< desired.cols {
        cell := screen_get(desired, cmd_row, col)
        cell.bg = BG_COMMAND
        cell.fg = FG_COMMAND
        if col < len(full) {
            cell.char = rune(full[col])
        } else {
            cell.char = ' '
        }
    }
}

render_cursor :: proc(w: ^Window, ob: ^Output_Buffer, ed: ^Editor) {
    if ed.mode == .Command || ed.mode == .Search_Forward || ed.mode == .Search_Backward {
        cmd_row := ed.term_rows - 1
        cmd_col := ed.command_buf_len + 1
        ansi_cursor_goto(ob, cmd_row, cmd_col)
        ansi_cursor_shape_beam(ob)
        return
    }

    if ed.mode == .Insert || ed.mode == .Replace {
        ansi_cursor_shape_beam(ob)
    } else {
        ansi_cursor_shape_block(ob)
    }

    disp_col := char_to_display_col(w.buffer, w.cursor.row, w.cursor.col)
    ln_width := 1
    if w.buffer.piece_table.line_count > 9 { ln_width = 2 }
    if w.buffer.piece_table.line_count > 99 { ln_width = 3 }
    if w.buffer.piece_table.line_count > 999 { ln_width = 4 }
    screen_row := w.top + (w.cursor.row - w.scroll_row)
    screen_col := ln_width + 1 + (disp_col - w.scroll_col)

    if screen_row < ed.term_rows - 1 {
        ansi_cursor_goto(ob, screen_row, screen_col)
    }
}

mode_to_string :: proc(m: Mode) -> string {
    switch m {
    case .Normal: return "NORMAL"
    case .Insert: return "INSERT"
    case .Replace: return "REPLACE"
    case .Visual_Char: return "VISUAL"
    case .Visual_Line: return "VISUAL LINE"
    case .Visual_Block: return "VISUAL BLOCK"
    case .Command: return "COMMAND"
    case .Search_Forward: return "SEARCH"
    case .Search_Backward: return "SEARCH"
    case .Operator_Pending: return "OPERATOR PENDING"
    }
    return ""
}

line_ending_string :: proc(le: Line_Ending) -> string {
    switch le {
    case .LF: return "[LF]"
    case .CRLF: return "[CRLF]"
    case .CR: return "[CR]"
    }
    return ""
}

utf8_encode_rune :: proc(r: rune, buf: []u8) -> int {
    if r < 0x80 {
        buf[0] = u8(r)
        return 1
    }
    if r < 0x800 {
        buf[0] = u8(0xC0 | (r >> 6))
        buf[1] = u8(0x80 | (r & 0x3F))
        return 2
    }
    if r < 0x10000 {
        buf[0] = u8(0xE0 | (r >> 12))
        buf[1] = u8(0x80 | ((r >> 6) & 0x3F))
        buf[2] = u8(0x80 | (r & 0x3F))
        return 3
    }
    buf[0] = u8(0xF0 | (r >> 18))
    buf[1] = u8(0x80 | ((r >> 12) & 0x3F))
    buf[2] = u8(0x80 | ((r >> 6) & 0x3F))
    buf[3] = u8(0x80 | (r & 0x3F))
    return 4
}
