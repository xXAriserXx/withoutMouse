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

## Signing

`./install.sh` signs the installed app with a stable self-signed certificate named **WhiteWindow Dev**, and refuses to run without it. macOS ties the Accessibility permission to the signature: an ad-hoc signature changes on every build, so the permission would be dropped after each reinstall.

Create the certificate once:

1.  Open **Keychain Access** > **Keychain Access** menu > **Certificate Assistant** > **Create a Certificate…**
2.  Name: `WhiteWindow Dev`, Identity Type: **Self-Signed Root**, Certificate Type: **Code Signing**. Click **Create**.
3.  Check it is visible: `security find-identity -p codesigning | grep "WhiteWindow Dev"`

The first install signed with this certificate needs Accessibility granted once more (remove and re-add `~/Applications/WhiteWindow.app`). Later reinstalls keep it.

## Usage

The application runs in the background.

### 1. Grid Mode (Targeting)
**Trigger**: Press and **Release** left `Option` (⌥) alone.

*   **Select**: Type the **two-letter code** (e.g., `AC`) shown on a cell's badge. After the first letter, that row is highlighted and the others fade.
*   **Drill Down**: The selected cell is split into 15 sub-cells labelled `QWERT` / `ASDFG` / `ZXCVB` (the same layout as your keyboard), shown small on the cell and large in a magnified view next to it. Type the **third letter** to click that sub-cell immediately.
*   **Click**: Press `Spacebar` to click the center of the selected cell (or the current cursor position if nothing is typed yet).
*   **Right-click / double-click**: Hold `Shift` (right-click) or `Option` (double-click) on the key that clicks, either `Spacebar` or the third letter.
*   **Undo a letter**: `Backspace`.
*   **Exit**: Press `Escape`.

The magnified view needs **Screen Recording** permission (System Settings > Privacy & Security > Screen Recording). Without it, the view shows the sub-cell letters only.

### 2. Movement Mode (Nudging)
**Trigger**: Press and **Release** right `Command` (⌘) alone. Tap it again to close.

*   **Move**: `J` left, `K` down, `L` up, `;` right. Tap to nudge, hold to move continuously (it speeds up).
*   **Scroll**: `S` up, `D` down, `U` left, `O` right.
*   **Click**: Tap `F` to click, tap it twice quickly to double-click. Press `A` to right-click.
*   **Hide cursor**: Press `H` to hide the mouse cursor; press it again to show it. It stays hidden after you leave Movement Mode, even when you move the mouse or trackpad or switch app or Space.
*   **Drag**: Hold `F`, move with `J`/`K`/`L`/`;`, release `F` to drop.
*   **Jump**: Tap left `Option` to show the grid; type a code to move the cursor there and return to Movement Mode.
*   **Shortcuts**: Key combos with `Command`, `Control` or `Option` pass through to the app.
*   **Visuals**: Screen border turns blue, background is transparent.
*   **Exit**: Press `Escape` (or any other key).
