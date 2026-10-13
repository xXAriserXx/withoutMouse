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

`./install.sh` builds the release binary, packages it as `~/Applications/WhiteWindow.app`, and registers a LaunchAgent (`com.james.whitewindow`) so the app runs detached from any terminal, starts at login, and restarts on crash. Logs go to `~/Library/Logs/WhiteWindow.log`. `./install.sh uninstall` removes the installation.

### Updating without resetting Accessibility

- Do not run `./install.sh` for a routine source update. It replaces and ad-hoc re-signs the installed app bundle. On 2026-09-28 this caused macOS to reject WhiteWindow's existing Accessibility permission, and James had to remove and re-add the app in System Settings.
- The previously working development workflow is `swift build -c release`, then the `ww` zsh alias, which launches `.build/release/WhiteWindow` directly. This does not update the installed LaunchAgent; check which instance James intends to use before changing or starting processes.
- If the installed background app needs a new binary, first establish an update method that preserves its Accessibility permission. Do not overwrite or re-sign the installed app, or rerun the installer, without telling James if another permission grant may be required.

## Architecture

The entire app lives in `Sources/main.swift` (~1430 lines). There is no SwiftUI — it uses AppKit (NSWindow, NSView) with a CGEventTap for global keyboard interception.

### Key Components

- **`GridConfig`** — Shared grid geometry and code alphabets used by both the renderer and hit-testing. Codes follow QWERTY keyboard order (grid starts QQ QW QE … at top-left) so a code's keys are easy to locate.
- **`GridView` (NSView)** — Draws the overlay. Three modes: `.grid` (26×26 cell grid with two-letter codes), `.movement` (blue border, transparent), `.gridMove` (grid display but cursor-move instead of click).
- **`AppDelegate`** — All state and input handling. Manages modifier key detection (lone left Option / right Command tap triggers: `tapKey`, `handleGridTap`, `handleMovementTap`), input buffering, cursor movement with acceleration, click/drag/scroll simulation via CGEvents.
- **`eventTapCallback`** — C-compatible global callback. Intercepts keyDown/keyUp when the overlay is visible, routes to the appropriate mode handler, and swallows consumed keys (returns `nil`). Also receives flagsChanged and forwards it to `handleFlagsChanged` — modifiers go through the tap (not an NSEvent monitor) so they stay strictly ordered with keyDowns; otherwise Cmd+key shortcuts can trigger the grid after inactivity.

### Mode Activation

- **Grid Mode**: Release left Option (keyCode 58) alone within 1 second → shows grid overlay. Type 2-letter code to select cell, optional 3rd letter for mini-grid sub-position (labels QWERT/ASDFG/ZXCVB mirror the physical keyboard rows), Space to confirm click. Shift/Option on the confirming key (Space or 3rd letter) = right/double click (`ClickKind`). Backspace undoes a letter. Selecting a cell shows a zoom panel: a ScreenCaptureKit capture of the cell (`requestZoom`, needs Screen Recording permission, macOS 14+) drawn magnified by `GridView.drawZoomPanel`. The sub-cell letters are drawn both small on the cell and large on the panel (`drawSubLetters`).
- **Movement Mode**: Release right Command (keyCode 54) alone → shows movement overlay; tapping it again closes it. JKL; for cursor movement, S/D scroll up/down, U/O scroll left/right, F for click/drag, A for right-click, H toggles cursor visibility (private CGS "SetsCursorInBackground" + CGDisplayHideCursor).
- **Grid Move Mode**: Tap left Option while in Movement Mode (tap again to go back) → grid overlay that moves cursor (no click) then returns to Movement Mode.
- **Grid Drag Mode** (`.gridDrag`): Release left Command (keyCode 55) alone → grid; first pick (same keys as Grid Mode, resolved by `pointFor(code:)`) sets `dragStart` and redraws the grid with an orange marker; the first pick also presses and holds the button (`beginHeldDrag`) and modified/non-letter keys pass through so Spaces can be switched mid-drag; the second pick runs `finishHeldDrag` (25 `leftMouseDragged` steps, mouse up). Backspace on an empty buffer, Escape or hiding releases the button (`cancelHeldDrag`). Drag events go through the serial `dragQueue`.

### Coordinate Systems

The code converts between three coordinate systems: NSView (top-left, flipped), Cocoa global (bottom-left), and Quartz/CGEvent (top-left from primary screen). Conversions happen in `processClick`, `processMove`, and `moveCursorRelative`.

### Key Code Reference

Movement keys use raw keyCodes (not characters): J=38, K=40, L=37, ;=41, S=1, D=2, U=32, O=31, F=3, A=0.

## Git Workflow

After making changes, always: `git pull --rebase`, commit, and push. If there are merge conflicts, stop and ask before resolving.
