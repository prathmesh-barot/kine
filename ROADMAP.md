# ROADMAP — Odin Modal Text Editor
> A fully-featured, terminal-based modal text editor written in Odin.
> This roadmap is ordered by dependency, not time. Each section must be complete before the next builds on it.
> "Perfect" means: stable, fast, correct, featureful enough to use as your daily driver.

---

## TABLE OF CONTENTS

1. [Project Structure & Conventions](#1-project-structure--conventions)
2. [Terminal Layer](#2-terminal-layer)
3. [Input Handling](#3-input-handling)
4. [Core Data Structures](#4-core-data-structures)
5. [Buffer Management](#5-buffer-management)
6. [Cursor & Motion Engine](#6-cursor--motion-engine)
7. [Viewport & Rendering Engine](#7-viewport--rendering-engine)
8. [Mode System](#8-mode-system)
9. [Normal Mode — Complete Keybindings](#9-normal-mode--complete-keybindings)
10. [Insert Mode](#10-insert-mode)
11. [Visual Mode](#11-visual-mode)
12. [Command Mode](#12-command-mode)
13. [File I/O](#13-file-io)
14. [Search & Replace](#14-search--replace)
15. [Undo / Redo System](#15-undo--redo-system)
16. [Registers & Clipboard](#16-registers--clipboard)
17. [Marks](#17-marks)
18. [Macros](#18-macros)
19. [Multiple Buffers & Buffer List](#19-multiple-buffers--buffer-list)
20. [Windows & Splits](#20-windows--splits)
21. [Tabs](#21-tabs)
22. [Status Line & Command Bar](#22-status-line--command-bar)
23. [Syntax Highlighting](#23-syntax-highlighting)
24. [Configuration System](#24-configuration-system)
25. [Keybinding Remapping](#25-keybinding-remapping)
26. [Autocommands & Hooks](#26-autocommands--hooks)
27. [File Explorer / Directory Browser](#27-file-explorer--directory-browser)
28. [Fuzzy Finder](#28-fuzzy-finder)
29. [Completion Engine](#29-completion-engine)
30. [LSP Client](#30-lsp-client)
31. [Diagnostics & Inline Errors](#31-diagnostics--inline-errors)
32. [Git Integration](#32-git-integration)
33. [Plugin / Extension System](#33-plugin--extension-system)
34. [Performance & Correctness Hardening](#34-performance--correctness-hardening)
35. [Testing Infrastructure](#35-testing-infrastructure)
36. [Final Polish & Packaging](#36-final-polish--packaging)

---

## 1. Project Structure & Conventions

### 1.1 Directory Layout

```
odin-editor/
├── src/
│   ├── main.odin              # Entry point, top-level event loop
│   ├── editor.odin            # Global editor state, init/shutdown
│   ├── terminal.odin          # Platform terminal layer
│   ├── input.odin             # Keypress parsing, escape sequences
│   ├── buffer.odin            # Buffer data structure + operations
│   ├── cursor.odin            # Cursor, motion, text objects
│   ├── viewport.odin          # Scroll, window geometry
│   ├── renderer.odin          # ANSI output, screen diffing
│   ├── mode.odin              # Mode enum + dispatch
│   ├── normal.odin            # Normal mode key handlers
│   ├── insert.odin            # Insert mode logic
│   ├── visual.odin            # Visual mode logic
│   ├── command.odin           # Ex command parser & executor
│   ├── search.odin            # Search, highlight, replace
│   ├── undo.odin              # Undo/redo stack
│   ├── register.odin          # Named registers + clipboard
│   ├── mark.odin              # Mark system
│   ├── macro.odin             # Macro record/playback
│   ├── window.odin            # Window/split management
│   ├── tab.odin               # Tab management
│   ├── statusline.odin        # Status line rendering
│   ├── highlight.odin         # Syntax highlight engine
│   ├── config.odin            # Config file parsing
│   ├── keymap.odin            # Keybinding table + remap
│   ├── autocmd.odin           # Autocommand system
│   ├── explorer.odin          # Directory browser
│   ├── fuzzy.odin             # Fuzzy finder
│   ├── completion.odin        # Completion engine
│   ├── lsp.odin               # LSP client protocol
│   ├── lsp_handler.odin       # LSP response dispatch
│   ├── diagnostics.odin       # Diagnostics display
│   ├── git.odin               # Git integration
│   └── util.odin              # Shared helpers, arena allocator wrappers
├── tests/
│   ├── buffer_test.odin
│   ├── motion_test.odin
│   ├── undo_test.odin
│   └── search_test.odin
├── config/
│   └── init.conf              # Default user config (shipped with binary)
├── build.sh                   # Build script
└── README.md
```

### 1.2 Build System

- Use `odin build src/ -out:editor` as base command.
- `build.sh` wraps this with flags: `-o:speed` for release, `-debug` for dev.
- Define `DEBUG :: #config(DEBUG, false)` for conditional logging.
- Use `when ODIN_OS == .Linux` / `.Windows` / `.Darwin` for platform forks.

### 1.3 Memory Strategy

- One permanent arena for editor lifetime allocations (config, keymap tables).
- One per-frame scratch arena, reset each render loop.
- Buffers use `[dynamic]` arrays with explicit `delete` on buffer close.
- All string temporaries in scratch arena — never leak into permanent state.
- No GC reliance. Every allocation site must have a matching free path.

### 1.4 Error Handling Convention

- Use `(value, ok: bool)` returns everywhere, not panics.
- `log_error` writes to a `~/.editor/log` file, never to stdout (would corrupt TUI).
- Fatal unrecoverable errors: restore terminal first, THEN crash.

---

## 2. Terminal Layer

### 2.1 Raw Mode

The terminal must be put into raw mode so keypresses are delivered immediately without line buffering or echo.

**Linux/macOS (`termios`):**
```odin
import "core:sys/posix"

Termios_State :: struct {
    original: posix.termios,
}

enter_raw_mode :: proc(state: ^Termios_State) -> bool {
    if posix.tcgetattr(posix.STDIN_FILENO, &state.original) != .OK do return false
    raw := state.original
    raw.c_iflag &~= {.BRKINT, .ICRNL, .INPCK, .ISTRIP, .IXON}
    raw.c_oflag &~= {.OPOST}
    raw.c_cflag |= {.CS8}
    raw.c_lflag &~= {.ECHO, .ICANON, .IEXTEN, .ISIG}
    raw.c_cc[.VMIN]  = 0
    raw.c_cc[.VTIME] = 1  // 100ms read timeout
    return posix.tcsetattr(posix.STDIN_FILENO, .TCSAFLUSH, &raw) == .OK
}

exit_raw_mode :: proc(state: ^Termios_State) {
    posix.tcsetattr(posix.STDIN_FILENO, .TCSAFLUSH, &state.original)
}
```

**Windows:**
- Use `GetConsoleMode` / `SetConsoleMode` with `ENABLE_VIRTUAL_TERMINAL_PROCESSING`.
- Disable `ENABLE_LINE_INPUT`, `ENABLE_ECHO_INPUT`, `ENABLE_PROCESSED_INPUT`.
- Enable `ENABLE_VIRTUAL_TERMINAL_INPUT` for escape sequence input.

### 2.2 Terminal Size

```odin
get_terminal_size :: proc() -> (cols, rows: int) {
    // Linux: ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws)
    // Windows: GetConsoleScreenBufferInfo
    // Fallback: write \x1b[9999;9999H then query cursor position
}
```

Register a `SIGWINCH` handler (Linux) that sets a `resize_pending` flag. Check flag at start of each render loop iteration. On Windows, poll `GetConsoleScreenBufferInfo` each frame.

### 2.3 ANSI Escape Codes Reference

These are the building blocks of your renderer. Know them all:

| Purpose | Escape Sequence |
|---|---|
| Clear screen | `\x1b[2J` |
| Clear line | `\x1b[2K` |
| Move cursor to row R, col C | `\x1b[{R};{C}H` (1-indexed) |
| Move cursor home | `\x1b[H` |
| Hide cursor | `\x1b[?25l` |
| Show cursor | `\x1b[?25h` |
| Save cursor position | `\x1b[s` |
| Restore cursor position | `\x1b[u` |
| Reset all attributes | `\x1b[0m` |
| Bold | `\x1b[1m` |
| Italic | `\x1b[3m` |
| Underline | `\x1b[4m` |
| Foreground color (256) | `\x1b[38;5;{n}m` |
| Background color (256) | `\x1b[48;5;{n}m` |
| Foreground color (RGB) | `\x1b[38;2;{r};{g};{b}m` |
| Background color (RGB) | `\x1b[48;2;{r};{g};{b}m` |
| Reverse video | `\x1b[7m` |
| Enable alternate screen | `\x1b[?1049h` |
| Disable alternate screen | `\x1b[?1049l` |
| Enable mouse tracking | `\x1b[?1000h\x1b[?1006h` |
| Disable mouse tracking | `\x1b[?1000l\x1b[?1006l` |
| Bracketed paste on | `\x1b[?2004h` |
| Bracketed paste off | `\x1b[?2004l` |

### 2.4 Output Buffering

**Never write to stdout byte by byte.** Accumulate all output for a frame into a `[dynamic]u8` buffer and flush it with a single `write` syscall at the end. This eliminates screen flicker.

```odin
Output_Buffer :: struct {
    data: [dynamic]u8,
}

ob_write :: proc(ob: ^Output_Buffer, s: string) {
    append(&ob.data, ..transmute([]u8)s)
}

ob_flush :: proc(ob: ^Output_Buffer) {
    os.write(os.stdout, ob.data[:])
    clear(&ob.data)
}
```

### 2.5 Alternate Screen Buffer

On startup: write `\x1b[?1049h` (enter alternate screen). On exit: write `\x1b[?1049l`. This means your editor never corrupts the user's scrollback history.

### 2.6 Signal Handling

Handle at minimum:
- `SIGWINCH` — terminal resize
- `SIGTERM`, `SIGINT` — clean exit (restore terminal before dying)
- `SIGPIPE` — ignore (relevant when piping output)

Always restore terminal state in a deferred call registered at startup so panics/crashes don't leave terminal broken.

---

## 3. Input Handling

### 3.1 Key Representation

```odin
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
    codepoint: rune,        // 0 if special
    special:   Special_Key,
    mods:      Key_Mods,
}
```

### 3.2 Escape Sequence Parser

Reading raw bytes from stdin is tricky because `\x1b` (ESC) can mean:
- A standalone Escape keypress
- The start of a multi-byte escape sequence (`\x1b[A` = Arrow Up)
- An Alt+key combination (`\x1bk` = Alt+k)

Parser algorithm:
1. Read one byte. If not `\x1b`, it's a regular UTF-8 char or Ctrl combo.
2. If `\x1b`: set a 50ms timeout, read next byte.
   - Timeout fires → standalone Escape.
   - Next byte is `[` or `O` → read VT sequence until terminator.
   - Next byte is printable → Alt+that_char.
3. Map VT sequences to `Special_Key` values via lookup table.

Complete VT sequence mapping to implement:

| Bytes | Key |
|---|---|
| `\x1b[A` | Arrow Up |
| `\x1b[B` | Arrow Down |
| `\x1b[C` | Arrow Right |
| `\x1b[D` | Arrow Left |
| `\x1b[H` or `\x1bOH` | Home |
| `\x1b[F` or `\x1bOF` | End |
| `\x1b[5~` | Page Up |
| `\x1b[6~` | Page Down |
| `\x1b[2~` | Insert |
| `\x1b[3~` | Delete |
| `\x1bOP` | F1 |
| `\x1bOQ` | F2 |
| `\x1bOR` | F3 |
| `\x1bOS` | F4 |
| `\x1b[15~` | F5 |
| `\x1b[17~` | F6 |
| `\x1b[18~` | F7 |
| `\x1b[19~` | F8 |
| `\x1b[20~` | F9 |
| `\x1b[21~` | F10 |
| `\x1b[23~` | F11 |
| `\x1b[24~` | F12 |
| `\x1b[1;2A` | Shift+Up |
| `\x1b[1;5A` | Ctrl+Up |
| `\x1b[1;3A` | Alt+Up |
| (etc. for all modifier+arrow combos) | |
| `\x00` | Ctrl+Space |
| `\x01`–`\x1a` | Ctrl+A through Ctrl+Z |

### 3.3 UTF-8 Input

Read enough bytes to complete a UTF-8 codepoint (1–4 bytes based on first byte). Never treat multi-byte chars as multiple keypresses.

### 3.4 Mouse Input

With `\x1b[?1000h\x1b[?1006h` (SGR mouse mode):
- Events arrive as `\x1b[<Cb;Cx;CyM` (press) and `\x1b[<Cb;Cx;CyrM` (release).
- Parse into: button (0=left, 1=middle, 2=right, 64=scroll-up, 65=scroll-down), col, row, pressed/released.
- Mouse events feed into the same dispatch as keyboard events.

### 3.5 Bracketed Paste

With `\x1b[?2004h`, pasted text is wrapped in `\x1b[200~` ... `\x1b[201~`. Treat the entire contents as a single Insert operation (not individual keypresses), enabling correct undo granularity for pastes.

---

## 4. Core Data Structures

### 4.1 The Piece Table

The piece table is the recommended buffer data structure. It supports O(1) insert/delete anywhere, cheap undo, and never moves original file data.

**Concept:**
- Two immutable buffers: `original` (file content on load, never modified) and `add` (all appended new content).
- A doubly-linked list of "pieces", each: `{source: Original|Add, start: int, length: int}`.
- The document is the concatenation of all pieces in order.

```odin
Piece_Source :: enum { Original, Add }

Piece :: struct {
    source: Piece_Source,
    start:  int,
    length: int,
    prev:   ^Piece,
    next:   ^Piece,
}

Piece_Table :: struct {
    original:    string,         // immutable, file content
    add_buffer:  [dynamic]u8,    // append-only
    head:        ^Piece,         // sentinel head
    tail:        ^Piece,         // sentinel tail
    piece_pool:  [dynamic]Piece, // arena for piece nodes
    char_count:  int,
    line_count:  int,
}
```

**Operations to implement:**

`pt_insert(pt, pos, text)`:
1. Find the piece containing `pos`. Split it into two pieces at `pos`.
2. Append `text` to `add_buffer`.
3. Insert a new piece pointing to the appended region, between the two split pieces.

`pt_delete(pt, pos, length)`:
1. Find pieces spanning `[pos, pos+length)`. Split at boundaries.
2. Remove all pieces entirely within the range; shrink boundary pieces.

`pt_char_at(pt, pos)` and `pt_substring(pt, pos, len)`:
- Walk piece list until cumulative length covers `pos`.
- Efficient iteration via a piece iterator that caches last-accessed piece.

**Line Index:**
- Maintain a separate `line_starts: [dynamic]int` array — absolute char offsets of each line start.
- Rebuild incrementally on edits (only lines after the edit point change).
- This gives O(1) line→offset and O(log n) offset→line (binary search).

### 4.2 Buffer

```odin
Buffer :: struct {
    id:           int,
    filepath:     string,           // "" if scratch
    name:         string,           // display name
    piece_table:  Piece_Table,
    undo_stack:   Undo_Stack,
    marks:        map[rune]Mark,
    registers:    // (shared via global register table)
    modified:     bool,
    readonly:     bool,
    filetype:     string,           // "odin", "c", "markdown", etc.
    encoding:     string,           // "utf-8", "latin-1"
    line_ending:  Line_Ending,      // LF, CRLF, CR
    tab_width:    int,
    expand_tabs:  bool,
    syntax:       ^Syntax_Definition,
    hl_cache:     Highlight_Cache,
    last_saved_undo_seq: int,       // for "modified" detection
}
```

### 4.3 Window

```odin
Window :: struct {
    id:           int,
    buffer:       ^Buffer,
    cursor:       Cursor,
    scroll_row:   int,   // first visible line (0-indexed)
    scroll_col:   int,   // first visible column
    top:          int,   // screen row of window top
    left:         int,   // screen col of window left
    width:        int,
    height:       int,   // excludes status line
    is_active:    bool,
}
```

### 4.4 Cursor

```odin
Cursor :: struct {
    row:          int,   // 0-indexed buffer line
    col:          int,   // 0-indexed byte offset in line (not screen col)
    preferred_col: int,  // "sticky" column for j/k motion
    visual_start: Maybe([2]int),  // [row, col] when in visual mode
}
```

### 4.5 Editor Global State

```odin
Editor :: struct {
    buffers:       [dynamic]^Buffer,
    windows:       [dynamic]^Window,
    tabs:          [dynamic]Tab,
    active_tab:    int,
    active_window: ^Window,
    mode:          Mode,
    prev_mode:     Mode,    // for returning from command mode
    command_buf:   [dynamic]u8,
    count_buf:     [dynamic]u8,  // numeric prefix accumulation
    pending_op:    Pending_Op,   // for operator-pending state (d, c, y...)
    registers:     Register_Table,
    macro_state:   Macro_State,
    search_state:  Search_State,
    config:        Config,
    keymap:        Keymap,
    autocmds:      Autocmd_Table,
    lsp_clients:   [dynamic]LSP_Client,
    output_buf:    Output_Buffer,
    term:          Termios_State,
    term_cols:     int,
    term_rows:     int,
    running:       bool,
    last_error:    string,
}
```

---

## 5. Buffer Management

### 5.1 Buffer Lifecycle

- `buffer_open(path) -> (^Buffer, error)` — read file, build piece table, detect filetype/encoding/line endings.
- `buffer_new_scratch() -> ^Buffer` — unnamed empty buffer.
- `buffer_close(buf)` — check `modified`, prompt if unsaved, free all memory.
- `buffer_save(buf, path) -> error` — serialize piece table to file, update `last_saved_undo_seq`.
- `buffer_reload(buf) -> error` — re-read from disk, preserving cursor position as best as possible.

### 5.2 Line Ending Detection & Handling

On open: scan first 8KB, tally `\r\n`, `\r`, `\n`. Pick the majority. Store as `buf.line_ending`.

On save: serialize using the detected (or configured) line ending. Never silently convert without user instruction.

Show line ending type in the status line: `[LF]`, `[CRLF]`, `[CR]`.

### 5.3 Encoding

Default UTF-8. On open: if BOM detected, strip it and record. If non-UTF-8 bytes found and filetype suggests latin-1, set `buf.encoding = "latin-1"`.

All internal processing in UTF-8. Column counts use grapheme cluster widths (handle CJK double-width, combining chars, zero-width joiners).

### 5.4 Large File Handling

Files > 10MB: disable syntax highlighting, disable undo history, show `[LARGE FILE]` in status. Still editable. The piece table handles large files natively.

---

## 6. Cursor & Motion Engine

### 6.1 Cursor Invariants

- `cursor.row` is always a valid line index: `0 <= row < line_count`.
- `cursor.col` in Normal mode: always `<= len(line) - 1` (can't be past last char, unless line is empty → 0).
- `cursor.col` in Insert mode: `<= len(line)` (can be past last char, on the newline position).
- After `j`/`k` vertical motion: `cursor.col = min(preferred_col, line_length - 1)`.
- `preferred_col` is updated on horizontal motion, preserved on vertical motion.

### 6.2 Text Objects

Text objects are the core power of modal editing. Each must work with operators `d`, `c`, `y`, `=`, `gU`, `gu`, etc.

Implement ALL of these:

| Key | Object |
|---|---|
| `aw` | A word (with surrounding whitespace) |
| `iw` | Inner word |
| `aW` | A WORD (whitespace-delimited) |
| `iW` | Inner WORD |
| `as` | A sentence |
| `is` | Inner sentence |
| `ap` | A paragraph |
| `ip` | Inner paragraph |
| `a(` or `ab` | A parenthesized block |
| `i(` or `ib` | Inner parenthesized block |
| `a[` | A bracket block |
| `i[` | Inner bracket block |
| `a{` or `aB` | A brace block |
| `i{` or `iB` | Inner brace block |
| `a<` | An angle bracket block |
| `i<` | Inner angle bracket block |
| `a"` | A double-quoted string |
| `i"` | Inner double-quoted string |
| `a'` | A single-quoted string |
| `i'` | Inner single-quoted string |
| `` a` `` | A backtick string |
| `` i` `` | Inner backtick string |
| `at` | An XML/HTML tag block |
| `it` | Inner tag block |

For each, the implementation must:
- Work with `a` (include delimiters/surrounding whitespace) and `i` (exclude them).
- Handle nested delimiters correctly (parentheses inside parentheses).
- Correctly handle the "seek" behavior: if cursor isn't inside the object, seek forward to the next occurrence.

### 6.3 Motions

Every standard motion must work standalone AND as the target of an operator.

**Word motions:**
- `w` — forward to start of next word
- `W` — forward to start of next WORD
- `b` — backward to start of word
- `B` — backward to start of WORD
- `e` — forward to end of word
- `E` — forward to end of WORD
- `ge` — backward to end of word
- `gE` — backward to end of WORD

Word: sequence of `[a-zA-Z0-9_]`. WORD: non-whitespace sequence.

**Character motions:**
- `h`, `l` — left/right
- `0` — start of line (col 0)
- `^` — first non-whitespace char of line
- `$` — end of line
- `g0` — start of screen line (for wrapped lines)
- `g^`, `g$` — screen line equivalents
- `|` — go to column N (`5|` = column 5)
- `f{char}`, `F{char}` — find char forward/backward on line
- `t{char}`, `T{char}` — till char (one before) forward/backward
- `;` — repeat last f/F/t/T
- `,` — repeat last f/F/t/T in opposite direction

**Line motions:**
- `j`, `k` — down/up line
- `gj`, `gk` — down/up screen line (visual wrap)
- `G` — last line
- `gg` — first line
- `{N}G` — go to line N
- `:{N}` — go to line N (via command mode)
- `H` — top of window (high)
- `M` — middle of window
- `L` — bottom of window (low)
- `+`, `-` — next/prev line, on first non-blank
- `{N}%` — go to N% of file

**Block motions:**
- `{` — beginning of paragraph (blank-line delimited)
- `}` — end of paragraph
- `[(`, `])` — go to unclosed `(` / next unmatched `)`
- `[{`, `]}` — go to unclosed `{` / next unmatched `}`
- `%` — matching bracket/delimiter

**Search motions:**
- `/{pattern}` — search forward
- `?{pattern}` — search backward
- `n` — repeat search
- `N` — repeat search in opposite direction
- `*` — search forward for word under cursor
- `#` — search backward for word under cursor
- `g*`, `g#` — like `*`/`#` but without word boundaries

**Jump motions:**
- `Ctrl-o` — jump to previous position in jumplist
- `Ctrl-i` / `Tab` — jump to next position in jumplist
- `''` / ` `` ` — jump to position before last jump
- `'{mark}` / `` `{mark} `` — jump to mark (line / exact position)

**Jumplist:** a circular buffer of up to 100 `(buffer_id, row, col)` entries. Updated on: `gg`, `G`, `/`, `?`, `n`, `N`, `%`, `H`, `M`, `L`, `Ctrl-o`, `Ctrl-i`, mark jumps, file open.

---

## 7. Viewport & Rendering Engine

### 7.1 Scroll Management

`scroll_row` / `scroll_col` track the top-left of the visible area per window.

Rules:
- After any cursor motion, call `scroll_into_view()`.
- `scrolloff` (default 5): always keep this many lines above/below cursor visible.
- `sidescrolloff` (default 5): same for horizontal.
- `scroll_into_view` adjusts `scroll_row` and `scroll_col` minimally to satisfy the constraints.

Explicit scroll commands:
- `Ctrl-e` / `Ctrl-y` — scroll down/up one line (cursor stays on screen)
- `Ctrl-d` / `Ctrl-u` — scroll half screen
- `Ctrl-f` / `Ctrl-b` — scroll full screen
- `zz` — center cursor line in window
- `zt` — cursor line to top
- `zb` — cursor line to bottom

### 7.2 Cell-Based Rendering

The terminal is a grid of cells. Represent your desired screen state as:

```odin
Cell :: struct {
    char: rune,
    fg:   Color,
    bg:   Color,
    bold: bool,
    italic: bool,
    underline: bool,
}

Screen :: struct {
    cells:   []Cell,   // [rows * cols]
    rows:    int,
    cols:    int,
}
```

Keep two screens: `current` (what's on screen) and `desired` (what we want). Each frame: build `desired`, diff against `current`, emit only the changed cells. This is screen diffing — it minimizes output bytes and eliminates flicker.

### 7.3 Rendering Pipeline

Each frame executes in this order:

1. `render_windows()` — for each window: render buffer content into desired screen region.
2. `render_statuslines()` — fill the status line row for each window.
3. `render_tabline()` — top line showing tabs (if more than one tab).
4. `render_commandbar()` — bottom line: command input, search prompt, messages.
5. `screen_diff_flush()` — emit ANSI codes for changed cells only.
6. `render_cursor()` — position terminal cursor (and set cursor shape).

### 7.4 Line Rendering

For each visible line:
1. Get the raw line text from the piece table.
2. Expand tabs to spaces (according to `tab_width`).
3. Apply syntax highlight spans (from highlight cache).
4. Apply search match highlights.
5. Apply visual selection highlight.
6. Apply LSP diagnostic underlines.
7. Clip to `[scroll_col, scroll_col + window.width)`.
8. Write to desired screen cells.

Handle double-width CJK characters: they occupy 2 cells. If a double-width char is split at the window edge, show a `~` or space in the last cell.

Line numbers: controlled by `number` and `relativenumber` config. Left-pad to width of `line_count` digits + 1 space.

`~` lines: rows below the last buffer line show a `~` in col 0 (like vim).

### 7.5 Cursor Shape

Change cursor shape per mode using ANSI sequences:
- Normal: block (`\x1b[1 q` or `\x1b[2 q`)
- Insert: beam (`\x1b[5 q` or `\x1b[6 q`)
- Visual: underline (`\x1b[3 q` or `\x1b[4 q`)

Restore original cursor shape on exit.

### 7.6 True Color vs 256 Color vs 16 Color

Detect via `COLORTERM` env var (`truecolor` or `24bit` → RGB), else `TERM` (`xterm-256color` → 256), else fall back to 16 colors. Colorscheme definitions provide values for all three tiers.

---

## 8. Mode System

### 8.1 Mode Enum

```odin
Mode :: enum {
    Normal,
    Insert,
    Replace,        // R — overwrite mode
    Visual_Char,    // v — char-wise visual
    Visual_Line,    // V — line-wise visual
    Visual_Block,   // Ctrl-v — block visual
    Operator_Pending, // waiting for motion after d/c/y/etc.
    Command,        // : command line
    Search_Forward, // / search prompt
    Search_Backward,// ? search prompt
    Insert_Completion, // completion popup active in insert
}
```

### 8.2 Mode Transitions

All valid transitions:

```
Normal → Insert         : i, a, I, A, o, O, s, S, c{motion}, C, R
Normal → Visual_Char    : v
Normal → Visual_Line    : V
Normal → Visual_Block   : Ctrl-v
Normal → Operator_Pending: d, c, y, g (various), =, <, >, !
Normal → Command        : :
Normal → Search_Forward : /
Normal → Search_Backward: ?

Insert → Normal         : Escape, Ctrl-c
Replace → Normal        : Escape
Visual_* → Normal       : Escape, v (if same mode), completing an operator
Visual_* → Insert       : I, A (block mode insert)
Operator_Pending → Normal: Escape, or after motion completes
Command → Normal/prev   : Enter (execute), Escape (cancel)
Search_* → Normal       : Enter (execute), Escape (cancel)
Insert_Completion → Insert: Escape, any non-completion key
```

### 8.3 Operator-Pending State

When the user types `d`, `c`, `y`, `=`, `gU`, `gu`, `~`, `<`, `>`, `!`, the editor enters Operator_Pending mode. It then waits for:
- A motion → apply operator over the region from cursor to motion end.
- A text object (`aw`, `iw`, etc.) → apply over the object.
- The same operator letter again → apply to current line (`dd`, `cc`, `yy`).
- `Escape` → cancel.

The pending operator is stored in `editor.pending_op`.

Operator list:

| Key | Operator |
|---|---|
| `d` | Delete |
| `c` | Change (delete + enter insert) |
| `y` | Yank (copy) |
| `=` | Auto-indent |
| `<` | Dedent |
| `>` | Indent |
| `!` | Filter through shell command |
| `gU` | Uppercase |
| `gu` | Lowercase |
| `g~` | Toggle case |
| `gq` | Format/wrap text |
| `gr` | Replace (virtual replace) |

---

## 9. Normal Mode — Complete Keybindings

### 9.1 Insertion Commands

| Key | Action |
|---|---|
| `i` | Insert before cursor |
| `a` | Insert after cursor |
| `I` | Insert at first non-blank of line |
| `A` | Insert at end of line |
| `o` | Open new line below, enter insert |
| `O` | Open new line above, enter insert |
| `s` | Delete char under cursor, enter insert |
| `S` | Delete line, enter insert (= `cc`) |
| `R` | Enter Replace mode |

### 9.2 Deletion Commands

| Key | Action |
|---|---|
| `x` | Delete char under cursor |
| `X` | Delete char before cursor |
| `d{motion}` | Delete over motion |
| `dd` | Delete current line |
| `D` | Delete to end of line (= `d$`) |
| `{N}d{motion}` | Delete N times |

### 9.3 Change Commands

| Key | Action |
|---|---|
| `c{motion}` | Delete motion region, enter insert |
| `cc` | Change current line |
| `C` | Change to end of line (= `c$`) |
| `r{char}` | Replace char under cursor with char |
| `R` | Enter Replace mode (overwrite) |
| `~` | Toggle case of char under cursor |
| `g~{motion}` | Toggle case over motion |
| `gU{motion}` | Uppercase over motion |
| `gu{motion}` | Lowercase over motion |

### 9.4 Yank/Paste Commands

| Key | Action |
|---|---|
| `y{motion}` | Yank motion region to unnamed register |
| `yy` or `Y` | Yank current line |
| `p` | Paste after cursor (char) / below (line) |
| `P` | Paste before cursor (char) / above (line) |
| `gp` | Like `p`, cursor after pasted text |
| `gP` | Like `P`, cursor after pasted text |
| `"{reg}y{motion}` | Yank to named register |
| `"{reg}p` | Paste from named register |

### 9.5 Indent / Format

| Key | Action |
|---|---|
| `>>` | Indent current line |
| `<<` | Dedent current line |
| `>{motion}` | Indent over motion |
| `<{motion}` | Dedent over motion |
| `={motion}` | Auto-indent over motion |
| `==` | Auto-indent current line |
| `gq{motion}` | Format (line-wrap) over motion |
| `gqq` | Format current line |

### 9.6 Window / Split Commands

| Key | Action |
|---|---|
| `Ctrl-w s` | Split horizontal |
| `Ctrl-w v` | Split vertical |
| `Ctrl-w w` | Focus next window |
| `Ctrl-w h/j/k/l` | Focus window left/down/up/right |
| `Ctrl-w H/J/K/L` | Move window left/down/up/right |
| `Ctrl-w =` | Equalize window sizes |
| `Ctrl-w _` | Maximize height |
| `Ctrl-w \|` | Maximize width |
| `Ctrl-w c` | Close window |
| `Ctrl-w o` | Close all other windows |
| `Ctrl-w +/-` | Resize height |
| `Ctrl-w </>` | Resize width |
| `Ctrl-w r` | Rotate windows |

### 9.7 Buffer Navigation

| Key | Action |
|---|---|
| `:bn` / `:bnext` | Next buffer |
| `:bp` / `:bprev` | Previous buffer |
| `:b{N}` | Switch to buffer N |
| `:b {name}` | Switch to buffer by name |
| `Ctrl-^` | Alternate buffer (last used) |

### 9.8 Miscellaneous Normal Commands

| Key | Action |
|---|---|
| `.` | Repeat last change |
| `u` | Undo |
| `Ctrl-r` | Redo |
| `J` | Join current line with next |
| `gJ` | Join without inserting space |
| `Ctrl-a` | Increment number under cursor |
| `Ctrl-x` | Decrement number under cursor |
| `g Ctrl-a` | Incrementally increment (in visual) |
| `gf` | Open file under cursor |
| `gd` | Go to definition (local) |
| `gD` | Go to definition (global) |
| `K` | Show documentation (hover) |
| `q{reg}` | Start recording macro to register |
| `q` | Stop recording macro |
| `@{reg}` | Execute macro in register |
| `@@` | Repeat last macro |
| `m{char}` | Set mark |
| `'{char}` | Jump to mark (line) |
| `` `{char} `` | Jump to mark (exact) |
| `Ctrl-g` | Show file info in status |
| `ga` | Show ASCII value of char under cursor |
| `g8` | Show UTF-8 bytes of char under cursor |
| `Ctrl-l` | Redraw screen |
| `ZZ` | Save and quit |
| `ZQ` | Quit without saving |

---

## 10. Insert Mode

### 10.1 Standard Insert Keys

| Key | Action |
|---|---|
| Any printable char | Insert at cursor |
| `Enter` | Insert newline |
| `Backspace` / `Ctrl-h` | Delete char before cursor |
| `Delete` | Delete char after cursor |
| `Ctrl-w` | Delete word before cursor |
| `Ctrl-u` | Delete all before cursor on line |
| `Ctrl-t` | Indent current line |
| `Ctrl-d` | Dedent current line |
| `Ctrl-j` or `Ctrl-m` | Insert newline (same as Enter) |
| `Escape` or `Ctrl-[` | Return to Normal mode |
| `Ctrl-c` | Return to Normal (no autocommand) |
| `Ctrl-o` | Execute one Normal mode command, return to Insert |
| `Ctrl-r{reg}` | Insert contents of register |
| `Ctrl-r Ctrl-r{reg}` | Insert literally (no special char processing) |
| `Ctrl-r =` | Insert result of expression |
| `Ctrl-a` | Insert previously inserted text |
| `Ctrl-n` | Trigger keyword completion (next) |
| `Ctrl-p` | Trigger keyword completion (prev) |
| `Ctrl-x Ctrl-n` | Complete with next match |
| `Ctrl-x Ctrl-p` | Complete with prev match |
| `Ctrl-x Ctrl-f` | Filename completion |
| `Ctrl-x Ctrl-l` | Line completion |
| `Ctrl-x Ctrl-o` | Omni-completion (LSP) |
| `Ctrl-k{digraph}` | Insert digraph |
| `Ctrl-v{code}` | Insert char by decimal/hex code |
| Arrow keys | Move cursor (stay in insert) |

### 10.2 Auto-Indent in Insert Mode

When `autoindent` is on: pressing Enter replicates the indentation of the current line.

When `smartindent` or `cindent` is on: increase indent after `{`, decrease after `}`, etc.

When `expandtab` is on: Tab inserts `tabstop` spaces.

When `smarttab` is on: Tab at line start inserts shiftwidth spaces, elsewhere inserts tabstop.

### 10.3 Auto-Pairs (Optional but Expected)

When typing `(`, `[`, `{`, `"`, `'`, `` ` ``: auto-insert the closing pair. Skip auto-close if next char is already the closing pair. On Backspace when cursor is between empty pair: delete both.

Make this configurable and per-filetype.

### 10.4 Replace Mode

Like Insert but each typed character overwrites the character under cursor instead of inserting. Backspace restores the original overwritten character (stored in undo history).

---

## 11. Visual Mode

### 11.1 Three Visual Modes

- **Visual char** (`v`): select character regions. Motion extends the selection endpoint.
- **Visual line** (`V`): always selects whole lines. Motion extends by lines.
- **Visual block** (`Ctrl-v`): selects a rectangular block. Operates on each line independently.

### 11.2 Selection Model

Selection is defined by `cursor.visual_start` (set on entering visual) and current cursor position. The region is always from the earlier to the later position, regardless of direction.

### 11.3 Visual Mode Keys

All Normal mode motions work in Visual mode (they extend the selection). Additionally:

| Key | Action |
|---|---|
| `o` | Move cursor to other end of selection |
| `O` | Move cursor to other corner (block mode) |
| `d` or `x` | Delete selection |
| `c` | Delete selection, enter Insert |
| `y` | Yank selection |
| `r{char}` | Replace all chars in selection with char |
| `>` | Indent selection |
| `<` | Dedent selection |
| `=` | Auto-indent selection |
| `gU` | Uppercase selection |
| `gu` | Lowercase selection |
| `g~` | Toggle case selection |
| `J` | Join selected lines |
| `!{cmd}` | Filter selection through shell |
| `gq` | Format selection |
| `p` / `P` | Replace selection with register content |
| `:` | Enter Command mode with `'<,'>` range pre-filled |
| `Ctrl-v` | Switch to Visual block (from char/line) |
| `V` | Switch to Visual line (from char/block) |
| `v` | Switch to Visual char (from line/block) |

### 11.4 Visual Block Special Operations

- `I{text}Escape` — insert text before each line in the block column.
- `A{text}Escape` — append text after each line in the block column.
- `c{text}Escape` — change each line in block.
- `d` / `x` — delete the block column from each line.
- `r{char}` — replace every char in block with char.
- `>` / `<` — indent/dedent all selected lines.

---

## 12. Command Mode

### 12.1 Command Bar

`:` enters command mode. A command line appears at the bottom. Features:
- Full editing: left/right arrows, Home/End, Backspace, Ctrl-w (delete word), Ctrl-u (clear).
- History: Up/Down arrow navigates command history (persistent across sessions).
- Tab completion: complete command names, filenames, buffer names, options.
- Escape: cancel and return to Normal mode.

### 12.2 Address/Range Syntax

Commands can be prefixed with a range:

| Syntax | Meaning |
|---|---|
| `{N}` | Line N |
| `.` | Current line |
| `$` | Last line |
| `%` | Entire file (= `1,$`) |
| `'x` | Mark x |
| `'<` , `'>` | Start/end of last visual selection |
| `/pattern/` | Next match of pattern |
| `?pattern?` | Previous match |
| `{addr}+{N}` | N lines after addr |
| `{addr}-{N}` | N lines before addr |
| `{addr1},{addr2}` | Range from addr1 to addr2 |

### 12.3 Built-in Ex Commands

Implement all of these:

**File commands:**
- `:e[dit] {file}` — open file
- `:w[rite] [file]` — save
- `:wa` — save all
- `:wq` — save and quit
- `:x` — save and quit (only writes if modified)
- `:q[uit]` — quit
- `:q!` — quit without saving
- `:qa` — quit all
- `:qa!` — quit all without saving
- `:r[ead] {file}` — insert file contents below cursor
- `:r !{cmd}` — insert command output below cursor

**Edit commands:**
- `:[range]d[elete] [reg]` — delete range to register
- `:[range]y[ank] [reg]` — yank range to register
- `:[range]p[ut] [reg]` — paste register after range
- `:[range]co[py] {addr}` or `:[range]t {addr}` — copy range to addr
- `:[range]m[ove] {addr}` — move range to addr
- `:[range]j[oin]` — join lines in range
- `:[range]s[ubstitute]/{pat}/{rep}/{flags}` — search and replace
- `:[range]g[lobal]/{pat}/{cmd}` — execute cmd on lines matching pat
- `:[range]v[global]/{pat}/{cmd}` — execute cmd on lines NOT matching pat
- `:[range]norm[al] {cmds}` — execute Normal mode commands on each line in range
- `:[range]=` — print line numbers for range

**Buffer/window commands:**
- `:b[uffer] {N|name}` — switch buffer
- `:bn[ext]`, `:bp[rev]` — next/prev buffer
- `:bd[elete]` — delete (close) buffer
- `:ls` or `:buffers` — list buffers
- `:sp[lit] [file]` — horizontal split
- `:vsp[lit] [file]` — vertical split
- `:new`, `:vnew` — new empty split
- `:on[ly]` — close other windows
- `:tabnew [file]`, `:tabe[dit] [file]` — new tab
- `:tabc[lose]` — close tab
- `:tabn[ext]`, `:tabp[rev]` — next/prev tab

**Option commands:**
- `:set {option}` — enable boolean option
- `:set no{option}` — disable boolean option
- `:set {option}={value}` — set value option
- `:set {option}?` — query option value
- `:set all` — show all options

**Misc commands:**
- `:[range]!{cmd}` — filter range through shell command
- `:!{cmd}` — run shell command (suspend editor, show output, press key to return)
- `:sh[ell]` — open shell (suspend editor)
- `:cd {dir}` — change working directory
- `:map`, `:nmap`, `:imap`, `:vmap`, etc. — define keybindings
- `:unmap`, `:nunmap`, etc. — remove keybindings
- `:source {file}` — execute config file
- `:colorscheme {name}` — switch colorscheme
- `:syntax on/off` — toggle syntax highlighting
- `:help {topic}` — open help (see section 36)
- `:messages` — show message history
- `:nohlsearch` or `:noh` — clear search highlight
- `:registers` — show register contents
- `:marks` — show marks
- `:jumps` — show jumplist
- `:history` — show command history
- `:undolist` — show undo tree
- `:version` — show editor version/build info

### 12.4 Substitute Command

Full `:s` syntax: `:[range]s/{pattern}/{replacement}/{flags}`

Flags:
- `g` — replace all occurrences on each line (not just first)
- `i` — case-insensitive
- `I` — case-sensitive (override config)
- `c` — confirm each substitution
- `e` — don't error if no match
- `n` — count matches without replacing

Replacement special sequences:
- `&` — entire matched text
- `\1`–`\9` — capture groups
- `\u` — uppercase next char
- `\l` — lowercase next char
- `\U` — uppercase until `\E`
- `\L` — lowercase until `\E`
- `\E` — end case modification
- `\n` — newline
- `\\` — literal backslash

---

## 13. File I/O

### 13.1 File Reading

- Use `os.read_entire_file` for files under ~100MB.
- For large files: read in chunks, build piece table from chunks.
- Detect encoding before building piece table (check BOM, try UTF-8 decode, fall back).
- Normalize line endings on read into internal `\n` only representation.

### 13.2 File Writing

- Write to a temp file first (`{original}.tmp`), then `rename` (atomic on POSIX).
- Preserve original file permissions.
- Write correct line endings based on `buf.line_ending`.
- If `write_backup` config is on: copy original to `{file}~` before overwriting.
- Show bytes written in status line after save.

### 13.3 File Watching

Poll `stat()` on the open file's mtime every N seconds. If mtime has changed externally: show a warning in the command bar. `:e` to reload, or `:w` to overwrite.

### 13.4 Sudo Write

`:w !sudo tee %` should work via the shell filter mechanism.

---

## 14. Search & Replace

### 14.1 Search Engine

Implement a proper regex engine (or wrap libc's `regcomp`/`regexec` via Odin's `core:c` FFI). Must support:

- `.` — any char
- `*`, `+`, `?`, `{n,m}` — quantifiers
- `^`, `$` — anchors
- `[abc]`, `[^abc]`, `[a-z]` — character classes
- `\w`, `\W`, `\d`, `\D`, `\s`, `\S` — shorthand classes
- `\b` — word boundary
- `(...)` — grouping and capture
- `|` — alternation
- `\1`–`\9` — backreferences
- `(?i)` — inline flags
- `\<`, `\>` — vim-style word boundaries (used by `*`, `#`)

Case sensitivity: respect `ignorecase` and `smartcase` settings. `smartcase`: if pattern contains any uppercase, force case-sensitive.

### 14.2 Search State

```odin
Search_State :: struct {
    pattern:      string,
    direction:    enum { Forward, Backward },
    matches:      [dynamic]Match,   // all matches in visible range (for highlighting)
    current:      int,              // index of current match
    highlight_on: bool,
}
```

After search: all matches in the file are found lazily (on-demand per visible line for highlighting; full scan for `n`/`N` navigation).

Show match count `[N/M]` in status line while searching.

### 14.3 Search Highlight

Draw all match spans with `search_highlight` color. Draw current match with `search_current` color (different). Clear on `:noh` or after a period of no search activity (configurable with `hlsearch_timeout`).

### 14.4 Incremental Search

As the user types the search pattern (before pressing Enter): update highlights in real time. If no match found: flash the command bar (briefly show error color).

### 14.5 Global Command

`:g/{pat}/{cmd}` — collect all lines matching pat, execute cmd on each. The command can itself be another `:g`, `:d`, `:s`, `:normal`, etc.

`:v/{pat}/{cmd}` (or `:g!`) — same but on non-matching lines.

---

## 15. Undo / Redo System

### 15.1 Undo History Requirements

- Unlimited undo depth (bounded only by memory).
- Undo granularity: each "change" is one undoable unit. A change is: a single Normal mode edit command, or all text typed during one Insert mode session (from entering Insert to leaving Insert).
- Redo is invalidated when a new change is made after undoing (standard linear model).

### 15.2 Undo Record

```odin
Undo_Record :: struct {
    kind:     enum { Insert, Delete, Compound },
    pos:      int,    // absolute char position
    text:     string, // inserted or deleted text
    cursor_before: [2]int,  // [row, col]
    cursor_after:  [2]int,
    seq:      int,    // monotonic sequence number
}

Undo_Stack :: struct {
    records:   [dynamic]Undo_Record,
    head:      int,    // points to next slot (after last undo point)
    save_seq:  int,    // seq at last save (for modified detection)
}
```

### 15.3 Undo Tree (Advanced)

Vim uses an undo *tree*, not a stack, meaning undoing and making a new change creates a branch, and `:undolist` / `g-` / `g+` can navigate branches. Implement this after the linear undo is solid.

Branches are stored as a tree of `Undo_Record` nodes. `u` / `Ctrl-r` traverse the main branch. `g-` / `g+` navigate by time across all branches.

### 15.4 Persistent Undo

Optionally persist undo history to `~/.editor/undo/{hash_of_filepath}`. Load on file open. This means you can close and reopen a file and still undo old changes.

---

## 16. Registers & Clipboard

### 16.1 Register Types

| Name | Key | Behavior |
|---|---|---|
| Unnamed | `"` | Default for d/c/y/p. Always updated on any change. |
| Numbered | `"0`–`"9` | `"0` = last yank. `"1`–`"9` = deletion history (shift on each delete). |
| Named | `"a`–`"z` | Explicitly addressed. Lowercase = replace. Uppercase = append. |
| Small delete | `"-` | Deletes less than one line go here. |
| Read-only: last search | `"/` | Current search pattern. |
| Read-only: last command | `":` | Last executed : command. |
| Read-only: current file | `"%` | Current buffer filename. |
| Read-only: alt file | `"#` | Alternate buffer filename. |
| Expression | `"=` | Prompts for an expression, evaluates it. |
| Selection | `"*` | System primary selection (X11 clipboard). |
| Clipboard | `"+` | System clipboard (Ctrl-C/V clipboard). |
| Black hole | `"_` | Discards everything written to it. Reading returns empty. |

### 16.2 System Clipboard Integration

Check for `xclip`, `xsel`, `wl-copy`/`wl-paste`, `pbcopy`/`pbpaste` (macOS) in PATH. Use whichever is available. Fall back to an in-process clipboard that only works within the editor session.

For `"+` register: on yank → pipe to clipboard tool. On paste → read from clipboard tool.

---

## 17. Marks

### 17.1 Mark Types

| Mark | Behavior |
|---|---|
| `a`–`z` | Local marks (per buffer). Jump with `'a` / `` `a ``. |
| `A`–`Z` | Global marks (across files). Jump opens the file if needed. |
| `0`–`9` | Last N file positions on exit (auto-saved to `~/.editor/marks`). |
| `` ` `` | Position before last jump |
| `'` | Line of position before last jump |
| `[` | Start of last change or yank |
| `]` | End of last change or yank |
| `<` | Start of last visual selection |
| `>` | End of last visual selection |
| `.` | Position of last change |
| `^` | Position of last insert |

### 17.2 Mark Persistence

On exit: save marks `a`–`z` for the N most recently used files in `~/.editor/marks`. Load on file open. This is part of "shada" (shared data) in vim parlance.

---

## 18. Macros

### 18.1 Recording

- `q{a-z}` — start recording into register `{a-z}`. Show `recording @{a}` in status line.
- Every keypress while recording is appended to the register as raw key bytes.
- `q` (when recording) — stop recording.

### 18.2 Playback

- `@{a-z}` — execute the macro in register `{a-z}`.
- `@@` — repeat the last executed macro.
- `{N}@{a}` — execute macro N times.
- If macro causes an error (e.g., motion fails), stop playback.

### 18.3 Recursive Macros

A macro can call itself (e.g., `@a` at the end of register `a`). Implement a recursion depth limit (default 100) to prevent infinite loops.

### 18.4 Editing Macros

`:let @a = "..."` — set register contents directly. This allows hand-editing a recorded macro.

---

## 19. Multiple Buffers & Buffer List

### 19.1 Buffer States

- **Active** — loaded in memory, currently displayed in a window.
- **Hidden** — loaded in memory, not displayed in any window.
- **Unloaded** — exists in the buffer list but not in memory (only filename stored).

### 19.2 Buffer List Display (`:ls`)

Format: `  {N} {flags} "{name}"  line {L}`

Flags:
- `%` — current buffer
- `#` — alternate buffer
- `a` — active (loaded, visible)
- `h` — hidden (loaded, not visible)
- `u` — unlisted (created by commands like `:r`)
- `-` — inactive (unloaded)
- `=` — readonly
- `+` — modified
- `x` — read error

---

## 20. Windows & Splits

### 20.1 Window Tree

Windows are arranged in a binary tree of splits:

```odin
Split_Dir :: enum { Horizontal, Vertical }

Window_Node :: union {
    ^Window,
    ^Split_Node,
}

Split_Node :: struct {
    dir:    Split_Dir,
    left:   Window_Node,
    right:  Window_Node,
    ratio:  f32,        // 0.0–1.0, left/top size fraction
}
```

### 20.2 Layout Engine

On terminal resize or manual resize: walk the tree, recompute `{top, left, width, height}` for each window node. Minimum window height: 2 (1 content row + 1 status line). Minimum width: 8.

### 20.3 Window Commands (detailed)

`:resize +N` / `:resize -N` — adjust current window height.
`:vertical resize +N` — adjust width.
`Ctrl-w {N}>` — increase width by N.
`Ctrl-w {N}<` — decrease width by N.
`Ctrl-w {N}+` — increase height by N.
`Ctrl-w {N}-` — decrease height by N.
`Ctrl-w =` — equalize all window sizes.
`Ctrl-w T` — move current window to new tab.

---

## 21. Tabs

### 21.1 Tab Model

Each tab has its own window tree. Switching tabs saves the current window layout and restores the target tab's layout.

```odin
Tab :: struct {
    id:          int,
    window_tree: Window_Node,
    active_win:  ^Window,
    name:        string,   // custom name, or derived from active buffer
}
```

### 21.2 Tab Line

When more than one tab exists, show a tab line at the top of the screen. Format: ` {N}: {name} ` for each tab, highlighted differently for active tab. Click (mouse) or `{N}gt` to switch.

### 21.3 Tab Commands

| Command | Action |
|---|---|
| `gt` / `Ctrl-PageDown` | Next tab |
| `gT` / `Ctrl-PageUp` | Previous tab |
| `{N}gt` | Go to tab N |
| `:tabnew` | New empty tab |
| `:tabe {file}` | Open file in new tab |
| `:tabc` | Close current tab |
| `:tabmove {N}` | Move tab to position N |
| `:tabonly` | Close all other tabs |

---

## 22. Status Line & Command Bar

### 22.1 Status Line Layout

Each window has a 1-row status line at its bottom. Active window has a distinct highlight color.

Left side: `{mode indicator} {filepath} {modified flag} {readonly flag} {filetype}`
Right side: `{percent through file} {line:col} {line ending} {encoding}`

Mode indicators: `-- NORMAL --`, `-- INSERT --`, `-- VISUAL --`, `-- VISUAL LINE --`, `-- VISUAL BLOCK --`, `-- REPLACE --`, `-- OPERATOR PENDING --`

Full implementation: status line is configurable via a format string (like vim's `statusline` option), supporting segments like `%f` (filepath), `%m` (modified), `%r` (readonly), `%y` (filetype), `%p` (percent), `%l` (line), `%c` (col), `%L` (total lines), `%{expr}` (expression), and highlight groups `%#GroupName#`.

### 22.2 Command Bar

The bottom-most line of the screen (not part of any window). Used for:
- `:` command input
- `/` and `?` search input
- Error and info messages
- Confirmation prompts (`Press ENTER or type command to continue`)
- `--More--` for long output

### 22.3 Messages

`editor_message(msg)` — show in command bar, expires after next keypress.
`editor_error(msg)` — show in red, stays until next keypress.
`editor_echo(msg)` — show persistently until explicitly cleared.

Message history: last 200 messages stored, viewable with `:messages`.

---

## 23. Syntax Highlighting

### 23.1 Architecture

A syntax definition maps regions of text to highlight groups. Highlight groups map to colors.

```odin
Highlight_Group :: struct {
    name: string,
    fg:   Color,
    bg:   Color,
    bold: bool,
    italic: bool,
    underline: bool,
    undercurl: bool,   // wavy underline (for errors)
    strikethrough: bool,
}

Span :: struct {
    start: int,   // byte offset in line
    end:   int,
    group: ^Highlight_Group,
}

Highlight_Cache :: struct {
    spans_per_line: [dynamic][dynamic]Span,
    dirty_from:     int,   // first dirty line
}
```

### 23.2 Regex-Based Highlighting

Each filetype definition is a list of rules, each rule: `{pattern: regex, group: string}`. Rules are tried in order; first match wins. This is similar to how vim's `syntax keyword`, `syntax match`, and `syntax region` work.

Rules types:
- **Keyword**: exact string match. Fast lookup via hash set.
- **Match**: single regex, single-line.
- **Region**: start pattern + end pattern (can span multiple lines). Optional `skip` pattern (e.g., for escaped quotes inside strings).

### 23.3 Multi-line Aware Highlighting

Use a state machine per line: each line has a "start state" (e.g., "inside block comment" or "inside multiline string"). Recompute from `dirty_from` on edits. Cache states per line.

### 23.4 Built-in Language Definitions

Implement syntax highlighting for at minimum:

- Odin
- C / C++
- Rust
- Go
- Python
- JavaScript / TypeScript
- Lua
- Shell (bash)
- Markdown
- JSON
- TOML
- YAML
- HTML / CSS
- SQL
- Diff / patch

Each definition: keywords, operators, string literals (single, double, multi-line), comments (line, block), numbers (int, float, hex), special constants, type names.

### 23.5 Colorschemes

A colorscheme maps highlight group names to colors. Ship at minimum:

- `default` — clean dark theme
- `light` — clean light theme
- `gruvbox` — warm earthy palette
- `catppuccin` — soft pastel dark
- `tokyonight` — blue/purple dark

Each colorscheme provides values for 16-color, 256-color, and truecolor terminals.

---

## 24. Configuration System

### 24.1 Config File Location

Load in order (later files override earlier):
1. Built-in defaults (hardcoded in `config.odin`)
2. `~/.config/editor/init.conf` (user config)
3. `.editor.conf` in current working directory (project-local config)

### 24.2 Config Syntax

Simple key = value format:

```
# Boolean options
number = true
relativenumber = false
expandtab = true
autoindent = true
smartcase = true
hlsearch = true
wrapscan = true
scrolloff = 5
sidescrolloff = 5

# Integer options
tabstop = 4
shiftwidth = 4
softtabstop = 4
history = 1000
undolevels = 10000
textwidth = 80
colorcolumn = 80

# String options
colorscheme = default
background = dark    # or "light"
shell = /bin/bash
clipboard = unnamedplus

# Filetype-specific overrides
[filetype:python]
tabstop = 4
expandtab = true

[filetype:go]
expandtab = false
tabstop = 4
```

### 24.3 Complete Option List

Implement all of these as real configurable options:

**Display:**
`number`, `relativenumber`, `cursorline`, `cursorcolumn`, `colorcolumn`, `signcolumn` (`no`/`yes`/`auto`), `wrap`, `linebreak`, `showbreak`, `scrolloff`, `sidescrolloff`, `laststatus` (0/1/2), `showtabline` (0/1/2), `showmode`, `showcmd`, `ruler`, `list`, `listchars`.

**Editing:**
`tabstop`, `shiftwidth`, `softtabstop`, `expandtab`, `smarttab`, `autoindent`, `smartindent`, `cindent`, `textwidth`, `wrapmargin`, `formatoptions`, `backspace`.

**Search:**
`hlsearch`, `incsearch`, `ignorecase`, `smartcase`, `wrapscan`.

**Files:**
`autoread`, `autowrite`, `backup`, `writebackup`, `backupdir`, `undofile`, `undodir`, `encoding`, `fileencoding`, `fileformat`.

**Behavior:**
`mouse` (`a`/`n`/`i`/`v`/``), `clipboard`, `history`, `undolevels`, `updatetime`, `timeoutlen`, `ttimeoutlen`, `shell`, `shellcmdflag`.

**Completion:**
`completeopt`, `pumheight`.

---

## 25. Keybinding Remapping

### 25.1 Map Commands

```
nmap {lhs} {rhs}     # Normal mode
imap {lhs} {rhs}     # Insert mode
vmap {lhs} {rhs}     # Visual mode
cmap {lhs} {rhs}     # Command mode
map {lhs} {rhs}      # All modes

nnoremap {lhs} {rhs} # Non-recursive normal
inoremap {lhs} {rhs} # Non-recursive insert
vnoremap {lhs} {rhs} # Non-recursive visual
...

nunmap {lhs}         # Remove mapping
```

### 25.2 Recursive vs Non-Recursive

`map` (recursive): the RHS is interpreted as keystrokes, which may themselves trigger further mappings.

`noremap` (non-recursive): the RHS is interpreted as built-in commands only.

Always prefer `noremap` internally. Recursive maps are supported for user configs but must detect and break cycles (max expansion depth: 200 steps).

### 25.3 Special Key Names in Maps

`<CR>`, `<Esc>`, `<Tab>`, `<Space>`, `<BS>`, `<Del>`, `<Up>`, `<Down>`, `<Left>`, `<Right>`, `<Home>`, `<End>`, `<PageUp>`, `<PageDown>`, `<F1>`–`<F12>`, `<C-a>` (Ctrl+a), `<M-a>` (Alt+a), `<S-a>` (Shift+a), `<C-S-a>`, `<leader>` (expands to `mapleader` option), `<localleader>`.

### 25.4 Leader Key

`mapleader` config option (default: `\`). `<leader>` in a mapping expands to this character. Common user config: `mapleader = ,` or `mapleader = Space`.

---

## 26. Autocommands & Hooks

### 26.1 Autocommand Events

An autocommand registers a command (or procedure) to run when a named event fires.

Implement these events:

| Event | When it fires |
|---|---|
| `BufNew` | New buffer created |
| `BufRead` | After reading a file into buffer |
| `BufWrite` | Before writing buffer to file |
| `BufWritePost` | After writing buffer to file |
| `BufEnter` | Entering a buffer (switching to it) |
| `BufLeave` | Leaving a buffer |
| `BufDelete` | Before deleting a buffer |
| `FileType` | Filetype detected/set |
| `InsertEnter` | Entering Insert mode |
| `InsertLeave` | Leaving Insert mode |
| `CursorMoved` | Cursor moved in Normal mode |
| `CursorMovedI` | Cursor moved in Insert mode |
| `VimEnter` | After editor fully initialized |
| `VimLeave` | Before editor exits |
| `WinEnter` | Entering a window |
| `WinLeave` | Leaving a window |
| `TabEnter` | Entering a tab |
| `TabLeave` | Leaving a tab |
| `ColorScheme` | After colorscheme changes |
| `OptionSet` | After option is changed |

### 26.2 Config Syntax

```
autocmd {Event} {pattern} {command}

# Examples:
autocmd FileType odin   set tabstop=4 expandtab=false
autocmd BufWrite *.md   %s/\s\+$//e       # trim trailing whitespace
autocmd BufRead  *.json set filetype=json
autocmd VimEnter *      colorscheme gruvbox

# Group (for easy clearing):
augroup MyGroup
  autocmd!   # clear group
  autocmd BufRead *.odin set filetype=odin
augroup END
```

---

## 27. File Explorer / Directory Browser

### 27.1 netrw-style Browser

When `:e {directory}` or `gf` on a directory is used: open the directory browser in the current window.

Display: sorted list of files/dirs in the directory. Directories shown with `/` suffix. Show hidden files optionally (toggle with `zh`).

Navigation:
- `j`/`k` — move selection
- `Enter` — open file (in current window) or enter subdirectory
- `-` — go up to parent directory
- `s` — change sort order (name/size/date)
- `r` — reverse sort
- `R` — rename file under cursor
- `D` — delete file under cursor (with confirmation)
- `%` — create new file
- `d` — create new directory
- `zh` — toggle hidden files
- `q` — close explorer

### 27.2 Sidebar Mode

`:Explore` opens the browser in the current window. `:Lexplore` opens a persistent sidebar (leftmost vertical split, 30 cols wide). Selecting a file in the sidebar opens it in the last used main window.

---

## 28. Fuzzy Finder

### 28.1 Overview

A fast fuzzy picker UI for: files in project, open buffers, command history, keybindings, colorschemes, and any custom list.

### 28.2 UI

Full-screen floating overlay (or bottom split):
- Top: text input with the query.
- Below: scrollable filtered list of candidates.
- Current item highlighted.
- Preview pane (optional, right half): shows file content for the selected candidate.

### 28.3 Fuzzy Matching Algorithm

Score each candidate against the query:
- All query chars must appear in the candidate in order (subsequence match).
- Score by: contiguous match bonus, start-of-word bonus, path separator bonus, consecutive char bonus.
- Sort descending by score.

This algorithm should handle `edt` matching `editor`, `bfm` matching `buffer_from_mark`, etc.

### 28.4 File Finder

Index project files: walk the current working directory tree, respecting `.gitignore`. For repos with >10k files, do this in a background thread. Cache the file list until the directory changes.

Keybinding: `<leader>f` (default, configurable).

### 28.5 Buffer Finder

List all open buffers. Keybinding: `<leader>b`.

### 28.6 Live Grep

`:Grep {pattern}` or `<leader>g` — run `rg` or `ag` or `grep -r` in background, stream results into the fuzzy picker. Selecting a result jumps to that file+line.

---

## 29. Completion Engine

### 29.1 Completion Sources

The completion engine collects candidates from multiple sources and ranks them:

- **Buffer keywords**: all words in all open buffers. Fast trie-based lookup.
- **Filename**: complete filesystem paths when typing after `/` or `~/`.
- **Line completion**: complete entire lines from buffer content.
- **LSP completion**: results from the LSP `textDocument/completion` request.
- **Snippet expansion**: expand short triggers to code templates.

### 29.2 Completion Menu UI

Displayed as a floating popup list below the cursor in Insert mode. Each item: `{icon} {label}  {kind}  {source}`. Kind icons: variable, function, class, keyword, snippet, file, etc.

Navigation: `Ctrl-n` / `Ctrl-p` (or Down/Up) — move selection. `Enter` or `Tab` — accept. `Escape` — dismiss.

### 29.3 Trigger Behavior

Auto-trigger: after typing N characters (configurable, default 2) or any trigger character (LSP-provided, e.g., `.`, `:`). Manual trigger: `Ctrl-Space`.

### 29.4 Snippet Engine

A snippet: a template with tabstop placeholders. Example (Odin procedure):

```
proc $1 :: proc($2) -> $3 {
    $0
}
```

`Tab` moves to the next tabstop. `Shift-Tab` moves to the previous. `$0` is the final cursor position. Support `${1:default_text}` for placeholders with defaults.

Snippets defined in `~/.config/editor/snippets/{filetype}.snip`.

---

## 30. LSP Client

### 30.1 Protocol Overview

The Language Server Protocol uses JSON-RPC over stdin/stdout. Your editor spawns a language server process (e.g., `clangd`, `rust-analyzer`, `pyright`) and communicates via JSON-RPC messages.

Message format:
```
Content-Length: {bytes}\r\n
\r\n
{json body}
```

### 30.2 LSP Client Architecture

```odin
LSP_Client :: struct {
    server_pid:    int,
    stdin_fd:      int,
    stdout_fd:     int,
    stderr_fd:     int,
    next_id:       int,
    pending:       map[int]LSP_Request,  // id → callback
    capabilities:  LSP_Server_Capabilities,
    filetype:      string,
    initialized:   bool,
    reader_thread: ^Thread,
}
```

Run a background reader thread that reads from the server's stdout and dispatches responses/notifications into a channel read by the main thread (on each editor tick).

### 30.3 LSP Requests to Implement

| Request | Trigger |
|---|---|
| `initialize` | On LSP start |
| `initialized` | After initialize response |
| `textDocument/didOpen` | When buffer is opened |
| `textDocument/didChange` | On each buffer change (incremental) |
| `textDocument/didSave` | On `:w` |
| `textDocument/didClose` | On buffer close |
| `textDocument/completion` | `Ctrl-Space` or auto-trigger |
| `textDocument/hover` | `K` in Normal mode |
| `textDocument/definition` | `gd` |
| `textDocument/declaration` | `gD` |
| `textDocument/typeDefinition` | `gy` |
| `textDocument/implementation` | `gi` |
| `textDocument/references` | `gr` |
| `textDocument/documentSymbol` | `<leader>s` |
| `textDocument/formatting` | `<leader>=` or `:Format` |
| `textDocument/rangeFormatting` | Format in visual mode |
| `textDocument/codeAction` | `<leader>ca` |
| `textDocument/rename` | `<leader>rn` |
| `textDocument/signatureHelp` | After `(` in Insert mode |
| `textDocument/inlayHint` | Background, rendered inline |
| `workspace/symbol` | `<leader>S` |

### 30.4 LSP Configuration

```
[lsp:odin]
command = ols
args =

[lsp:c]
command = clangd
args = --background-index --clang-tidy

[lsp:python]
command = pyright-langserver
args = --stdio
```

Auto-detect LSP servers installed in PATH for common languages. Allow per-project override via `.editor.conf`.

### 30.5 Inlay Hints

Render type annotations, parameter names, etc. as virtual text inline at the relevant positions (in a dimmed color). Toggle with `:InlayHintsToggle`.

---

## 31. Diagnostics & Inline Errors

### 31.1 Diagnostic Sources

- LSP `textDocument/publishDiagnostics` notifications.
- Compiler output parsed from `:make` or `:compiler` output.

### 31.2 Diagnostic Storage

```odin
Diagnostic_Severity :: enum { Error, Warning, Info, Hint }

Diagnostic :: struct {
    filepath: string,
    line:     int,
    col:      int,
    end_line: int,
    end_col:  int,
    severity: Diagnostic_Severity,
    message:  string,
    source:   string,   // "clangd", "make", etc.
    code:     string,
}
```

### 31.3 Display

**Underline**: draw undercurl (or underline, depending on terminal capability) under the diagnostic range. Color by severity (error=red, warning=yellow, info=blue, hint=gray).

**Virtual text**: show diagnostic message at end of line in dimmed color. If multiple diagnostics on one line, show the highest severity one.

**Sign column**: show a symbol in the sign column (`E`, `W`, `I`, `H`) with severity color.

**Status line**: show count of errors/warnings for current buffer: `E:3 W:5`.

### 31.4 Diagnostic Navigation

- `]d` / `[d` — next/previous diagnostic in buffer
- `]e` / `[e` — next/previous error
- `]w` / `[w` — next/previous warning
- `:DiagnosticList` — open quickfix list with all diagnostics

### 31.5 Quickfix / Location List

`:copen` — open quickfix list window (editor-global).
`:lopen` — open location list window (per-window).
`:cn` / `:cp` — next/prev quickfix item.
`:ln` / `:lp` — next/prev location list item.
`]q` / `[q` — same as `:cn`/`:cp` via keybind.

Items show: `{filepath}:{line}:{col}: {message}`. Jumping to an item opens the file and positions cursor.

---

## 32. Git Integration

### 32.1 Gutter Signs

When inside a git repo: run `git diff HEAD {file}` in background (or use `libgit2` via FFI). Show signs in the sign column:

- `│` (green) — added line
- `│` (red, for deleted line above) — deleted
- `│` (blue/yellow) — modified line

Update on `BufWrite` and `BufEnter`.

### 32.2 Hunk Navigation & Operations

- `]h` / `[h` — next/previous hunk
- `:GitHunkStage` — stage current hunk
- `:GitHunkUnstage` — unstage current hunk
- `:GitHunkPreview` — open a split showing the diff for the current hunk
- `:GitHunkReset` — revert current hunk to HEAD

### 32.3 Blame

`:GitBlame` — open a side pane (or virtual text) showing `git blame` output for the current file. Each line shows: commit hash, author, date, summary. Click/select a line to show full commit info.

### 32.4 Status & Commit

`:GitStatus` — open a buffer showing `git status`. Keybindings within: `s` stage, `u` unstage, `=` toggle diff, `cc` open commit message buffer.

`:GitCommit` — open a commit message buffer. Saving (`:wq`) runs `git commit -F {file}`.

---

## 33. Plugin / Extension System

### 33.1 Design Goals

Plugins written in Odin, compiled to shared libraries (`.so` / `.dll`) loaded at startup. This avoids the complexity and performance cost of an embedded scripting language while still allowing extensibility.

Alternatively (simpler first pass): a Lua FFI via `luajit` (call `lua_newstate`, register editor API functions as C functions callable from Lua). This is the approach taken by Neovim.

### 33.2 Plugin API (Lua or Odin)

The plugin API must expose:

**Buffer API:**
- `get_lines(buf, start, end)` — get line range
- `set_lines(buf, start, end, lines)` — replace line range
- `get_cursor()` — `{row, col}`
- `set_cursor(row, col)`
- `get_option(name)` / `set_option(name, value)`
- `get_text(buf, start_row, start_col, end_row, end_col)` — get text region
- `buf_line_count(buf)` — number of lines

**Window API:**
- `get_current_win()` / `set_current_win(win)`
- `win_get_buf(win)` / `win_set_buf(win, buf)`
- `win_get_cursor(win)` / `win_set_cursor(win, pos)`
- `open_win(buf, config)` — open a floating window

**Editor API:**
- `command(cmd)` — execute an ex command
- `feedkeys(keys)` — inject keypresses
- `create_autocmd(event, pattern, callback)`
- `set_keymap(mode, lhs, rhs, opts)`
- `notify(msg, level)` — show message
- `schedule(fn)` — run fn on next main loop tick (safe from async)

**UI API:**
- `create_namespace()` — for virtual text / highlight namespaces
- `buf_set_extmark(buf, ns, row, col, opts)` — virtual text, highlights
- `buf_del_extmark(buf, ns, id)`
- `buf_get_extmarks(buf, ns, start, end)`
- `open_floating_win(buf, config)` — for completion popups, hover, etc.

### 33.3 Plugin Loading

Scan `~/.config/editor/plugins/` and `./plugins/` at startup. Each plugin: a directory containing a `plugin.conf` (name, version, entry point) and its source/binary.

Load order: core → user plugins (alphabetical). Plugins can declare dependencies on other plugins.

---

## 34. Performance & Correctness Hardening

### 34.1 Performance Targets

- Keystroke to screen update: < 8ms (well within 120fps perception threshold).
- File open (100K lines): < 200ms.
- Syntax highlight update after a single-char edit: < 2ms.
- Search across 100K-line file: < 50ms.
- LSP diagnostics publish (background): non-blocking, zero impact on keystroke latency.

### 34.2 Profiling

Instrument the main loop with a debug profiler (compile-time gated). Record: time to process input, time to build screen cells, time to diff and flush. Log stats to `~/.editor/perf.log` when `debug_perf = true`.

### 34.3 Threading Model

Main thread handles: input, rendering, mode transitions, all text operations.

Background threads (communicate via lock-free channels to main thread):
- LSP reader thread (one per LSP client)
- File watcher thread
- Fuzzy finder indexer thread
- Git diff thread

The main thread NEVER blocks on I/O. Background threads never touch editor state directly.

### 34.4 Correctness: Edge Cases to Explicitly Test

- Empty file (0 lines)
- File with 1 million lines
- Single line with 1 million characters
- File with mixed line endings
- File with embedded null bytes
- File with BOM
- Buffer with only blank lines
- Undo past start of history (should do nothing, not crash)
- Redo past end of history
- Macro that modifies the buffer being iterated by `:g`
- Visual block selection on lines of varying lengths
- Search with regex that can match empty string (infinite loop guard)
- LSP server that crashes mid-session
- Resize terminal to 1 column, 1 row
- Extremely long lines in non-wrap mode
- Unicode: combining characters, ZWJ sequences, RTL text

---

## 35. Testing Infrastructure

### 35.1 Unit Tests

`odin test tests/` runs all `_test.odin` files. Test each module in isolation:

- `buffer_test.odin` — piece table insert/delete/query, line index correctness.
- `motion_test.odin` — all motion commands on known buffers.
- `undo_test.odin` — undo/redo sequences, including undo tree.
- `search_test.odin` — regex matching, search navigation, substitute.
- `input_test.odin` — escape sequence parser with byte sequence inputs.
- `command_test.odin` — ex command parser and executor.

### 35.2 Integration Tests

A headless mode (`--headless`): accept a script of keypresses on stdin, run the editor, write final buffer state to stdout. Compare against expected output files.

Example test:
```bash
echo -e ":e test_file.txt\niwHello World\x1b:wq\n" | ./editor --headless
diff test_file.txt expected_output.txt
```

Build a library of integration test cases covering common workflows: open file → edit → save, multi-buffer editing, visual mode operations, macro playback, search+replace.

### 35.3 Fuzz Testing

Use `odin fuzz` or a custom harness with libFuzzer:
- Fuzz the escape sequence parser with random byte sequences.
- Fuzz the piece table with random insert/delete operations.
- Fuzz the regex engine with random patterns and inputs.
- Fuzz the config file parser.

Goal: no crashes, no memory corruption, no infinite loops under any input.

---

## 36. Final Polish & Packaging

### 36.1 Built-in Help System

`:help {topic}` opens a readonly buffer with help text. Topics: every command, every option, every keybinding. Help text is compiled into the binary as string literals. Include a help index and cross-references.

### 36.2 Startup Performance

- Editor should be usable within 50ms of invocation for typical configs.
- LSP startup is async — editor is not blocked.
- File loading is the dominant cost; optimize for common case (< 10K lines).
- Profile and eliminate any startup allocations that scale with config complexity.

### 36.3 Man Page

Write a proper `editor.1` man page covering: synopsis, description, options (command-line flags), configuration, environment variables, files (config paths), exit codes, and examples.

### 36.4 Command-Line Flags

```
editor [options] [file ...]

-o {files}     Open files in horizontal splits
-O {files}     Open files in vertical splits
-p {files}     Open files in separate tabs
+{N}           Open first file at line N
+/{pattern}    Open first file at first match of pattern
-R             Read-only mode
-u {config}    Use specified config file (not ~/.config/editor/init.conf)
-u NONE        Skip config file
--headless     No UI (for scripting/testing)
--version      Print version and exit
--help         Print usage and exit
```

### 36.5 Exit Codes

- `0` — normal exit
- `1` — error (unwritten modified buffers, etc.)
- `2` — usage error (bad flags)

### 36.6 Distribution

- Single statically-linked binary. No runtime dependencies.
- Build targets: `linux-amd64`, `linux-arm64`, `macos-amd64`, `macos-arm64`, `windows-amd64`.
- Build script outputs to `dist/` with proper naming.
- Release checklist: run full test suite, fuzz for 1 hour, test on all target platforms, update changelog, tag version.

### 36.7 Version String

`:version` output:
```
editor v1.0.0 (built 2025-01-01)
Odin compiler: dev-2025-01
Target: linux/amd64
Config: ~/.config/editor/init.conf
Features: LSP, syntax, git, fuzzy
```

---

## DEPENDENCY ORDER SUMMARY

The sections above must be built roughly in this sequence (later items depend on earlier):

```
Terminal Layer
  └── Input Handling
        └── Core Data Structures
              └── Buffer Management
                    ├── Cursor & Motion Engine
                    └── Viewport & Rendering Engine
                          └── Mode System
                                ├── Normal Mode
                                ├── Insert Mode
                                ├── Visual Mode
                                └── Command Mode
                                      ├── File I/O
                                      ├── Search & Replace
                                      ├── Undo / Redo
                                      ├── Registers & Clipboard
                                      ├── Marks
                                      ├── Macros
                                      ├── Multiple Buffers
                                      ├── Windows & Splits
                                      ├── Tabs
                                      └── Status Line
                                            ├── Syntax Highlighting
                                            ├── Configuration System
                                            ├── Keybinding Remapping
                                            ├── Autocommands
                                            ├── File Explorer
                                            ├── Fuzzy Finder
                                            ├── Completion Engine
                                            └── LSP Client
                                                  ├── Diagnostics
                                                  ├── Git Integration
                                                  └── Plugin System
                                                        └── Performance Hardening
                                                              └── Testing
                                                                    └── Polish & Packaging
```

Each leaf is a shippable milestone. You can use the editor after "Status Line" and add everything else iteratively.
