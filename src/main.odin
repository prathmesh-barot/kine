package main

import "core:fmt"
import "core:os"

main :: proc() {
    if !editor_init() {
        fmt.eprintln("Failed to initialize editor")
        os.exit(1)
    }
    defer editor_shutdown()

    for ed := &editor; ed.running; {
        resize_pending = false
        editor_resize()

        w := ed.active_window
        if w != nil {
            w.width = ed.term_cols
            w.height = ed.term_rows - 2
        }

        key, ok := read_key()
        if ok {
            process_key(ed, key)
        }

        if ed.active_window != nil && ed.active_window.buffer != nil {
            scroll_into_view(ed.active_window)
        }

        render_frame(ed.active_window, &ed.current_screen, &ed.desired_screen, &ed.output_buf, ed)

        ob_flush(&ed.output_buf)
    }

    terminal_cleanup()
}

terminal_cleanup :: proc() {
    ed := &editor
    ansi_cursor_show(&ed.output_buf)
    ansi_exit_alt_screen(&ed.output_buf)
    ob_flush(&ed.output_buf)
    exit_raw_mode(&ed.term_state)
}
