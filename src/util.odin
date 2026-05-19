package main

import "core:mem"
import "core:os"
import "core:strings"

DEBUG :: #config(DEBUG, false)

log_file: ^os.File = nil

log_init :: proc() -> bool {
    home_buf: [256]u8
    home, lookup_err := os.lookup_env(home_buf[:], "HOME")
    if lookup_err != nil {
        return true
    }
    log_dir := strings.concatenate({home, "/.kine"})
    os.make_directory(log_dir)
    delete(log_dir)
    log_path := strings.concatenate({home, "/.kine/log"})
    fd, err := os.open(log_path, os.File_Flags{.Write, .Create, .Append})
    delete(log_path)
    if err != nil {
        return true
    }
    log_file = fd
    return true
}

log_write :: proc(msg: string) {
    if log_file != nil {
        os.write(log_file, transmute([]u8)msg)
        os.write(log_file, []u8{'\n'})
    }
}

log_error :: proc(msg: string) {
    log_write(strings.concatenate({"[ERROR] ", msg}))
}

log_debug :: proc(msg: string) {
    when DEBUG {
        log_write(strings.concatenate({"[DEBUG] ", msg}))
    }
}

log_destroy :: proc() {
    if log_file != nil {
        os.close(log_file)
        log_file = nil
    }
}

Allocator_Error :: mem.Allocator_Error

Error :: union #shared_nil {
    os.Error,
    Allocator_Error,
}

Vec2 :: [2]int

Color :: u8

DEFAULT_TAB_WIDTH :: 4
SCROLLOFF :: 5
SIDESCROLLOFF :: 3

Color_Mode :: enum {
    Bit16,
    Bit256,
    TrueColor,
}

detect_color_mode :: proc() -> Color_Mode {
    colorterm_buf: [64]u8
    colorterm, err1 := os.lookup_env(colorterm_buf[:], "COLORTERM")
    if err1 == nil && (colorterm == "truecolor" || colorterm == "24bit") {
        return .TrueColor
    }
    term_buf: [64]u8
    term, err2 := os.lookup_env(term_buf[:], "TERM")
    if err2 == nil && strings.contains(term, "256") {
        return .Bit256
    }
    return .Bit16
}

is_word_char :: proc(b: u8) -> bool {
    return (b >= 'a' && b <= 'z') ||
           (b >= 'A' && b <= 'Z') ||
           (b >= '0' && b <= '9') ||
           b == '_'
}

is_non_whitespace :: proc(b: u8) -> bool {
    return b != ' ' && b != '\t' && b != '\n' && b != '\r'
}
