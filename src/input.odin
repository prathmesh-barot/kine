package main

import "core:unicode/utf8"
import "core:os"

Key_Mod :: enum u8 { Ctrl, Alt, Shift }
Key_Mods :: bit_set[Key_Mod]

Special_Key :: enum {
    None,
    Arrow_Up, Arrow_Down, Arrow_Left, Arrow_Right,
    Home, End, Page_Up, Page_Down,
    Insert, Delete, Backspace, Tab, Enter, Escape,
    F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12,
}

Key :: struct {
    codepoint: rune,
    special:   Special_Key,
    mods:      Key_Mods,
}

read_byte :: proc() -> (u8, bool) {
    buf: [1]u8
    n, err := os.read(os.stdin, buf[:])
    if err != nil || n == 0 {
        return 0, false
    }
    return buf[0], true
}

read_bytes_timeout :: proc(buf: []u8, timeout_ms: int) -> (int, bool) {
    total := 0
    for total < len(buf) {
        n, err := os.read(os.stdin, buf[total:])
        if err != nil {
            return total, false
        }
        if n == 0 {
            break
        }
        total += n
    }
    return total, total > 0
}

read_key :: proc() -> (Key, bool) {
    byte_val, ok := read_byte()
    if !ok {
        return Key{}, false
    }

    if byte_val == 0x1b {
        return read_escape_sequence()
    }

    if byte_val <= 0x1a {
        ctrl_val := byte_val + 0x60
        if ctrl_val == 0x09 {
            return Key{special = .Tab}, true
        }
        if ctrl_val == 0x0d {
            return Key{special = .Enter}, true
        }
        if ctrl_val == 0x1b {
            return Key{special = .Escape}, true
        }
        return Key{codepoint = rune(ctrl_val), mods = {.Ctrl}}, true
    }

    if byte_val == 0x7f {
        return Key{special = .Backspace}, true
    }

    if byte_val & 0x80 != 0 {
        rune_val, _ := utf8.decode_rune(string([]u8{byte_val}))
        utf8_len := utf8.rune_size(rune_val)
        if utf8_len > 1 {
            more_buf := make([]u8, utf8_len - 1)
            defer delete(more_buf)
            for i := 0; i < utf8_len - 1; i += 1 {
                b, ok2 := read_byte()
                if !ok2 {
                    return Key{codepoint = utf8.RUNE_ERROR}, true
                }
                more_buf[i] = b
            }
            full := make([]u8, utf8_len)
            full[0] = byte_val
            for i in 0 ..< utf8_len - 1 {
                full[i + 1] = more_buf[i]
            }
            r, _ := utf8.decode_rune(string(full))
            delete(full)
            return Key{codepoint = r}, true
        }
        return Key{codepoint = rune(byte_val)}, true
    }

    return Key{codepoint = rune(byte_val)}, true
}

parse_csi_sequence :: proc(buf: []u8, start: int, n: int) -> (Key, bool) {
    pos := start
    params: [16]int
    param_count := 0

    for pos < n && buf[pos] >= 0x30 && buf[pos] <= 0x3f {
        if buf[pos] >= 0x30 && buf[pos] <= 0x39 {
            val := 0
            for pos < n && buf[pos] >= 0x30 && buf[pos] <= 0x39 {
                val = val * 10 + int(buf[pos] - 0x30)
                pos += 1
            }
            if param_count < len(params) {
                params[param_count] = val
            }
            param_count += 1
        } else if buf[pos] == ';' {
            pos += 1
        } else {
            pos += 1
        }
    }

    for pos < n && buf[pos] >= 0x20 && buf[pos] <= 0x2f {
        pos += 1
    }

    if pos >= n {
        return Key{special = .Escape}, true
    }

    terminator := buf[pos]

    mods := Key_Mods{}
    if param_count >= 2 && params[1] >= 2 {
        if params[1] == 2 { mods += {.Shift} }
        else if params[1] == 3 { mods += {.Alt} }
        else if params[1] == 4 { mods += {.Alt, .Shift} }
        else if params[1] == 5 { mods += {.Ctrl} }
        else if params[1] == 6 { mods += {.Ctrl, .Shift} }
        else if params[1] == 7 { mods += {.Ctrl, .Alt} }
        else if params[1] == 8 { mods += {.Ctrl, .Alt, .Shift} }
    }

    switch terminator {
    case 'A': return Key{special = .Arrow_Up, mods = mods}, true
    case 'B': return Key{special = .Arrow_Down, mods = mods}, true
    case 'C': return Key{special = .Arrow_Right, mods = mods}, true
    case 'D': return Key{special = .Arrow_Left, mods = mods}, true
    case 'H': return Key{special = .Home}, true
    case 'F': return Key{special = .End}, true
    case '~':
        switch params[0] {
        case 1:  return Key{special = .Home}, true
        case 2:  return Key{special = .Insert}, true
        case 3:  return Key{special = .Delete}, true
        case 4:  return Key{special = .End}, true
        case 5:  return Key{special = .Page_Up}, true
        case 6:  return Key{special = .Page_Down}, true
        case 15: return Key{special = .F5}, true
        case 17: return Key{special = .F6}, true
        case 18: return Key{special = .F7}, true
        case 19: return Key{special = .F8}, true
        case 20: return Key{special = .F9}, true
        case 21: return Key{special = .F10}, true
        case 23: return Key{special = .F11}, true
        case 24: return Key{special = .F12}, true
        }
    }

    return Key{special = .Escape}, true
}

read_escape_sequence :: proc() -> (Key, bool) {
    buf: [32]u8
    n, ok := read_bytes_timeout(buf[:], 50)
    if !ok || n == 0 {
        return Key{special = .Escape}, true
    }

    first := buf[0]

    if first == '[' {
        return parse_csi_sequence(buf[:], 1, n)
    }

    if first == 'O' {
        if n < 2 {
            return Key{special = .Escape}, true
        }
        switch buf[1] {
        case 'H': return Key{special = .Home}, true
        case 'F': return Key{special = .End}, true
        case 'P': return Key{special = .F1}, true
        case 'Q': return Key{special = .F2}, true
        case 'R': return Key{special = .F3}, true
        case 'S': return Key{special = .F4}, true
        case 'A': return Key{special = .Arrow_Up}, true
        case 'B': return Key{special = .Arrow_Down}, true
        case 'C': return Key{special = .Arrow_Right}, true
        case 'D': return Key{special = .Arrow_Left}, true
        case:
            return Key{codepoint = rune(buf[1]), mods = {.Alt}}, true
        }
    }

    if first >= 0x20 && first <= 0x7e {
        if n > 1 && buf[1] >= 0x20 && buf[1] <= 0x7e {
            r, _ := utf8.decode_rune(string(buf[:n]))
            return Key{codepoint = r, mods = {.Alt}}, true
        }
        return Key{codepoint = rune(first), mods = {.Alt}}, true
    }

    return Key{special = .Escape}, true
}
