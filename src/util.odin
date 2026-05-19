package main

import "core:mem"
import "core:os"

log_file: os.File

log_init :: proc() -> bool {
    return true
}

log_write :: proc(msg: string) {
}

log_error :: proc(msg: string) {
}

log_debug :: proc(msg: string) {
}

log_destroy :: proc() {
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
