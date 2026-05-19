package main

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:sys/linux"
import "core:sys/posix"

resize_pending: bool

Terminal_State :: struct {
    original: posix.termios,
}

enter_raw_mode :: proc(ts: ^Terminal_State) -> bool {
    when ODIN_OS == .Linux || ODIN_OS == .Darwin {
        if posix.tcgetattr(posix.STDIN_FILENO, &ts.original) != .OK {
            return false
        }
        raw := ts.original
        raw.c_iflag &~= {.BRKINT, .ICRNL, .INPCK, .ISTRIP, .IXON}
        raw.c_oflag &~= {.OPOST}
        raw.c_cflag |= {.CS8}
        raw.c_lflag &~= {.ECHO, .ICANON, .IEXTEN, .ISIG}
        raw.c_cc[posix.Control_Char.VMIN] = 0
        raw.c_cc[posix.Control_Char.VTIME] = 1
        return posix.tcsetattr(posix.STDIN_FILENO, .TCSAFLUSH, &raw) == .OK
    }
    when ODIN_OS == .Windows {
        return false
    }
    return false
}

exit_raw_mode :: proc(ts: ^Terminal_State) {
    when ODIN_OS == .Linux || ODIN_OS == .Darwin {
        posix.tcsetattr(posix.STDIN_FILENO, .TCSAFLUSH, &ts.original)
    }
}

winsize :: struct {
    row: u16,
    col: u16,
    xpixel: u16,
    ypixel: u16,
}

TIOCGWINSZ :: 0x5413

get_terminal_size :: proc() -> (cols, rows: int, ok: bool) {
    when ODIN_OS == .Linux {
        ws: winsize
        result := linux.ioctl(linux.Fd(1), TIOCGWINSZ, cast(uintptr)&ws)
        if result == 0 {
            return int(ws.col), int(ws.row), true
        }
    }
    return 80, 24, false
}

Output_Buffer :: struct {
    data: [dynamic]u8,
}

ob_init :: proc(ob: ^Output_Buffer) {
    ob.data = make([dynamic]u8, 0, 4096)
}

ob_destroy :: proc(ob: ^Output_Buffer) {
    delete(ob.data)
}

ob_write :: proc(ob: ^Output_Buffer, s: string) {
    append(&ob.data, ..transmute([]u8)s)
}

ob_write_byte :: proc(ob: ^Output_Buffer, b: u8) {
    append(&ob.data, b)
}

ob_printf :: proc(ob: ^Output_Buffer, fmt_str: string, args: ..any) {
    s := fmt.tprintf(fmt_str, ..args)
    ob_write(ob, s)
}

ob_flush :: proc(ob: ^Output_Buffer) {
    if len(ob.data) > 0 {
        os.write(os.stdout, ob.data[:])
        clear(&ob.data)
    }
}

ansi_clear_screen :: #force_inline proc(ob: ^Output_Buffer) { ob_write(ob, "\x1b[2J") }
ansi_clear_line :: #force_inline proc(ob: ^Output_Buffer) { ob_write(ob, "\x1b[2K") }
ansi_cursor_home :: #force_inline proc(ob: ^Output_Buffer) { ob_write(ob, "\x1b[H") }
ansi_cursor_goto :: #force_inline proc(ob: ^Output_Buffer, row, col: int) {
    ob_printf(ob, "\x1b[%d;%dH", row + 1, col + 1)
}
ansi_cursor_hide :: #force_inline proc(ob: ^Output_Buffer) { ob_write(ob, "\x1b[?25l") }
ansi_cursor_show :: #force_inline proc(ob: ^Output_Buffer) { ob_write(ob, "\x1b[?25h") }
ansi_reset :: #force_inline proc(ob: ^Output_Buffer) { ob_write(ob, "\x1b[0m") }
ansi_set_fg :: #force_inline proc(ob: ^Output_Buffer, color: u8) {
    ob_printf(ob, "\x1b[38;5;%dm", color)
}
ansi_set_bg :: #force_inline proc(ob: ^Output_Buffer, color: u8) {
    ob_printf(ob, "\x1b[48;5;%dm", color)
}
ansi_set_fg_rgb :: #force_inline proc(ob: ^Output_Buffer, r, g, b: u8) {
    ob_printf(ob, "\x1b[38;2;%d;%d;%dm", r, g, b)
}
ansi_set_bg_rgb :: #force_inline proc(ob: ^Output_Buffer, r, g, b: u8) {
    ob_printf(ob, "\x1b[48;2;%d;%d;%dm", r, g, b)
}
ansi_bold :: #force_inline proc(ob: ^Output_Buffer) { ob_write(ob, "\x1b[1m") }
ansi_italic :: #force_inline proc(ob: ^Output_Buffer) { ob_write(ob, "\x1b[3m") }
ansi_underline :: #force_inline proc(ob: ^Output_Buffer) { ob_write(ob, "\x1b[4m") }
ansi_reverse :: #force_inline proc(ob: ^Output_Buffer) { ob_write(ob, "\x1b[7m") }
ansi_strikethrough :: #force_inline proc(ob: ^Output_Buffer) { ob_write(ob, "\x1b[9m") }
ansi_cursor_shape_block :: #force_inline proc(ob: ^Output_Buffer) { ob_write(ob, "\x1b[2 q") }
ansi_cursor_shape_beam :: #force_inline proc(ob: ^Output_Buffer) { ob_write(ob, "\x1b[6 q") }
ansi_cursor_shape_underline :: #force_inline proc(ob: ^Output_Buffer) { ob_write(ob, "\x1b[4 q") }
ansi_enter_alt_screen :: #force_inline proc(ob: ^Output_Buffer) { ob_write(ob, "\x1b[?1049h") }
ansi_exit_alt_screen :: #force_inline proc(ob: ^Output_Buffer) { ob_write(ob, "\x1b[?1049l") }
ansi_enable_mouse :: #force_inline proc(ob: ^Output_Buffer) { ob_write(ob, "\x1b[?1000h\x1b[?1006h") }
ansi_disable_mouse :: #force_inline proc(ob: ^Output_Buffer) { ob_write(ob, "\x1b[?1000l\x1b[?1006l") }
ansi_enable_bracketed_paste :: #force_inline proc(ob: ^Output_Buffer) { ob_write(ob, "\x1b[?2004h") }
ansi_disable_bracketed_paste :: #force_inline proc(ob: ^Output_Buffer) { ob_write(ob, "\x1b[?2004l") }

SIGWINCH :: 28
SIGPIPE :: 13
SIG_IGN :: 1

signal_handler :: proc "c" (sig: posix.Signal) {
    if sig == posix.Signal(posix.SIGINT) || sig == posix.Signal(posix.SIGTERM) {
        context = runtime.default_context()
        editor_shutdown()
        os.exit(0)
    }
    if sig == posix.Signal(SIGWINCH) {
        resize_pending = true
    }
}

signal_setup :: proc() {
    posix.signal(posix.Signal(posix.SIGINT), signal_handler)
    posix.signal(posix.Signal(posix.SIGTERM), signal_handler)
    posix.signal(posix.Signal(SIGWINCH), signal_handler)
    posix.signal(posix.Signal(posix.SIGPIPE), cast(proc "c" (posix.Signal))posix.SIG_IGN)
}
