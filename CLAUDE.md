# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

WhiteWindow is a keyboard-driven mouse control utility for macOS. It overlays a transparent grid on the screen, letting users click or move the cursor by typing letter codes — no mouse needed. Requires macOS 13+ and Accessibility permissions.

## Build & Run

```bash
swift build              # Debug build
swift build -c release   # Release build → .build/release/WhiteWindow
.build/release/WhiteWindow
```

No tests, no linter, no dependencies — single-target Swift Package.

### Background install (LaunchAgent)

`./install.sh` builds the release binary, installs it to `~/Library/Application Support/WhiteWindow/`, and registers a LaunchAgent (`com.james.whitewindow`) so the app runs detached from any terminal, starts at login, and restarts on crash. Logs go to `~/Library/Logs/WhiteWindow.log`. Re-run the script after code changes to deploy them; `./install.sh uninstall` removes everything.

## Architecture

The entire app lives in `Sources/main.swift` (~1180 lines). There is no SwiftUI — it uses AppKit (NSWindow, NSView) with a CGEventTap for global keyboard interception.

### Key Components

- **`GridConfig`** — Shared grid geometry and code alphabets used by both the renderer and hit-testing. Codes follow QWERTY keyboard order (grid starts QQ QW QE … at top-left) so a code's keys are easy to locate.
- **`GridView` (NSView)** — Draws the overlay. Three modes: `.grid` (26×26 cell grid with two-letter codes), `.movement` (blue border, transparent), `.gridMove` (grid display but cursor-move instead of click).
- **`AppDelegate`** — All state and input handling. Manages modifier key detection (Command/Control press-and-release triggers), input buffering, cursor movement with acceleration, click/drag/scroll simulation via CGEvents.
- **`eventTapCallback`** — C-compatible global callback. Intercepts keyDown/keyUp when the overlay is visible, routes to the appropriate mode handler, and swallows consumed keys (returns `nil`). Also receives flagsChanged and forwards it to `handleFlagsChanged` — modifiers go through the tap (not an NSEvent monitor) so they stay strictly ordered with keyDowns; otherwise Cmd+key shortcuts can trigger the grid after inactivity.

### Mode Activation

- **Grid Mode**: Release Left Command (keyCode 55) alone within 1 second → shows grid overlay. Type 2-letter code to select cell, optional 3rd letter for mini-grid sub-position (labels QWERT/ASDFG/ZXCVB mirror the physical keyboard rows), Space to confirm click.
- **Movement Mode**: Release Control alone (short press <0.25s) → shows movement overlay. JKL; for cursor movement, S/D scroll up/down, U/O scroll left/right, F for click/drag, A for right-click.
- **Grid Move Mode**: Press Control again while in Movement Mode → grid overlay that moves cursor (no click) then returns to Movement Mode.

### Coordinate Systems

The code converts between three coordinate systems: NSView (top-left, flipped), Cocoa global (bottom-left), and Quartz/CGEvent (top-left from primary screen). Conversions happen in `processClick`, `processMove`, and `moveCursorRelative`.

### Key Code Reference

Movement keys use raw keyCodes (not characters): J=38, K=40, L=37, ;=41, S=1, D=2, U=32, O=31, F=3, A=0.

## Git Workflow

After making changes, always: `git pull --rebase`, commit, and push. If there are merge conflicts, stop and ask before resolving.
