# Bunny Organiser 🐰🥕

A notification-sized Mac app that keeps your design-school files tidy. Press **Organise!** and the Gengo bunny hops through
`~/Downloads`, `~/Desktop` and `~/Documents`, works out which project each new file belongs to (using the
`claude` CLI), and files it into a dated project template.

<img src="docs/screenshot.png" alt="Bunny Organiser banner" width="450">

## The folder template

```
~/2026/
  10_October/
    Project_Name/
      01_Research/
      02_Inspiration/
      03_Assets/      Images · Icons · Illustrations · Logos · Fonts · Templates
      04_Working_Files/  V01 · V02 · V03 · V04 · V05
      05_Exports/     JPG · PNG · PDF · SVG
      06_Mockups/
      07_Final/
      99_Archive/
```

- Files for an existing project go into that project's folder; a new project starts in the current month.
- Personal items go to `~/Personal`, installers to `~/Installers`, and anything unclear to `~/2026/_To_Review`.
- Files touched in the last 10 minutes are left alone, so half-finished downloads are never grabbed.
- Every move is logged to `~/2026/_move_log.tsv`. `undo_moves.sh` puts everything back.

## Using it

| | |
|---|---|
| **Organise!** | Sort everything that's waiting |
| **Option-click Organise** | Preview where files *would* go without moving anything |
| **Click the status after a run** | Open the organised folders in Finder |

The first time you press Organise, macOS asks for access to Downloads, Desktop and Documents. Click **Allow**.

From the terminal:

```bash
python3 organize.py --list      # what's waiting
python3 organize.py --dry-run   # plan only
python3 organize.py             # organise
```

## Build

Needs macOS 12+, the Xcode command-line tools (`swiftc`) and the [Claude Code CLI](https://claude.com/claude-code)
logged in at `~/.local/bin/claude`.

```bash
./build.sh   # builds ~/Applications/Bunny Organiser.app
```

The app expects the organiser at `~/2026/_organize_new.py`. Link it once:

```bash
mkdir -p ~/2026 && ln -sf "$PWD/organize.py" ~/2026/_organize_new.py
```

## Files

| File | What it is |
|---|---|
| `main.swift` | Native window (WKWebView) that runs the organiser and streams its output |
| `index.html` | The bunny UI, in Gengo's colours |
| `organize.py` | Finds new files, asks `claude -p` to classify them, moves them |
| `undo_moves.sh` | Reverses every logged move |
| `build.sh` | Compiles, adds the icon and Info.plist, ad-hoc signs |
