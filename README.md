# WhiteWindow

WhiteWindow is a keyboard-driven mouse control utility for macOS. It allows you to click anywhere on the screen using a grid system or "nudge" the cursor with precision, all without touching the mouse.

## Installation

1.  **Clone the repository:**
    ```bash
    git clone <repository_url>
    cd withoutmouse
    ```

2.  **Build the application:**
    ```bash
    swift build -c release
    ```
    The binary will be created at `.build/release/WhiteWindow`.

3.  **Run:**
    ```bash
    .build/release/WhiteWindow
    ```

## Permissions

**Crucial Step:** This application requires **Accessibility Permissions** to simulate mouse clicks and monitor key events globally.

1.  When you first run the app, macOS should prompt you to grant accessibility access. Click "Open System Settings".
2.  If not prompted, go to **System Settings > Privacy & Security > Accessibility**.
3.  Add the terminal (e.g., Terminal, iTerm) or the `WhiteWindow` binary to the list and enable the toggle.
4.  If the app behaves erratically (e.g., ignores Escape key), remove it from the list and re-add it.

## Usage

The application runs in the background.

### 1. Grid Mode (Targeting)
**Trigger**: Press and **Release** `Command` (⌘) alone.

*   **Select**: Type the **two-letter code** (e.g., `AC`) shown in a grid cell.
*   **Drill Down**: Type a **third letter** (displayed in the mini-grid) to click a specific sub-area immediately.
*   **Click**: Press `Spacebar` to click the center of the selected cell (or the current cursor position if no cell is selected).
*   **Exit**: Press `Escape`.

### 2. Movement Mode (Nudging)
**Trigger**: Press and **Release** `Control` (⌃) alone.

*   **Move**:
    *   `J`: Left
    *   `K`: Down
    *   `L`: Up
    *   `;`: Right
    *   *Hold key for continuous movement.*
*   **Scroll**:
    *   `D`: Scroll Down
    *   `U`: Scroll Up
*   **Click & Drag**:
    *   **Drag**: Hold `Spacebar` + Move keys.
    *   **Drop/Click**: Release `Spacebar`.
*   **Visuals**: Screen border turns blue, background is transparent.
*   **Exit**: Press `Escape`.
