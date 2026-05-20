package main

import "core:os"
import "core:strings"

Line_Ending :: enum {
    LF,
    CRLF,
    CR,
}

Piece_Source :: enum {
    Original,
    Add,
}

Piece :: struct {
    source: Piece_Source,
    start:  int,
    length: int,
    prev:   ^Piece,
    next:   ^Piece,
}

Piece_Table :: struct {
    original:       string,
    original_data:  [dynamic]u8,
    add_buffer:     [dynamic]u8,
    head:           ^Piece,
    tail:           ^Piece,
    piece_pool:     [dynamic]Piece,
    char_count:     int,
    line_count:     int,
    line_starts:    [dynamic]int,
}

Buffer :: struct {
    id:              int,
    filepath:        string,
    name:            string,
    piece_table:     Piece_Table,
    undo_stack:      Undo_Stack,
    modified:        bool,
    readonly:        bool,
    filetype:        string,
    encoding:        string,
    line_ending:     Line_Ending,
    tab_width:       int,
    expand_tabs:     bool,
    large_file:      bool,
    last_saved_seq:  int,
}

Undo_Kind :: enum {
    Insert,
    Delete,
}

Undo_Record :: struct {
    kind:          Undo_Kind,
    pos:           int,
    text:          string,
    cursor_before: Vec2,
    cursor_after:  Vec2,
    seq:           int,
}

Undo_Stack :: struct {
    records: [dynamic]Undo_Record,
    head:    int,
    seq:     int,
}

pt_init :: proc(pt: ^Piece_Table, original: string) {
    pt.original_data = make([dynamic]u8, len(original))
    copy(pt.original_data[:], transmute([]u8)original)
    pt.original = string(pt.original_data[:])
    pt.add_buffer = make([dynamic]u8, 0, 1024)
    pt.piece_pool = make([dynamic]Piece, 0, 64)
    pt.line_starts = make([dynamic]int, 0, 64)
    pt.char_count = 0
    pt.line_count = 0

    piece := Piece{source = .Original, start = 0, length = len(original)}
    append(&pt.piece_pool, piece)
    pt.head = &pt.piece_pool[0]
    pt.tail = pt.head

    rebuild_line_starts(pt)
}

pt_destroy :: proc(pt: ^Piece_Table) {
    delete(pt.original_data)
    delete(pt.add_buffer)
    delete(pt.piece_pool)
    delete(pt.line_starts)
}

rebuild_line_starts :: proc(pt: ^Piece_Table) {
    clear(&pt.line_starts)
    append(&pt.line_starts, 0)
    pt.line_count = 1
    pt.char_count = 0

    piece := pt.head
    for piece != nil {
        str_data := piece_data(pt, piece^)
        for i in 0 ..< len(str_data) {
            pt.char_count += 1
            if str_data[i] == 10 {
                append(&pt.line_starts, pt.char_count)
                pt.line_count += 1
            }
        }
        piece = piece.next
    }
}

piece_data :: proc(pt: ^Piece_Table, p: Piece) -> string {
    if p.source == .Original {
        return pt.original[p.start:p.start + p.length]
    }
    return string(pt.add_buffer[p.start:p.start + p.length])
}

pt_insert :: proc(pt: ^Piece_Table, pos: int, text: string) {
    if pos > pt.char_count { return }
    if len(text) == 0 { return }

    piece, offset := find_piece_at(pt, pos)

    if piece != nil {
        split_piece(pt, piece, offset)
    }

    start := len(pt.add_buffer)
    append(&pt.add_buffer, ..transmute([]u8)text)

    new_piece := Piece{source = .Add, start = start, length = len(text)}
    append(&pt.piece_pool, new_piece)
    new_node := &pt.piece_pool[len(pt.piece_pool) - 1]

    if piece != nil {
        next_piece := piece.next
        new_node.prev = piece
        new_node.next = next_piece
        piece.next = new_node
        if next_piece != nil {
            next_piece.prev = new_node
        } else {
            pt.tail = new_node
        }
    } else {
        new_node.next = pt.head
        if pt.head != nil {
            pt.head.prev = new_node
        } else {
            pt.tail = new_node
        }
        pt.head = new_node
    }

    pt.char_count += len(text)

    newline_count := 0
    for c in text {
        if c == '\n' { newline_count += 1 }
    }
    if newline_count > 0 || pos < pt.char_count - len(text) {
        rebuild_line_starts(pt)
    }
}

pt_delete :: proc(pt: ^Piece_Table, pos: int, length: int) {
    if length <= 0 || pos >= pt.char_count { return }

    del_len := min(length, pt.char_count - pos)
    if del_len <= 0 { return }

    piece, offset := find_piece_at(pt, pos)
    if piece == nil { return }

    if offset > 0 {
        split_piece(pt, piece, offset)
    }

    end_pos := pos + del_len
    end_piece, end_offset := find_piece_at(pt, end_pos)
    if end_piece == nil { return }
    if end_offset > 0 {
        split_piece(pt, end_piece, end_offset)
    }

    start_piece: ^Piece
    if offset > 0 {
        start_piece = piece.next
    } else {
        start_piece = piece
    }

    end_piece_stop: ^Piece
    if end_offset > 0 {
        end_piece_stop = end_piece.next
    } else {
        end_piece_stop = end_piece
    }

    p := start_piece
    for p != nil && p != end_piece_stop {
        next := p.next
        p.length = 0
        p = next
    }

    if start_piece != nil {
        if start_piece.prev != nil {
            start_piece.prev.next = end_piece_stop
            if end_piece_stop != nil {
                end_piece_stop.prev = start_piece.prev
            } else {
                pt.tail = start_piece.prev
            }
        } else {
            pt.head = end_piece_stop
            if end_piece_stop != nil {
                end_piece_stop.prev = nil
            } else {
                pt.tail = nil
            }
        }
    }

    pt.char_count -= del_len
    rebuild_line_starts(pt)
}

find_piece_at :: proc(pt: ^Piece_Table, pos: int) -> (piece: ^Piece, offset: int) {
    if pos <= 0 {
        return pt.head, 0
    }
    if pos >= pt.char_count {
        piece = pt.tail
        if piece != nil {
            offset = piece.length
        }
        return
    }

    cumulative := 0
    piece = pt.head
    for piece != nil {
        if pos < cumulative + piece.length {
            return piece, pos - cumulative
        }
        cumulative += piece.length
        piece = piece.next
    }
    return pt.tail, 0
}

split_piece :: proc(pt: ^Piece_Table, p: ^Piece, offset: int) {
    if offset <= 0 || offset >= p.length { return }

    new_p := Piece{
        source = p.source,
        start  = p.start + offset,
        length = p.length - offset,
    }
    append(&pt.piece_pool, new_p)
    new_node := &pt.piece_pool[len(pt.piece_pool) - 1]

    p.length = offset

    new_node.prev = p
    new_node.next = p.next
    p.next = new_node
    if new_node.next != nil {
        new_node.next.prev = new_node
    } else {
        pt.tail = new_node
    }
}

pt_char_at :: proc(pt: ^Piece_Table, pos: int) -> u8 {
    piece, offset := find_piece_at(pt, pos)
    if piece == nil { return 0 }
    data := piece_data(pt, piece^)
    if offset < len(data) {
        return data[offset]
    }
    return 0
}

pt_substring :: proc(pt: ^Piece_Table, pos: int, length: int) -> string {
    if length <= 0 { return "" }

    buf := make([]u8, length)
    remaining := length
    piece, offset := find_piece_at(pt, pos)

    for piece != nil && remaining > 0 {
        str_data := piece_data(pt, piece^)
        available := min(len(str_data) - offset, remaining)
        if available > 0 {
            copy(buf[length - remaining:], str_data[offset:offset + available])
            remaining -= available
        }
        offset = 0
        piece = piece.next
    }

    return string(buf)
}

pt_get_line :: proc(pt: ^Piece_Table, line: int) -> string {
    if line < 0 || line >= pt.line_count { return "" }

    line_start := pt.line_starts[line]
    line_end := pt.char_count
    if line + 1 < pt.line_count {
        line_end = pt.line_starts[line + 1]
    }

    length := line_end - line_start
    if length > 0 {
        line_text := pt_substring(pt, line_start, length)
        if len(line_text) > 0 && line_text[len(line_text) - 1] == '\n' {
            trimmed := strings.clone(line_text[:len(line_text) - 1])
            delete(line_text)
            return trimmed
        }
        return line_text
    }
    return ""
}

Line_Ending_Counts :: struct {
    lf:   int,
    crlf: int,
    cr:   int,
}

detect_line_endings :: proc(data: []byte) -> Line_Ending {
    counts: Line_Ending_Counts
    max_check := min(len(data), 8192)
    i := 0
    for i < max_check {
        if data[i] == '\r' {
            if i + 1 < max_check && data[i + 1] == '\n' {
                counts.crlf += 1
                i += 2
            } else {
                counts.cr += 1
                i += 1
            }
        } else if data[i] == '\n' {
            counts.lf += 1
            i += 1
        } else {
            i += 1
        }
    }

    if counts.crlf > counts.lf && counts.crlf > counts.cr { return .CRLF }
    if counts.cr > counts.lf && counts.cr > counts.crlf { return .CR }
    return .LF
}

strip_bom :: proc(data: []u8) -> []u8 {
    if len(data) >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF {
        result := make([]u8, len(data) - 3)
        copy(result, data[3:])
        return result
    }
    if len(data) >= 2 {
        if (data[0] == 0xFE && data[1] == 0xFF) || (data[0] == 0xFF && data[1] == 0xFE) {
            result := make([]u8, len(data) - 2)
            copy(result, data[2:])
            return result
        }
    }
    return data
}

detect_encoding :: proc(data: []u8) -> string {
    if len(data) >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF {
        return "utf-8"
    }
    if len(data) >= 2 {
        if data[0] == 0xFE && data[1] == 0xFF {
            return "utf-16be"
        }
        if data[0] == 0xFF && data[1] == 0xFE {
            return "utf-16le"
        }
    }
    for i in 0 ..< min(len(data), 8192) {
        if data[i] >= 0x80 {
            if i + 1 < len(data) && (data[i] & 0xE0) == 0xC0 && (data[i + 1] & 0xC0) == 0x80 {
                continue
            }
            if i + 2 < len(data) && (data[i] & 0xF0) == 0xE0 && (data[i + 1] & 0xC0) == 0x80 && (data[i + 2] & 0xC0) == 0x80 {
                continue
            }
            return "latin-1"
        }
    }
    return "utf-8"
}

detect_filetype :: proc(path: string) -> string {
    ext_idx := strings.last_index(path, ".")
    if ext_idx == -1 { return "text" }
    switch path[ext_idx:] {
    case ".odin": return "odin"
    case ".c", ".h", ".cpp", ".hpp", ".cxx": return "c"
    case ".rs": return "rust"
    case ".go": return "go"
    case ".py": return "python"
    case ".js", ".ts", ".jsx", ".tsx": return "javascript"
    case ".lua": return "lua"
    case ".sh", ".bash": return "shell"
    case ".md", ".markdown": return "markdown"
    case ".json": return "json"
    case ".toml": return "toml"
    case ".yaml", ".yml": return "yaml"
    case ".txt": return "text"
    }
    return "text"
}

buffer_open :: proc(path: string) -> (^Buffer, Error) {
    data, err := os.read_entire_file_from_path(path, context.allocator)
    if err != nil {
        return nil, err
    }
    defer delete(data)

    file_size := len(data)
    is_large := file_size > 10 * 1024 * 1024

    encoding := detect_encoding(data)
    data = strip_bom(data)

    line_ending := detect_line_endings(data)

    normalized := make([dynamic]u8, 0, len(data))
    for i := 0; i < len(data); i += 1 {
        if line_ending == .CRLF && data[i] == '\r' && i + 1 < len(data) && data[i + 1] == '\n' {
            append(&normalized, u8('\n'))
            i += 1
        } else if line_ending == .CR && data[i] == '\r' {
            append(&normalized, u8('\n'))
        } else {
            append(&normalized, data[i])
        }
    }

    buf := new(Buffer)
    buf.id = editor_next_buffer_id()
    buf.filepath = strings.clone(path)
    name_idx := strings.last_index(path, "/")
    if name_idx == -1 {
        buf.name = strings.clone(path)
    } else {
        buf.name = strings.clone(path[name_idx+1:])
    }
    buf.modified = false
    buf.readonly = false
    buf.filetype = detect_filetype(path)
    buf.encoding = encoding
    buf.line_ending = line_ending
    buf.tab_width = DEFAULT_TAB_WIDTH
    buf.expand_tabs = false
    buf.large_file = is_large
    buf.last_saved_seq = 0

    if !is_large {
        undo_stack_init(&buf.undo_stack)
    }

    pt_init(&buf.piece_table, string(normalized[:]))
    return buf, nil
}

buffer_new_scratch :: proc() -> (^Buffer, Error) {
    buf := new(Buffer)
    buf.id = editor_next_buffer_id()
    buf.filepath = ""
    buf.name = strings.clone("[No Name]")
    buf.modified = false
    buf.readonly = false
    buf.filetype = "text"
    buf.encoding = "utf-8"
    buf.line_ending = .LF
    buf.tab_width = DEFAULT_TAB_WIDTH
    buf.expand_tabs = false
    buf.large_file = false
    buf.last_saved_seq = 0

    pt_init(&buf.piece_table, strings.clone(""))
    return buf, nil
}

buffer_close :: proc(buf: ^Buffer) {
    pt_destroy(&buf.piece_table)
    if len(buf.filepath) > 0 { delete(buf.filepath) }
    delete(buf.name)
    free(buf)
}

buffer_save :: proc(buf: ^Buffer, path: string) -> Error {
    data := make([dynamic]u8, 0, buf.piece_table.char_count + 1)

    piece := buf.piece_table.head
    for piece != nil {
        d := piece_data(&buf.piece_table, piece^)
        if buf.line_ending == .LF {
            for i in 0 ..< len(d) {
                append(&data, d[i])
            }
        } else {
            for i in 0 ..< len(d) {
                if d[i] == 10 {
                    if buf.line_ending == .CRLF {
                        append(&data, u8('\r'), u8('\n'))
                    } else {
                        append(&data, u8('\r'))
                    }
                } else {
                    append(&data, d[i])
                }
            }
        }
        piece = piece.next
    }

    err2 := os.write_entire_file(path, data[:])
    delete(data)
    if err2 != nil { return err2 }

    if path != buf.filepath {
        if len(buf.filepath) > 0 { delete(buf.filepath) }
        buf.filepath = strings.clone(path)
        name_idx := strings.last_index(path, "/")
        delete(buf.name)
        buf.name = strings.clone(path[name_idx:])
    }

    buf.modified = false
    buf.last_saved_seq = undo_seq_counter + 1
    return nil
}

buffer_reload :: proc(buf: ^Buffer) -> Error {
    data, err := os.read_entire_file_from_path(buf.filepath, context.allocator)
    if err != nil { return err }
    defer delete(data)

    pt_destroy(&buf.piece_table)

    buf.encoding = detect_encoding(data)
    data = strip_bom(data)

    line_ending := detect_line_endings(data)
    buf.line_ending = line_ending

    normalized := make([dynamic]u8, 0, len(data))
    for i := 0; i < len(data); i += 1 {
        if line_ending == .CRLF && data[i] == '\r' && i + 1 < len(data) && data[i + 1] == '\n' {
            append(&normalized, u8('\n'))
            i += 1
        } else if line_ending == .CR && data[i] == '\r' {
            append(&normalized, u8('\n'))
        } else {
            append(&normalized, data[i])
        }
    }

    pt_init(&buf.piece_table, string(normalized[:]))
    buf.modified = false
    buf.large_file = len(data) > 10 * 1024 * 1024
    return nil
}

undo_seq_counter: int = 0

undo_stack_init :: proc(s: ^Undo_Stack) {
    s.records = make([dynamic]Undo_Record, 0, 128)
    s.head = 0
    s.seq = 0
}

undo_stack_destroy :: proc(s: ^Undo_Stack) {
    for r in s.records {
        delete(r.text)
    }
    delete(s.records)
}

undo_stack_push :: proc(s: ^Undo_Stack, kind: Undo_Kind, pos: int, text: string, cursor_before, cursor_after: Vec2) {
    for i := len(s.records) - 1; i >= s.head; i -= 1 {
        delete(s.records[i].text)
    }
    resize(&s.records, s.head)
    undo_seq_counter += 1
    rec := Undo_Record{
        kind = kind,
        pos = pos,
        text = strings.clone(text),
        cursor_before = cursor_before,
        cursor_after = cursor_after,
        seq = undo_seq_counter,
    }
    append(&s.records, rec)
    s.head = len(s.records)
    s.seq = undo_seq_counter
}

undo_stack_can_undo :: proc(s: ^Undo_Stack) -> bool {
    return s.head > 0
}

undo_stack_can_redo :: proc(s: ^Undo_Stack) -> bool {
    return s.head < len(s.records)
}

undo_stack_undo :: proc(s: ^Undo_Stack) -> Maybe(Undo_Record) {
    if !undo_stack_can_undo(s) { return nil }
    s.head -= 1
    return s.records[s.head]
}

undo_stack_redo :: proc(s: ^Undo_Stack) -> Maybe(Undo_Record) {
    if !undo_stack_can_redo(s) { return nil }
    rec := s.records[s.head]
    s.head += 1
    return rec
}
