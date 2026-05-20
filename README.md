# kine — Odin Modal Text Editor

kine is a terminal-based modal text editor inspired by vim, written entirely in Odin. Phase 1 delivers a functional foundation: terminal control, a piece-table buffer, cursor motion, rendering, and normal/insert modes.

## Build

Requires [Odin dev-2026-05](https://odin-lang.org).

Check out the [OdinUP](https://github.com/prathmesh-barot/odinup). which is the native version manager for Odin, Ols and Odin fmt.

```bash
git clone <this-repo>
cd kine

# dev build with debug symbols and vet
./build.sh dev

# release build
./build.sh release

# build and run
./build.sh run [file]
```

Or directly:

```bash
odin build src/ -out:kine -debug
```

## Usage

```bash
./kine              # opens an empty scratch buffer
./kine main.c       # opens main.c
```

### Normal Mode (default)

| Key | Action |
|---|---|
| `h` `j` `k` `l` | Cursor movement |
| `w` `b` | Word forward/backward |
| `0` `^` `$` | Line start, first non-blank, line end |
| `gg` `G` | First line, last line |
| `i` | Enter insert mode before cursor |
| `a` | Enter insert mode after cursor |
| `I` | Insert at first non-blank |
| `A` | Insert at line end |
| `o` `O` | Open new line below/above |
| `x` | Delete character under cursor |
| `dd` | Delete current line |
| `D` | Delete to end of line |
| `yy` `Y` | Yank current line |
| `p` `P` | Paste below/above |
| `u` | Undo |
| `Ctrl-r` | Redo |
| `J` | Join lines |
| `r` | Replace character |
| `.` | Repeat last change |
| `zz` `zt` `zb` | Center/top/bottom cursor |
| `Ctrl-d` `Ctrl-u` | Scroll half screen |
| `Ctrl-f` `Ctrl-b` | Scroll full screen |
| `:`  | Enter command mode |
| `/` `?` | Search forward/backward |
| `v` `V` `Ctrl-v` | Visual modes |

### Insert Mode

| Key | Action |
|---|---|
| Any printable | Insert character |
| `Enter` | New line |
| `Backspace` | Delete before cursor |
| `Tab` | Insert tab |
| `Escape` | Return to normal mode |

### Command Mode

| Command | Action |
|---|---|
| `:q` | Quit |
| `:q!` | Force quit |
| `:w` | Save |
| `:wq` | Save and quit |
| `:e <file>` | Open file |
| `:bn` `:bp` | Next/previous buffer |
| `:b <name>` | Switch to buffer by name |
| `:ls` | List buffers |
| `:noh` | Clear search highlight |

## Project Structure

```
src/
├── main.odin        Entry point, event loop
├── editor.odin      Global editor state, init/shutdown
├── terminal.odin    Raw mode, ANSI, output buffering, signals
├── input.odin       Key press parsing, escape sequences
├── buffer.odin      Piece table, buffer operations, file I/O, undo
├── cursor.odin      Cursor movement and motion engine
├── viewport.odin    Scroll management
├── renderer.odin    Screen diffing, ANSI rendering
├── mode.odin        Mode enum
├── normal.odin      Normal mode dispatch
├── insert.odin      Insert mode dispatch
└── util.odin        Shared types and helpers
```

## What Phase 1 Delivers

- **Terminal layer**: raw mode, alternate screen, ANSI output buffering, signal handling, terminal resize detection
- **Input handling**: escape sequence parser (arrow keys, function keys, modified keys), UTF-8 input, Ctrl+key combos, Alt+key combos
- **Piece table**: O(1) insert/delete, immutable original + append-only add buffer, line index with O(log n) line lookup
- **Buffer management**: open files, scratch buffers, save (with line ending preservation), detect filetype
- **Cursor motion**: h/j/k/l, w/b, 0/^/$, gg/G, page up/down, scroll into view, preferred column
- **Rendering**: cell-based screen, diff-based output, line numbers, status line, command bar, cursor shape per mode
- **Modes**: Normal, Insert, Command, Visual (basic), up/down scroll
- **Undo/redo**: linear undo stack with proper granularity
- **Commands**: :q, :w, :wq, :e, :bn, :bp, :b, :ls, :noh

## License

MIT
