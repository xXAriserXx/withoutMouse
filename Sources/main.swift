import Cocoa
import Carbon
import ScreenCaptureKit

let appVersion = "0.1.0"

// The zoom panel (magnified copy of the selected cell) is off unless the app
// is launched with --zoom. It needs Screen Recording permission.
let zoomEnabled = CommandLine.arguments.contains("--zoom")

// Shared grid geometry and code alphabets.
// The renderer (GridView) and the hit-testing (processClick/processMove)
// must use the same values or clicks land in the wrong cell.
enum GridConfig {
    // 15 rows x 30 cols: the screen is split in two 15x15 halves.
    static let rows = 15
    static let cols = 30
    static let halfCols = 15
    // Every code takes both hands (10-finger touch typing split):
    // - left half of the screen: left-hand row key, then right-hand column key
    // - right half: right-hand row key, then left-hand column key
    // So the first key's hand says which half, and no code is typed with one
    // hand (no DX, JK, ...). The optional 3rd key (mini grid) is the first
    // key's hand again, so a full code alternates L-R-L or R-L-R.
    // Each hand's 15 keys follow the physical keyboard (QWERTY reading order).
    static let leftKeys = Array("qwertasdfgzxcvb")
    static let rightKeys = Array("yuiophjkl;nm,./")
    // Keys captured while the grid is open (the rest are swallowed or passed on)
    static let validInputChars = String(leftKeys + rightKeys)

    // Shift (right click) on ; , . / reports the shifted symbol: map it back
    static func normalize(_ char: Character) -> Character {
        switch char {
        case ":": return ";"
        case "<": return ","
        case ">": return "."
        case "?": return "/"
        default: return char
        }
    }

    // Label of a cell
    static func code(row: Int, col: Int) -> String {
        col < halfCols
            ? String([leftKeys[row], rightKeys[col]])
            : String([rightKeys[row], leftKeys[col - halfCols]])
    }

    // Cell of a 2-key code (extra keys ignored), nil if it isn't a code
    static func cell(for code: String) -> (row: Int, col: Int)? {
        let chars = Array(code)
        guard chars.count >= 2 else { return nil }
        if let r = leftKeys.firstIndex(of: chars[0]), let c = rightKeys.firstIndex(of: chars[1]) {
            return (r, c)
        }
        if let r = rightKeys.firstIndex(of: chars[0]), let c = leftKeys.firstIndex(of: chars[1]) {
            return (r, c + halfCols)
        }
        return nil
    }

    // Mini-grid keys: the left hand's QWERT / ASDFG / ZXCVB in every cell,
    // so a sub-position always has the same letter on both halves
    static func miniKeys(for code: String) -> [Character] {
        leftKeys
    }

    // Whether a key can come next after `typed`: wrong-hand keys are ignored
    static func accepts(_ char: Character, after typed: String) -> Bool {
        switch typed.count {
        case 0: return leftKeys.contains(char) || rightKeys.contains(char)
        case 1: return leftKeys.contains(typed.first!) ? rightKeys.contains(char) : leftKeys.contains(char)
        case 2: return miniKeys(for: typed).contains(char)
        default: return false
        }
    }

    // Mini grid inside a selected cell (3 rows x 5 cols = 15 cells).
    // Labels mirror the physical keyboard rows (QWERT / ASDFG / ZXCVB) so
    // the key you press matches the sub-cell's position.
    static let miniRows = 3
    static let miniCols = 5

    // Magnification of the zoom panel shown next to the selected cell
    static let zoomFactor: CGFloat = 6
}

// What a grid click does. Chosen by the modifier held on the confirming key
// (Space or the 3rd letter): none = left click, Shift = right click,
// Option = double click.
enum ClickKind {
    case left, right, double

    init(flags: CGEventFlags) {
        if flags.contains(.maskShift) {
            self = .right
        } else if flags.contains(.maskAlternate) {
            self = .double
        } else {
            self = .left
        }
    }
}

// Custom View to draw the grid
class GridView: NSView {
    enum Mode {
        case grid
        case movement
        case gridMove  // Grid mode that moves cursor without clicking
        case gridDrag  // Two picks on the grid: drag from the first point to the second
    }

    // Drag mode: start point already picked (view coords), drawn as a marker
    var dragStartMarker: NSPoint? {
        didSet { needsDisplay = true }
    }
    
    var mode: Mode = .grid {
        didSet { needsDisplay = true }
    }
    
    override var isFlipped: Bool { return true }

    // Track selected code for highlighting (Grid Mode)
    var selectedCode: String? {
        didSet {
            if selectedCode != oldValue { zoomImage = nil }  // stale capture of the old cell
            needsDisplay = true
        }
    }

    // Screen capture of the selected cell, shown magnified in the zoom panel.
    // nil while capturing or without Screen Recording permission: the panel
    // then shows the sub-cell letters on a plain dark background.
    var zoomImage: CGImage? {
        didSet { needsDisplay = true }
    }

    // Letters typed so far. After the first (row) letter, labels outside
    // that row fade out so only the 15 candidate cells (in one half) stand out.
    var typedPrefix = "" {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        // No background dim: each label sits on its own dark badge,
        // so the screen underneath stays readable.

        switch mode {
        case .grid:
            drawGrid(dirtyRect)
        case .movement:
            drawMovementUI(dirtyRect)
        case .gridMove:
            drawGrid(dirtyRect)  // Same grid display, different behavior
        case .gridDrag:
            drawGrid(dirtyRect)
            drawDragUI()
        }
    }
    
    func drawMovementUI(_ dirtyRect: NSRect) {
        // Draw a blue border to distinguish - Minimalist as requested
        NSColor.systemBlue.withAlphaComponent(0.5).setStroke()
        let borderPath = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
        borderPath.lineWidth = 2
        borderPath.stroke()
    }

    func drawGrid(_ dirtyRect: NSRect) {
        let rows = GridConfig.rows
        let cols = GridConfig.cols
        let width = bounds.width
        let height = bounds.height
        let rowHeight = height / CGFloat(rows)
        let colWidth = width / CGFloat(cols)
        
        // Small Vimium-style badges instead of large text, so labels don't
        // compete with the content underneath. Centered: that's where clicks land.
        let badgeFontSize = max(12, min(rowHeight, colWidth) * 0.28)
        let badgeFont = NSFont.monospacedSystemFont(ofSize: badgeFontSize, weight: .semibold)
        let badgeAttrs: [NSAttributedString.Key: Any] = [
            .font: badgeFont,
            .foregroundColor: NSColor.white.withAlphaComponent(0.95)
        ]
        let badgeFill = NSColor.black.withAlphaComponent(0.7)
        let badgePadX: CGFloat = 3
        let badgePadY: CGFloat = 1
        let fadedAlpha: CGFloat = 0.12

        // Row letter typed so far (nil until the first keystroke)
        let typedRow = typedPrefix.first
        let halfWidth = colWidth * CGFloat(GridConfig.halfCols)
        if let typedRow = typedRow {
            // Highlight the candidate row, in the half the first key's hand picks
            let isLeft = GridConfig.leftKeys.contains(typedRow)
            let r = (isLeft ? GridConfig.leftKeys : GridConfig.rightKeys).firstIndex(of: typedRow) ?? 0
            let rowRect = NSRect(x: isLeft ? 0 : halfWidth, y: CGFloat(r) * rowHeight, width: halfWidth, height: rowHeight)
            NSColor.systemYellow.withAlphaComponent(0.12).setFill()
            rowRect.fill()
            NSColor.systemYellow.withAlphaComponent(0.6).setStroke()
            let rowPath = NSBezierPath(rect: rowRect)
            rowPath.lineWidth = 1.5
            rowPath.stroke()
        }

        var selectedCellRect: NSRect?

        // Draw Two-Letter Codes

        for r in 0..<rows {
            for c in 0..<cols {
                let x = CGFloat(c) * colWidth
                let y = CGFloat(r) * rowHeight
                let cellRect = NSRect(x: x, y: y, width: colWidth, height: rowHeight)

                // Code Generation
                let lowerCode = GridConfig.code(row: r, col: c)
                let firstChar = lowerCode.first!
                let code = lowerCode.uppercased()
                
                // Highlight if selected
                if let selected = selectedCode, selected.uppercased() == code {
                    // Small letters here mark where each key lands on the real
                    // screen; the zoom panel drawn after the loop shows them large.
                    selectedCellRect = cellRect
                    drawSubGridLines(in: cellRect, color: NSColor.systemGreen.withAlphaComponent(0.5), lineWidth: 0.5)
                    let miniFontSize = max(7, min(colWidth / CGFloat(GridConfig.miniCols), rowHeight / CGFloat(GridConfig.miniRows)) * 0.7)
                    drawSubLetters(in: cellRect, keys: GridConfig.miniKeys(for: lowerCode), font: NSFont.monospacedSystemFont(ofSize: miniFontSize, weight: .semibold), padX: 1, padY: 0)

                    // Cell outline drawn last so it sits on top of the sub-cell lines
                    NSColor.systemGreen.withAlphaComponent(0.9).setStroke()
                    let outline = NSBezierPath(rect: cellRect)
                    outline.lineWidth = 1.5
                    outline.stroke()
                    
                } else {
                    // Centered badge; faded when it can't match the typed row letter
                    let isCandidate = typedRow == nil || typedRow == firstChar
                    let context = NSGraphicsContext.current?.cgContext
                    context?.saveGState()
                    if !isCandidate { context?.setAlpha(fadedAlpha) }

                    let textSize = code.size(withAttributes: badgeAttrs)
                    let badgeWidth = textSize.width + badgePadX * 2
                    let badgeHeight = textSize.height + badgePadY * 2
                    let badgeRect = NSRect(
                        x: cellRect.midX - badgeWidth / 2,
                        y: cellRect.midY - badgeHeight / 2,
                        width: badgeWidth,
                        height: badgeHeight
                    )
                    badgeFill.setFill()
                    NSBezierPath(roundedRect: badgeRect, xRadius: 3, yRadius: 3).fill()
                    code.draw(at: NSPoint(x: badgeRect.minX + badgePadX, y: badgeRect.minY + badgePadY),
                              withAttributes: badgeAttrs)

                    context?.restoreGState()
                }
            }
        }
        
        // No grid lines: the badges already mark each cell,
        // and lines cut through the text underneath.

        // Drawn last so it sits above every badge
        if zoomEnabled, let cellRect = selectedCellRect {
            drawZoomPanel(for: cellRect)
        }
    }

    // Drag mode: which step we're on, and a marker on the start point once picked
    func drawDragUI() {
        if let start = dragStartMarker {
            let ring = NSRect(x: start.x - 9, y: start.y - 9, width: 18, height: 18)
            NSColor.systemOrange.withAlphaComponent(0.35).setFill()
            NSBezierPath(ovalIn: ring).fill()
            NSColor.systemOrange.setStroke()
            let path = NSBezierPath(ovalIn: ring)
            path.lineWidth = 2.5
            path.stroke()
        }
        let text = dragStartMarker == nil ? "Drag: pick the start" : "Drag: pick the destination"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attrs)
        let rect = NSRect(x: bounds.midX - size.width / 2 - 12, y: bounds.maxY - size.height - 40,
                          width: size.width + 24, height: size.height + 10)
        NSColor.systemOrange.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        text.draw(at: NSPoint(x: rect.minX + 12, y: rect.minY + 5), withAttributes: attrs)
    }

    func drawSubGridLines(in rect: NSRect, color: NSColor, lineWidth: CGFloat) {
        let miniWidth = rect.width / CGFloat(GridConfig.miniCols)
        let miniHeight = rect.height / CGFloat(GridConfig.miniRows)
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        for i in 1..<GridConfig.miniCols {
            let x = rect.minX + CGFloat(i) * miniWidth
            path.move(to: NSPoint(x: x, y: rect.minY))
            path.line(to: NSPoint(x: x, y: rect.maxY))
        }
        for i in 1..<GridConfig.miniRows {
            let y = rect.minY + CGFloat(i) * miniHeight
            path.move(to: NSPoint(x: rect.minX, y: y))
            path.line(to: NSPoint(x: rect.maxX, y: y))
        }
        color.setStroke()
        path.stroke()
    }

    // Mini-grid keys (QWERT/ASDFG/ZXCVB) centered in each sub-cell, on dark badges
    func drawSubLetters(in rect: NSRect, keys: [Character], font: NSFont, padX: CGFloat, padY: CGFloat) {
        let miniWidth = rect.width / CGFloat(GridConfig.miniCols)
        let miniHeight = rect.height / CGFloat(GridConfig.miniRows)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        for (index, char) in keys.enumerated() {
            let mr = index / GridConfig.miniCols
            let mc = index % GridConfig.miniCols
            let subRect = NSRect(x: rect.minX + CGFloat(mc) * miniWidth,
                                 y: rect.minY + CGFloat(mr) * miniHeight,
                                 width: miniWidth, height: miniHeight)
            let text = String(char).uppercased()
            let textSize = text.size(withAttributes: attrs)
            let badge = NSRect(x: subRect.midX - textSize.width / 2 - padX,
                               y: subRect.midY - textSize.height / 2 - padY,
                               width: textSize.width + padX * 2, height: textSize.height + padY * 2)
            NSColor.black.withAlphaComponent(0.55).setFill()
            NSBezierPath(roundedRect: badge, xRadius: min(3, padX), yRadius: min(3, padX)).fill()
            text.draw(at: NSPoint(x: badge.minX + padX, y: badge.minY + padY), withAttributes: attrs)
        }
    }

    // Magnified copy of the selected cell, placed beside it, with large
    // sub-cell letters on top so the 3rd keystroke can be aimed precisely.
    func drawZoomPanel(for cellRect: NSRect) {
        let gap: CGFloat = 10
        let size = NSSize(width: cellRect.width * GridConfig.zoomFactor,
                          height: cellRect.height * GridConfig.zoomFactor)

        // Right of the cell if it fits, else left; vertically centered, kept on screen
        var x = cellRect.maxX + gap
        if x + size.width > bounds.maxX { x = cellRect.minX - gap - size.width }
        var y = cellRect.midY - size.height / 2
        y = max(bounds.minY + gap, min(y, bounds.maxY - gap - size.height))
        let panel = NSRect(origin: NSPoint(x: x, y: y), size: size)

        // Background, then the captured image if we have one
        NSColor.black.withAlphaComponent(0.85).setFill()
        panel.fill()
        if let image = zoomImage {
            NSGraphicsContext.current?.imageInterpolation = .high
            NSImage(cgImage: image, size: cellRect.size)
                .draw(in: panel, from: .zero, operation: .sourceOver, fraction: 1,
                      respectFlipped: true, hints: nil)
        }

        drawSubGridLines(in: panel, color: NSColor.systemGreen.withAlphaComponent(0.6), lineWidth: 1)

        // Large sub-cell letters on dark badges
        let fontSize = max(12, min(panel.width / CGFloat(GridConfig.miniCols), panel.height / CGFloat(GridConfig.miniRows)) * 0.4)
        drawSubLetters(in: panel, keys: GridConfig.miniKeys(for: selectedCode ?? ""), font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold), padX: 4, padY: 1)

        NSColor.systemGreen.withAlphaComponent(0.9).setStroke()
        let outline = NSBezierPath(rect: panel)
        outline.lineWidth = 2
        outline.stroke()

        // Key hint under the panel (above it if there's no room)
        let hint: String
        switch mode {
        case .gridDrag: hint = "Space pick · ⌫ back"
        case .gridMove: hint = "Space move · ⌫ back"
        default: hint = "⌥ click · Space right-click · ⌥Space double-click · ⌫ back"
        }
        let hintAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.9)
        ]
        let hintSize = hint.size(withAttributes: hintAttrs)
        var hintY = panel.maxY + 4
        if hintY + hintSize.height + 2 > bounds.maxY { hintY = panel.minY - hintSize.height - 6 }
        let hintRect = NSRect(x: panel.minX, y: hintY, width: hintSize.width + 10, height: hintSize.height + 2)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: hintRect, xRadius: 3, yRadius: 3).fill()
        hint.draw(at: NSPoint(x: hintRect.minX + 5, y: hintRect.minY + 1), withAttributes: hintAttrs)
    }
}

// Application Delegate to manage lifecycle and events
// Private CoreGraphics calls. macOS only lets the frontmost app hide the
// cursor; the "SetsCursorInBackground" connection property lifts that for
// this background app (the same trick Cursorcerer uses).
typealias CGSConnectionID = UInt32
@_silgen_name("_CGSDefaultConnection") func _CGSDefaultConnection() -> CGSConnectionID
@_silgen_name("CGSSetConnectionProperty") func CGSSetConnectionProperty(_ cid: CGSConnectionID, _ targetCID: CGSConnectionID, _ key: CFString, _ value: CFTypeRef) -> CGError

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var eventTap: CFMachPort?

    var inputBuffer = ""
    // Trigger taps: left Option (58) alone -> grid, right Command (54) alone -> movement,
    // left Command (55) alone -> drag.
    var tapKey: Int?  // Trigger key currently held, if it went down with no other modifier
    var isTapPotential = false  // Cleared by any other key, click or modifier during the hold
    var tapPressTime: Date?
    // A release only fires after a short quiet period. Karabiner layers on these
    // keys (right Command + Q, left Option + J...) lift the modifier before sending
    // the remapped key, which otherwise looks exactly like a lone tap.
    var pendingTap: DispatchWorkItem?
    let tapSettleDelay: TimeInterval = 0.01
    // Karabiner also re-presses the modifier right after the remapped key, so the
    // final real release would look like a tap. Presses this close after another
    // key event come from a remap, not a finger.
    var lastKeyEventTime = Date.distantPast
    let remapPressWindow: TimeInterval = 0.05

    func cancelPendingTap() {
        pendingTap?.cancel()
        pendingTap = nil
    }
    
    // Mode Tracking
    var currentMode: GridView.Mode = .grid
    
    // Movement Parameters (pixels per 60 FPS frame)
    // Holding a direction key grows the speed exponentially: x1.07 per frame,
    // so it doubles about every 0.17s, then caps (about 3600px/s). The glide
    // starts at the speed of the press's step (see handleDirectionPress).
    var currentSpeed: CGFloat = 1.0
    let minSpeed: CGFloat = 1.0
    let maxSpeed: CGFloat = 60.0
    let speedGrowth: CGFloat = 1.07
    
    // Smooth Movement State
    var activeMovementKeys: Set<Int> = []
    var movementTimer: Timer?
    var lastClickTime: Date?  // Track last click for double-click detection
    let clickInterval: TimeInterval = 0.3  // Max time between clicks for double-click
    var dragStart: CGPoint?  // Drag mode: start point (Quartz coords) once the first pick is made
    var secureInputTimer: Timer?  // Hides the overlay if secure input turns on while it's shown
    var modeShownAt = Date.distantPast
    let movementIdleTimeout: TimeInterval = 3  // Movement Mode closes after this long with no key
    var isCursorHidden = false  // Toggled with H in Movement Mode
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Create the window (using standard rect initially, updated on show)
        let rect = NSRect(x: 0, y: 0, width: 800, height: 600)

        window = NSWindow(
            contentRect: rect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        // REQUIRED for transparency
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        // Changed to 1.0 so we can control opacity manually in draw()
        window.alphaValue = 1.0 
        
        window.level = .screenSaver  // Highest level to appear above popups and dialogs
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        
        // Set the content view to our GridView
        window.contentView = GridView(frame: rect)
        
        // Check for accessibility trust
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let isTrusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        if !isTrusted {
            print("WARNING: Accessibility permissions are NOT granted. The Escape key will NOT work.")
            print("Please check the system popup or go to System Settings > Privacy & Security > Accessibility.")
        }
        
        setupMonitors()

        // Switching Spaces leaves Movement Mode (and its jump grid). The drag
        // grid stays: it is meant to carry a held drag across Spaces.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self, self.window.isVisible,
                  self.currentMode == .movement || self.currentMode == .gridMove else { return }
            self.hideWindow()
        }

        // Screen Recording powers the zoom panel. Ask once; macOS only shows
        // the prompt the first time, and the grant applies after a restart.
        if zoomEnabled && !CGPreflightScreenCaptureAccess() {
            print("Screen Recording permission not granted: the zoom panel will show letters only.")
            CGRequestScreenCaptureAccess()
        }
        
        print("WhiteWindow v\(appVersion) started. Press Cmd to show, Esc to hide. Zoom panel: \(zoomEnabled ? "on" : "off (launch with --zoom)").") 
    }
    
    // Hide/show calls are counted by the system (the count can't go below 0).
    // Real mouse/trackpad movement can bring the cursor back, so while hidden a
    // listen-only tap re-hides it on every move: show+hide keeps the count at 1
    // whether or not the system reset it.
    var cursorMoveTap: CFMachPort?
    var cursorMoveSource: CFRunLoopSource?
    // Switching Space or app also brings the cursor back without any movement,
    // so re-hide on those notifications and on a short timer as a catch-all.
    var cursorRehideTimer: Timer?
    var cursorObservers: [NSObjectProtocol] = []

    func rehideCursor() {
        guard isCursorHidden else { return }
        CGDisplayShowCursor(CGMainDisplayID())
        CGDisplayHideCursor(CGMainDisplayID())
    }

    func toggleCursorHidden() {
        let display = CGMainDisplayID()
        if isCursorHidden {
            if let tap = cursorMoveTap { CGEvent.tapEnable(tap: tap, enable: false) }
            if let source = cursorMoveSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
            cursorMoveTap = nil
            cursorMoveSource = nil
            cursorRehideTimer?.invalidate()
            cursorRehideTimer = nil
            cursorObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
            cursorObservers = []
            CGDisplayShowCursor(display)
        } else {
            let cid = _CGSDefaultConnection()
            _ = CGSSetConnectionProperty(cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
            CGDisplayHideCursor(display)
            let mask = (1 << CGEventType.mouseMoved.rawValue) | (1 << CGEventType.leftMouseDragged.rawValue) | (1 << CGEventType.rightMouseDragged.rawValue) | (1 << CGEventType.otherMouseDragged.rawValue)
            if let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                           eventsOfInterest: CGEventMask(mask),
                                           callback: { _, type, event, _ in
                                               if type == .mouseMoved || type == .leftMouseDragged || type == .rightMouseDragged || type == .otherMouseDragged {
                                                   CGDisplayShowCursor(CGMainDisplayID())
                                                   CGDisplayHideCursor(CGMainDisplayID())
                                               }
                                               return Unmanaged.passUnretained(event)
                                           }, userInfo: nil) {
                let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
                CGEvent.tapEnable(tap: tap, enable: true)
                cursorMoveTap = tap
                cursorMoveSource = source
            }
            cursorRehideTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
                self?.rehideCursor()
            }
            let center = NSWorkspace.shared.notificationCenter
            for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
                cursorObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.rehideCursor()
                    // The system can show it again a moment after the switch.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self?.rehideCursor() }
                })
            }
        }
        isCursorHidden.toggle()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
    
    func setupMonitors() {
        // CGEventTap for Keys (Added keyUp for smooth movement).
        // Created FIRST: if this fails (no Accessibility permission), we must
        // NOT install the modifier-key monitor either — otherwise the overlay
        // can appear but nothing can intercept keys to dismiss it.
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.rightMouseDown.rawValue) | (1 << CGEventType.tapDisabledByTimeout.rawValue) | (1 << CGEventType.tapDisabledByUserInput.rawValue)

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: eventTapCallback,
            userInfo: nil
        ) else {
            print("CRITICAL ERROR: Failed to create event tap (missing Accessibility permission?).")
            print("Overlay triggers are disabled. Grant permission in System Settings > Privacy & Security > Accessibility, then restart the app.")
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        self.eventTap = eventTap
        print("Event tap successfully created.")
    }

    // Called synchronously from the event tap so modifier changes are processed
    // in the same ordered stream as keyDowns. A separate NSEvent global monitor
    // delivers with higher latency than the tap: after inactivity (App Nap) a
    // queued keyDown could be handled before the Cmd-down that preceded it,
    // making the shortcut invalidation a no-op and triggering the grid on
    // Cmd+key shortcuts.
    func handleFlagsChanged(keyCode: Int, flags: CGEventFlags) {
        // Caps Lock (.maskAlphaShift) is deliberately ignored: it's a lock state,
        // not a held key, and would otherwise disable the triggers while on.
        let held = flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
        let triggers: [Int: CGEventFlags] = [58: .maskAlternate, 54: .maskCommand, 55: .maskCommand]
        cancelPendingTap()
        let sinceLastKey = Date().timeIntervalSince(lastKeyEventTime)
        lastKeyEventTime = Date()

        guard let key = tapKey, let keyFlag = triggers[key] else {
            // Nothing pending: start one if a trigger key went down on its own
            if let flag = triggers[keyCode], held == flag,
               sinceLastKey > remapPressWindow {
                tapKey = keyCode
                isTapPotential = true
                tapPressTime = Date()
            }
            return
        }

        if keyCode == key && !held.contains(keyFlag) {
            // Trigger key released. Secure input (password fields) hides keyDowns
            // from the tap, so a shortcut there looks like a lone tap: don't fire.
            if isTapPotential && !IsSecureEventInputEnabled(),
               let pressTime = tapPressTime, Date().timeIntervalSince(pressTime) < 1.0 {
                let work = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    self.pendingTap = nil
                    switch key {
                    case 58: self.handleGridTap()
                    case 55: self.handleDragTap()
                    default: self.handleMovementTap()
                    }
                }
                pendingTap = work
                DispatchQueue.main.asyncAfter(deadline: .now() + tapSettleDelay, execute: work)
            }
            tapKey = nil
            isTapPotential = false
            tapPressTime = nil
        } else {
            // Another modifier joined (or the other side's twin): it's a shortcut
            isTapPotential = false
            if held.isEmpty { tapKey = nil }
        }
    }

    // Left Option tap: opens the grid; in the open grid and in Movement Mode
    // it left-clicks (two quick taps double-click). In the jump grid it goes
    // back to Movement Mode.
    func handleGridTap() {
        guard window.isVisible else { startGridMode(); return }
        switch currentMode {
        case .movement: performClick()
        case .gridMove: startMovementMode()
        case .grid:
            // Lone left Option is the click: on the selected cell, or at
            // the cursor if nothing is typed yet
            if inputBuffer.count == 1 { startGridMode() } else { handleConfirm(kind: .left) }
        case .gridDrag: startGridMode()
        }
    }

    // Left Command tap: opens the drag grid, or closes it if already open.
    func handleDragTap() {
        if window.isVisible && currentMode == .gridDrag {
            hideWindow()
        } else {
            cancelHeldDrag()
            showWindow(mode: .gridDrag)
        }
    }

    // Right Command tap: opens Movement Mode; tapped again there it opens the
    // jump grid (Grid Move), and in the jump grid it goes back. Esc (or any
    // unused key) closes Movement Mode.
    func handleMovementTap() {
        if window.isVisible && currentMode == .movement {
            startGridMoveMode()
        } else {
            startMovementMode()
        }
    }

    func startGridMode() {
        showWindow(mode: .grid)
    }
    
    func startMovementMode() {
        showWindow(mode: .movement)
    }
    
    func startGridMoveMode() {
        showWindow(mode: .gridMove)
    }
    
    func showWindow(mode: GridView.Mode) {
        guard let window = window else { return }
        
        currentMode = mode
        // Key releases are only tracked in movement mode, so a key held across
        // a mode switch would never be removed and the cursor would keep drifting.
        stopMovement()
        if let gridView = window.contentView as? GridView {
            gridView.mode = mode
            gridView.selectedCode = nil // Reset selection
            gridView.typedPrefix = ""
            gridView.dragStartMarker = nil
        }
        inputBuffer = "" // Reset buffer
        modeShownAt = Date()
        
        // Ensure window covers current screen
        let mouseLocation = NSEvent.mouseLocation
        var targetScreen = NSScreen.main
        for screen in NSScreen.screens {
            if NSMouseInRect(mouseLocation, screen.frame, false) {
                targetScreen = screen
                break
            }
        }
        if let screen = targetScreen {
            // For movement mode, use visibleFrame to not cover dock/menu bar
            // This allows dock and menu bar to trigger when cursor reaches edges
            let frameToUse = (mode == .movement) ? screen.visibleFrame : screen.frame
            window.setFrame(frameToUse, display: true)
        }
        
        window.orderFrontRegardless()
        startSecureInputWatch()
    }

    // Secure input (e.g. focusing a password field) hides keyDowns from the tap,
    // so Escape and mode keys would go to the app and the overlay couldn't be
    // dismissed. Poll while visible and close the overlay when it turns on.
    // The same poll closes Movement Mode after movementIdleTimeout with no key
    // event (lastKeyEventTime covers keys and modifier taps) and nothing gliding.
    func startSecureInputWatch() {
        guard secureInputTimer == nil else { return }
        secureInputTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if IsSecureEventInputEnabled() {
                print("Secure input enabled while overlay visible. Hiding.")
                self.hideWindow()
            } else if self.currentMode == .movement, self.activeMovementKeys.isEmpty, self.stepAnimations.isEmpty,
                      Date().timeIntervalSince(max(self.lastKeyEventTime, self.modeShownAt)) >= self.movementIdleTimeout {
                self.hideWindow()
            }
        }
    }
    
    func hideWindow() {
        guard let window = window else { return }
        secureInputTimer?.invalidate()
        secureInputTimer = nil
        if window.isVisible {
            window.orderOut(nil)
            inputBuffer = ""
            cancelHeldDrag()
            if let gridView = window.contentView as? GridView {
                gridView.selectedCode = nil
                gridView.typedPrefix = ""
            }
            // Stop movement
            stopMovement()
        }
    }
    
    func stopMovement() {
        movementTimer?.invalidate()
        movementTimer = nil
        activeMovementKeys.removeAll()
        stepAnimations.removeAll()
        currentSpeed = minSpeed // Reset speed
    }
    
    // Pressing a direction key glides a step right away (stepFrames frames,
    // no teleport); still holding when the step ends carries on at the same
    // speed into the accelerating glide. The step is 1/8 of the screen's
    // width/height. Homing: each axis remembers its own step; reversing on an
    // axis halves it (overshoot, come back half as far), the same direction
    // keeps it, and using the other axis in between leaves it alone. Both
    // reset once no direction key has been used for homingWindow.
    let stepFraction: CGFloat = 1.0 / 8
    let stepFrames: CGFloat = 5          // ~80ms at 60 FPS
    let minStep: CGFloat = 4
    let homingWindow: TimeInterval = 1.0
    var stepAnimations: [Int: (remaining: CGFloat, perFrame: CGFloat)] = [:]
    var axisSteps: [Bool: (keyCode: Int, size: CGFloat)] = [:]  // key: horizontal?
    var lastDirectionUse: Date?
    let directionVectors: [Int: (dx: CGFloat, dy: CGFloat)] = [
        38: (-1, 0),  // j -> left
        41: (1, 0),   // ; -> right
        40: (0, 1),   // k -> down
        37: (0, -1),  // l -> up
    ]

    func handleDirectionPress(keyCode: Int) {
        guard let vector = directionVectors[keyCode],
              let current = CGEvent(source: nil)?.location, let screen = cursorScreen(current) else { return }
        let horizontal = vector.dx != 0
        if let lastUse = lastDirectionUse, Date().timeIntervalSince(lastUse) >= homingWindow {
            axisSteps.removeAll()
        }
        var size = (horizontal ? screen.width : screen.height) * stepFraction
        if let last = axisSteps[horizontal] {
            size = last.keyCode == keyCode ? last.size : max(minStep, last.size / 2)
        }
        axisSteps[horizontal] = (keyCode, size)
        lastDirectionUse = Date()
        stepAnimations[keyCode] = (size, size / stepFrames)
        currentSpeed = min(max(size / stepFrames, minSpeed), maxSpeed)
    }

    // Shift + direction key: move a few pixels at once, for fine positioning
    let nudgeDistance: CGFloat = 10

    // It also arms homing on its axis: the next normal tap there within
    // homingWindow moves half the current step, in either direction.
    func nudge(keyCode: Int) {
        guard let vector = directionVectors[keyCode],
              let current = CGEvent(source: nil)?.location, let screen = cursorScreen(current) else { return }
        moveCursorRelative(dx: vector.dx * nudgeDistance, dy: vector.dy * nudgeDistance)
        let horizontal = vector.dx != 0
        if let lastUse = lastDirectionUse, Date().timeIntervalSince(lastUse) >= homingWindow {
            axisSteps.removeAll()
        }
        let size = axisSteps[horizontal]?.size ?? (horizontal ? screen.width : screen.height) * stepFraction
        axisSteps[horizontal] = (-1, size)  // -1 matches no key, so the next tap halves
        lastDirectionUse = Date()
    }

    // The homing window counts from the release, so a long glide doesn't use it up
    func handleDirectionRelease(keyCode: Int) {
        lastDirectionUse = Date()
    }

    // Screen under the cursor, in Quartz coordinates (top-left origin)
    func cursorScreen(_ current: CGPoint) -> CGRect? {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let screens = NSScreen.screens.map {
            CGRect(x: $0.frame.minX, y: primaryHeight - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height)
        }
        return screens.first(where: { $0.contains(current) }) ?? screens.first
    }

    // C: middle of the screen the cursor is on
    func centerCursor() {
        guard let current = CGEvent(source: nil)?.location, let screen = cursorScreen(current) else { return }
        moveCursorRelative(dx: screen.midX - current.x, dy: screen.midY - current.y)
    }

    func startMovementTimerIfNeeded() {
        guard movementTimer == nil else { return }
        
        // 60 FPS timer
        movementTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            self?.updateMovement()
        }
    }
    
    func updateMovement() {
        guard !activeMovementKeys.isEmpty || !stepAnimations.isEmpty else {
            // Nothing held and no step still gliding
            movementTimer?.invalidate()
            movementTimer = nil
            currentSpeed = minSpeed
            return
        }
        
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        let scrollSpeed: Int32 = 2 // Scroll steps per frame
        
        // j/; left/right, k/l down/up: a key's step first (it finishes even
        // after a quick release), then the held glide
        var gliding = false
        for (key, vector) in directionVectors {
            var distance: CGFloat = 0
            if let step = stepAnimations[key] {
                distance = min(step.perFrame, step.remaining)
                let remaining = step.remaining - distance
                stepAnimations[key] = remaining > 0.01 ? (remaining, step.perFrame) : nil
            } else if activeMovementKeys.contains(key) {
                distance = currentSpeed
                gliding = true
            }
            dx += vector.dx * distance
            dy += vector.dy * distance
        }
        // Exponential acceleration while held
        if gliding {
            currentSpeed = min(currentSpeed * speedGrowth, maxSpeed)
        }
        
        // Horizontal scrolling (vertical is half a page per press: scrollHalfPage)
        var scrollX: Int32 = 0
        // y (16) -> Scroll Left
        // o (31) -> Scroll Right
        if activeMovementKeys.contains(16) { scrollX += scrollSpeed }
        if activeMovementKeys.contains(31) { scrollX -= scrollSpeed }
        
        if dx != 0 || dy != 0 {
            moveCursorRelative(dx: dx, dy: dy)
        }
        
        if scrollX != 0 {
            performScroll(dx: scrollX, dy: 0)
        }
    }
    
    // Same as pressing Cmd+Shift+5 (so it follows the user's screenshot
    // settings). The overlay is hidden first so it isn't in the capture and
    // the toolbar gets the keyboard (Return / Esc).
    func openScreenshotToolbar() {
        hideWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let source = CGEventSource(stateID: .hidSystemState)
            let five: CGKeyCode = 23
            for keyDown in [true, false] {
                if let event = CGEvent(keyboardEventSource: source, virtualKey: five, keyDown: keyDown) {
                    event.flags = [.maskCommand, .maskShift]
                    event.post(tap: .cghidEventTap)
                }
            }
        }
    }

    // Same as the keyboard's volume keys (system volume plus the on-screen
    // indicator): media keys are system-defined events, not key codes.
    func pressVolumeKey(up: Bool) {
        let key = up ? NX_KEYTYPE_SOUND_UP : NX_KEYTYPE_SOUND_DOWN
        for (keyDown, flags) in [(true, 0xa00), (false, 0xb00)] {
            let event = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                           modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flags)),
                                           timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                                           data1: Int((key << 16) | (keyDown ? 0xa00 : 0xb00)), data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    // Scroll half the height of the window under the cursor (the one that
    // receives the scroll), split into a few pixel steps so it glides.
    // With Shift (`fine`) only a tenth of it, for small adjustments.
    func scrollHalfPage(up: Bool, fine: Bool = false) {
        let cursor = CGEvent(source: nil)?.location ?? .zero
        var pageHeight = (NSScreen.main?.frame.height ?? 900)
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for info in windows {  // front to back
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? Int32) != getpid(),
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.contains(cursor) else { continue }
            pageHeight = bounds.height
            break
        }
        let steps = 8
        let distance = pageHeight * (fine ? 0.1 : 0.5)
        let step = Int32((distance / CGFloat(steps)).rounded()) * (up ? 1 : -1)
        for i in 0..<steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(i * 12)) {
                if let scroll = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: step, wheel2: 0, wheel3: 0) {
                    scroll.flags = []  // a held Shift would make apps scroll sideways
                    scroll.post(tap: .cghidEventTap)
                }
            }
        }
    }

    func performScroll(dx: Int32, dy: Int32) {
        let source = CGEventSource(stateID: .hidSystemState)
        // scrollWheelEvent2Source uses (lines, rows, columns). We usually just want 'lines' (axis 1).
        // A simpler initializer is `CGEvent(scrollWheelEvent2Source:units:wheelCount:wheel1:wheel2:wheel3:)`
        // wheel1 is Y axis usually. wheel2 is X axis.
        
        if let scroll = CGEvent(scrollWheelEvent2Source: source, units: .line, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0) {
            scroll.post(tap: .cghidEventTap)
        }
    }
    
    // Sync the row filter, selected cell and zoom panel with the input buffer
    func updateGridSelection() {
        guard let gridView = window.contentView as? GridView else { return }
        gridView.typedPrefix = String(inputBuffer.prefix(2))
        if inputBuffer.count >= 2 {
            let code = String(inputBuffer.prefix(2))
            if gridView.selectedCode != code {
                gridView.selectedCode = code
                // Grid-move acts on the 2nd letter immediately, so only grid mode zooms
                if zoomEnabled && (currentMode == .grid || currentMode == .gridDrag) {
                    requestZoom(forCode: code)
                }
            }
        } else {
            gridView.selectedCode = nil
        }
    }

    // Capture the selected cell for the zoom panel. Needs Screen Recording
    // permission (macOS 14+); without it the panel just shows the letters.
    var zoomGeneration = 0  // ignores captures for a cell that's no longer selected

    func requestZoom(forCode code: String) {
        guard #available(macOS 14.0, *), CGPreflightScreenCaptureAccess() else { return }
        let chars = Array(code)
        guard chars.count == 2,
              let (r, c) = GridConfig.cell(for: code),
              let screen = window.screen,
              let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        else { return }

        // View coordinates are top-left and the window covers the whole
        // screen, which matches ScreenCaptureKit's display-local sourceRect.
        let rowHeight = window.frame.height / CGFloat(GridConfig.rows)
        let colWidth = window.frame.width / CGFloat(GridConfig.cols)
        let cellRect = CGRect(x: CGFloat(c) * colWidth, y: CGFloat(r) * rowHeight,
                              width: colWidth, height: rowHeight)
        let scale = screen.backingScaleFactor
        let ownWindowID = CGWindowID(window.windowNumber)

        zoomGeneration += 1
        let generation = zoomGeneration

        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first(where: { $0.displayID == displayID }) else { return }
                // Leave our overlay out of the capture
                let overlay = content.windows.filter { $0.windowID == ownWindowID }
                let filter = SCContentFilter(display: display, excludingWindows: overlay)
                let config = SCStreamConfiguration()
                config.sourceRect = cellRect
                config.width = Int(cellRect.width * scale)
                config.height = Int(cellRect.height * scale)
                config.showsCursor = false
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                await MainActor.run {
                    guard generation == self.zoomGeneration,
                          let gridView = self.window.contentView as? GridView,
                          gridView.selectedCode == code else { return }
                    gridView.zoomImage = image
                }
            } catch {
                print("Zoom capture failed: \(error)")
            }
        }
    }

    // Backspace: undo the last typed letter (grid and grid-move modes)
    func handleBackspace() {
        if inputBuffer.isEmpty && currentMode == .gridDrag && dragStart != nil {
            cancelHeldDrag()
            (window.contentView as? GridView)?.dragStartMarker = nil
            return
        }
        guard !inputBuffer.isEmpty else { return }
        inputBuffer.removeLast()
        updateGridSelection()
    }

    func handleInput(char: Character, kind: ClickKind) {
        guard GridConfig.accepts(char, after: inputBuffer) else { return }
        // Append input
        inputBuffer.append(char)
        
        // Max buffer size is now 3 (2 for parent, 1 for mini)
        if inputBuffer.count > 3 {
             inputBuffer = String(inputBuffer.suffix(3))
        }
        
        updateGridSelection()
        
        // Immediate Click Action if count == 3
        // An invalid mini letter rolls the buffer back to the parent code
        // and keeps the grid open so the user can retry.
        if inputBuffer.count == 3 {
             if processClick(code: inputBuffer, kind: kind) {
                 hideWindow()
             }
        }
    }
    
    func handleConfirm(kind: ClickKind) {
        // Quick Click: If buffer is empty, click at current mouse location
        if inputBuffer.isEmpty {
            performQuickClick(kind: kind)
            return
        }
        
        // Only confirm parent if we have exactly 2 chars
        if inputBuffer.count == 2 {
            if processClick(code: inputBuffer, kind: kind) {
                hideWindow()
            }
        }
    }
    
    func handleGridMoveInput(char: Character) {
        guard GridConfig.accepts(char, after: inputBuffer) else { return }
        // Append input
        inputBuffer.append(char)
        
        // Max buffer size is 2 for grid move (no mini grid)
        if inputBuffer.count > 2 {
             inputBuffer = String(inputBuffer.suffix(2))
        }
        
        updateGridSelection()
        
        // Immediate Move Action if count == 2 (but stay in mode)
        if inputBuffer.count == 2 {
             if processMove(code: inputBuffer) {
                 // On successful move, switch to movement mode
                 startMovementMode()
             } else {
                 // Invalid code, just clear buffer and stay in gridMove
                 inputBuffer = ""
                 if let gridView = window.contentView as? GridView {
                     gridView.selectedCode = nil
                     gridView.typedPrefix = ""
                 }
             }
        }
    }
    
    func handleGridMoveConfirm() {
        // If buffer has 2 chars, move to that location (but stay in mode)
        if inputBuffer.count == 2 {
            if processMove(code: inputBuffer) {
                startMovementMode()
            } else {
                inputBuffer = ""
                if let gridView = window.contentView as? GridView {
                    gridView.selectedCode = nil
                    gridView.typedPrefix = ""
                }
            }
        }
    }
    
    func performQuickClick(kind: ClickKind) {
        // CGEvent location is already in Quartz coordinates (Top-Left Origin)
        guard let currentPos = CGEvent(source: nil)?.location else { return }
        print("Quick Click at: \(currentPos)")
        
        DispatchQueue.main.async {
            self.hideWindow()
        }
        
        executeClick(at: currentPos, kind: kind)
    }
    
    // Screen point (Quartz, top-left origin) for a 2-letter cell code, or a
    // 3-letter code aiming at a sub-cell. nil for an invalid code; an invalid
    // 3rd letter rolls the buffer back to the 2-letter code.
    func pointFor(code: String) -> CGPoint? {
        guard let window = window else { return nil }
        let chars = Array(code)
        let miniKeys = GridConfig.miniKeys(for: code)

        // Check for Parent Grid Code (2 chars)
        guard let (pcIndex1, pcIndex2) = GridConfig.cell(for: code) else {
            print("Invalid parent code: \(code)")
            inputBuffer = ""
            return nil
        }

        // Parent Grid Dimensions
        let rows = GridConfig.rows
        let cols = GridConfig.cols
        let width = window.frame.width
        let height = window.frame.height
        let rowHeight = height / CGFloat(rows)
        let colWidth = width / CGFloat(cols)
        
        // Parent Cell Origin (Top-Left in View Coords)
        let parentX = CGFloat(pcIndex2) * colWidth
        let parentY = CGFloat(pcIndex1) * rowHeight
        
        var targetX = parentX + colWidth / 2
        var targetY = parentY + rowHeight / 2 // Default to center of parent
        
        // Check for Mini Grid Code (3rd char)
        if chars.count == 3 {
             if let miniIndex = miniKeys.firstIndex(of: chars[2]) {
                 // Mini Grid Dimensions
                 let miniRows = GridConfig.miniRows
                 let miniCols = GridConfig.miniCols
                 let miniWidth = colWidth / CGFloat(miniCols)
                 let miniHeight = rowHeight / CGFloat(miniRows)
                 
                 let mr = miniIndex / miniCols
                 let mc = miniIndex % miniCols
                 
                 // Center of Mini Cell relative to Parent Origin
                 let miniCenterX = (CGFloat(mc) + 0.5) * miniWidth
                 let miniCenterY = (CGFloat(mr) + 0.5) * miniHeight
                 
                 targetX = parentX + miniCenterX
                 targetY = parentY + miniCenterY
             } else {
                 print("Invalid mini code: \(chars[2])")
                 inputBuffer = String(code.prefix(2)) // Rollback to parent
                 return nil
             }
        }
        
        // Convert to Global Cocoa Coordinates (Bottom-Left Origin)
        let globalX = window.frame.minX + targetX
        let globalY = window.frame.maxY - targetY
        
        // Convert to Quartz Coordinates (Top-Left Origin)
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 1080
        let quartzY = primaryScreenHeight - globalY
        
        return CGPoint(x: globalX, y: quartzY)
    }

    @discardableResult
    func processClick(code: String, kind: ClickKind) -> Bool {
        guard let clickPoint = pointFor(code: code) else { return false }
        print("Clicking at: \(clickPoint)")
        
        // Hide window FIRST so the click hits the app below, not our window
        // But we must do it on main thread
        DispatchQueue.main.async {
            self.hideWindow()
        }
        
        executeClick(at: clickPoint, kind: kind)
        return true
    }

    // Drag mode input: same keys as the click grid (2 letters + Space, or a 3rd
    // letter for a sub-cell; Space alone = current cursor position). The first
    // pick sets the start and brings the grid back; the second performs the drag.
    func handleDragInput(char: Character) {
        guard GridConfig.accepts(char, after: inputBuffer) else { return }
        inputBuffer.append(char)
        if inputBuffer.count > 3 {
            inputBuffer = String(inputBuffer.suffix(3))
        }
        updateGridSelection()
        if inputBuffer.count == 3 {
            if let point = pointFor(code: inputBuffer) {
                dragPick(point)
            } else {
                updateGridSelection()  // invalid 3rd letter was rolled back
            }
        }
    }

    func handleDragConfirm() {
        if inputBuffer.isEmpty {
            if let current = CGEvent(source: nil)?.location { dragPick(current) }
        } else if inputBuffer.count == 2, let point = pointFor(code: inputBuffer) {
            dragPick(point)
        }
    }

    func dragPick(_ point: CGPoint) {
        guard let start = dragStart else {
            // First pick: press the button there and keep it held, so the user
            // can switch Space (shortcuts pass through) before picking the drop.
            showWindow(mode: .gridDrag)
            dragStart = point
            if let gridView = window.contentView as? GridView {
                // Quartz (top-left of primary screen) -> view coords (top-left of this window)
                let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 1080
                let cocoaY = primaryScreenHeight - point.y
                gridView.dragStartMarker = NSPoint(x: point.x - window.frame.minX, y: window.frame.maxY - cocoaY)
            }
            beginHeldDrag(at: point)
            return
        }
        print("Dragging from \(start) to \(point)")
        dragStart = nil  // hideWindow must not release the button at the start
        hideWindow()
        finishHeldDrag(to: point)
    }

    // Serial so the press, the moves and the release never overtake each other
    let dragQueue = DispatchQueue(label: "whitewindow.drag", qos: .userInteractive)

    func postDragEvent(_ type: CGEventType, _ point: CGPoint) {
        postLeftButtonEvent(type, at: point)
    }

    // Left-button event as a real mouse sends it: click state 1 and, for
    // drags, the movement since the last position. Window edges, the
    // screenshot selection and similar trackers read the deltas and ignore
    // drags without them.
    func postLeftButtonEvent(_ type: CGEventType, at point: CGPoint) {
        let previous = CGEvent(source: nil)?.location ?? point
        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return }
        event.flags = []
        if type != .mouseMoved {
            event.setIntegerValueField(.mouseEventClickState, value: 1)
        }
        if type == .leftMouseDragged || type == .mouseMoved {
            event.setIntegerValueField(.mouseEventDeltaX, value: Int64((point.x - previous.x).rounded()))
            event.setIntegerValueField(.mouseEventDeltaY, value: Int64((point.y - previous.y).rounded()))
        }
        event.post(tap: .cghidEventTap)
    }

    // Press at the start and wiggle a few pixels: apps only start a drag
    // after some movement with the button down.
    func beginHeldDrag(at start: CGPoint) {
        dragQueue.async {
            self.postDragEvent(.mouseMoved, start)
            Thread.sleep(forTimeInterval: 0.05)
            self.postDragEvent(.leftMouseDown, start)
            Thread.sleep(forTimeInterval: 0.1)
            for offset in [2.0, 4.0, 6.0, 0.0] as [CGFloat] {
                self.postDragEvent(.leftMouseDragged, CGPoint(x: start.x + offset, y: start.y + offset))
                Thread.sleep(forTimeInterval: 0.015)
            }
        }
    }

    // Move to the drop point in small steps, then release
    func finishHeldDrag(to end: CGPoint) {
        dragQueue.async {
            let from = CGEvent(source: nil)?.location ?? end
            let steps = 25
            for i in 1...steps {
                let t = CGFloat(i) / CGFloat(steps)
                self.postDragEvent(.leftMouseDragged, CGPoint(x: from.x + (end.x - from.x) * t, y: from.y + (end.y - from.y) * t))
                Thread.sleep(forTimeInterval: 0.012)
            }
            Thread.sleep(forTimeInterval: 0.1)
            self.postDragEvent(.leftMouseUp, end)
        }
    }

    // Escape / Backspace / closing with the button held: drop where it is
    func cancelHeldDrag() {
        guard dragStart != nil else { return }
        dragStart = nil
        dragQueue.async {
            let here = CGEvent(source: nil)?.location ?? .zero
            self.postDragEvent(.leftMouseUp, here)
        }
    }

    func processMove(code: String) -> Bool {
        guard let window = window else { return false }
        // Check for Grid Code (2 chars)
        guard let (pcIndex1, pcIndex2) = GridConfig.cell(for: code) else {
            print("Invalid grid code: \(code)")
            inputBuffer = ""
            return false
        }

        // Grid Dimensions
        let rows = GridConfig.rows
        let cols = GridConfig.cols
        let width = window.frame.width
        let height = window.frame.height
        let rowHeight = height / CGFloat(rows)
        let colWidth = width / CGFloat(cols)
        
        // Cell Origin (Top-Left in View Coords)
        let cellX = CGFloat(pcIndex2) * colWidth
        let cellY = CGFloat(pcIndex1) * rowHeight
        
        // Target is center of cell
        let targetX = cellX + colWidth / 2
        let targetY = cellY + rowHeight / 2
        
        // Convert to Global Cocoa Coordinates (Bottom-Left Origin)
        let globalX = window.frame.minX + targetX
        let globalY = window.frame.maxY - targetY
        
        // Convert to Quartz Coordinates (Top-Left Origin)
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 1080
        let quartzY = primaryScreenHeight - globalY
        
        let movePoint = CGPoint(x: globalX, y: quartzY)
        print("Moving cursor to: \(movePoint)")
        
        // Move cursor immediately (don't hide window for gridMove mode)
        executeMove(to: movePoint)
        
        return true
    }
    
    func executeMove(to point: CGPoint) {
        // Move cursor immediately
        CGAssociateMouseAndMouseCursorPosition(0)
        CGWarpMouseCursorPosition(point)
        CGAssociateMouseAndMouseCursorPosition(1)
        
        // Post move event for proper event propagation
        let source = CGEventSource(stateID: .hidSystemState)
        let move = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
        move?.post(tap: .cghidEventTap)
        
    }
    
    func executeClick(at point: CGPoint, kind: ClickKind) {
        // Perform click with slight delay to ensure window is gone
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.05) { [weak self] in
            let source = CGEventSource(stateID: .hidSystemState)

            // Events from the HID source inherit the modifiers currently held,
            // and Shift/Option are still down here (they chose the click kind).
            // Clear them so apps don't see a Shift-click or Option-click.
            func post(_ type: CGEventType, _ button: CGMouseButton, clickState: Int64 = 1) {
                guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button) else { return }
                event.flags = []
                event.setIntegerValueField(.mouseEventClickState, value: clickState)
                event.post(tap: .cghidEventTap)
            }

            // 1. Move
            post(.mouseMoved, .left, clickState: 0)
            Thread.sleep(forTimeInterval: 0.02)

            // 2. Click
            switch kind {
            case .left:
                post(.leftMouseDown, .left)
                Thread.sleep(forTimeInterval: 0.02)
                post(.leftMouseUp, .left)
            case .right:
                post(.rightMouseDown, .right)
                Thread.sleep(forTimeInterval: 0.02)
                post(.rightMouseUp, .right)
            case .double:
                post(.leftMouseDown, .left, clickState: 1)
                post(.leftMouseUp, .left, clickState: 1)
                Thread.sleep(forTimeInterval: 0.02)
                post(.leftMouseDown, .left, clickState: 2)
                post(.leftMouseUp, .left, clickState: 2)
            }
            
            print("Click simulated (\(kind)).")
            
            // Reset state explicitly just in case
            DispatchQueue.main.async {
                self?.inputBuffer = ""
                self?.isTapPotential = false
            }
        }
    }
    
    func moveCursorRelative(dx: CGFloat, dy: CGFloat) {
        guard let currentPos = CGEvent(source: nil)?.location else { return }
        var newPos = CGPoint(x: currentPos.x + dx, y: currentPos.y + dy)
        
        // Get combined screen bounds (all screens) in Quartz coordinates (top-left origin)
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 0
        var combinedBounds = CGRect.null
        for screen in NSScreen.screens {
            // Convert Cocoa coordinates (bottom-left origin) to Quartz (top-left origin)
            let quartzFrame = CGRect(
                x: screen.frame.minX,
                y: primaryScreenHeight - screen.frame.maxY,
                width: screen.frame.width,
                height: screen.frame.height
            )
            combinedBounds = combinedBounds.union(quartzFrame)
        }
        
        // Clamp to screen bounds
        newPos.x = max(combinedBounds.minX, min(newPos.x, combinedBounds.maxX - 1))
        newPos.y = max(combinedBounds.minY, min(newPos.y, combinedBounds.maxY - 1))
        
        // Warp cursor (this triggers dock/menu behavior at screen edges)
        CGAssociateMouseAndMouseCursorPosition(0)
        CGWarpMouseCursorPosition(newPos)
        CGAssociateMouseAndMouseCursorPosition(1)
        
        // Post move event for proper event propagation to apps
        let source = CGEventSource(stateID: .hidSystemState)
        let move = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: newPos, mouseButton: .left)
        move?.post(tap: .cghidEventTap)
    }
    
    
    func performClick() {
        guard let currentPos = CGEvent(source: nil)?.location else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        
        // Check for double-click
        let now = Date()
        if let lastClick = lastClickTime, now.timeIntervalSince(lastClick) < clickInterval {
            // Double-click detected
            performDoubleClick()
            lastClickTime = nil  // Reset
            return
        }
        
        // Single click (post off the main thread to avoid blocking it during the sleep)
        lastClickTime = now
        DispatchQueue.global(qos: .userInteractive).async {
            let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: currentPos, mouseButton: .left)
            down?.post(tap: .cghidEventTap)

            Thread.sleep(forTimeInterval: 0.02)

            let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: currentPos, mouseButton: .left)
            up?.post(tap: .cghidEventTap)

            print("Single Click performed")
        }
    }
    
    func performRightClick() {
        guard let currentPos = CGEvent(source: nil)?.location else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        
        DispatchQueue.global(qos: .userInteractive).async {
            let down = CGEvent(mouseEventSource: source, mouseType: .rightMouseDown, mouseCursorPosition: currentPos, mouseButton: .right)
            down?.post(tap: .cghidEventTap)

            Thread.sleep(forTimeInterval: 0.02)

            let up = CGEvent(mouseEventSource: source, mouseType: .rightMouseUp, mouseCursorPosition: currentPos, mouseButton: .right)
            up?.post(tap: .cghidEventTap)

            print("Right Click performed")
        }
    }
    
    func performDoubleClick() {
        guard let currentPos = CGEvent(source: nil)?.location else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        
        DispatchQueue.global(qos: .userInteractive).async {
            // First click
            let down1 = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: currentPos, mouseButton: .left)
            down1?.setIntegerValueField(.mouseEventClickState, value: 1)
            down1?.post(tap: .cghidEventTap)

            let up1 = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: currentPos, mouseButton: .left)
            up1?.setIntegerValueField(.mouseEventClickState, value: 1)
            up1?.post(tap: .cghidEventTap)

            Thread.sleep(forTimeInterval: 0.02)

            // Second click
            let down2 = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: currentPos, mouseButton: .left)
            down2?.setIntegerValueField(.mouseEventClickState, value: 2)
            down2?.post(tap: .cghidEventTap)

            let up2 = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: currentPos, mouseButton: .left)
            up2?.setIntegerValueField(.mouseEventClickState, value: 2)
            up2?.post(tap: .cghidEventTap)

            print("Double Click performed")
        }
    }

}

// C-compatible callback function for the Event Tap
func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    // Handle tap disabled events to re-enable
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        print("Event tap disabled by system. Re-enabling...")
        if let delegate = NSApp.delegate as? AppDelegate, let tap = delegate.eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }

    // Modifier keys: handled here (not via an NSEvent monitor) so they stay
    // strictly ordered with the keyDown invalidation below. Always passed through.
    if type == .flagsChanged {
        if let delegate = NSApp.delegate as? AppDelegate {
            let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            delegate.handleFlagsChanged(keyCode: keyCode, flags: event.flags)
        }
        return Unmanaged.passUnretained(event)
    }

    // Invalidate triggers on Mouse Clicks or Key Presses/Releases
    // This ensures shortcuts (e.g. Cmd+A) don't trigger the "clean press" actions (Grid Mode).
    // keyUp matters for rolled combos while typing: if the letter goes down a few ms
    // before Cmd registers, its keyDown precedes the potential flag and only its keyUp
    // lands inside the Cmd hold — without this, releasing Cmd would show the grid.
    if type == .keyDown || type == .keyUp || type == .leftMouseDown || type == .rightMouseDown {
        if let delegate = NSApp.delegate as? AppDelegate {
            // Invalidate Command/Control potential on any key press or click
            if delegate.isTapPotential {
                delegate.isTapPotential = false
            }
            delegate.cancelPendingTap()
            if type == .keyDown || type == .keyUp { delegate.lastKeyEventTime = Date() }
        }
    }

    if type == .keyDown {
        if let delegate = NSApp.delegate as? AppDelegate {
            let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            
            // If window is visible, we intercept keys
            if delegate.window.isVisible {
                
                // Escape (53)
                if keyCode == 53 {
                    DispatchQueue.main.async { delegate.hideWindow() }
                    return nil
                }
                
                // Movement Mode Logic
                if delegate.currentMode == .movement {
                    // Check for Modifiers (Cmd, Ctrl, Option)
                    // If any are held, pass the event through to allow system shortcuts (e.g. Cmd+A, Cmd+Tab)
                    let flags = event.flags
                    if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
                        return Unmanaged.passUnretained(event)
                    }

                    // 32: u (scroll up half a page), 2: d (scroll down half a page)
                    // 16: y (scroll left), 31: o (scroll right)
                    // 49: space (Right Click)
                    // 0: a (Right Click)
                    // 1: s (screenshot toolbar, Cmd+Shift+5)
                    // 8: c (center the cursor on its screen)
                    // 45: n / 46: m (volume down / up)
                    let directionKeys: Set<Int> = [38, 40, 37, 41]
                    let scrollKeys: Set<Int> = [16, 31]
                    let pageKeys: Set<Int> = [32, 2]
                    let validMovementKeys: Set<Int> = directionKeys.union(scrollKeys).union(pageKeys).union([49, 0, 4, 1, 8, 45, 46])
                    
                    
                    // If key is NOT a valid movement key, exit cursor mode
                    if !validMovementKeys.contains(keyCode) {
                        DispatchQueue.main.async { delegate.hideWindow() }
                        return nil
                    }
                    
                    // Holding A or Space must not repeat clicks
                    let isAutorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                    if isAutorepeat && (keyCode == 0 || keyCode == 49) {
                        return nil
                    }

                    // u / d -> half a page up / down, once per press (holding repeats
                    // at the keyboard repeat rate, like Ctrl-U / Ctrl-D in Vim)
                    if pageKeys.contains(keyCode) {
                        let fine = flags.contains(.maskShift)
                        DispatchQueue.main.async { delegate.scrollHalfPage(up: keyCode == 32, fine: fine) }
                        return nil
                    }

                    // s (1) -> close the overlay and open the screenshot toolbar
                    if keyCode == 1 {
                        if !isAutorepeat {
                            DispatchQueue.main.async { delegate.openScreenshotToolbar() }
                        }
                        return nil
                    }

                    // c (8) -> center the cursor
                    if keyCode == 8 {
                        DispatchQueue.main.async { delegate.centerCursor() }
                        return nil
                    }

                    // n (45) / m (46) -> volume down / up (holding repeats)
                    if keyCode == 45 || keyCode == 46 {
                        DispatchQueue.main.async { delegate.pressVolumeKey(up: keyCode == 46) }
                        return nil
                    }

                    // h (4) -> toggle cursor visibility
                    if keyCode == 4 {
                        if !isAutorepeat {
                            DispatchQueue.main.async { delegate.toggleCursorHidden() }
                        }
                        return nil
                    }

                    // Handle Right Click (a)
                    if keyCode == 0 {
                         DispatchQueue.main.async { delegate.performRightClick() }
                         return nil
                    }
                    
                    // Shift + direction key: a small fixed nudge, no glide (holding
                    // repeats it at the keyboard repeat rate)
                    if directionKeys.contains(keyCode) && flags.contains(.maskShift) {
                        DispatchQueue.main.async { delegate.nudge(keyCode: keyCode) }
                        return nil
                    }

                    // Direction keys: perform tap movement first, then start continuous
                    if directionKeys.contains(keyCode) {
                        // Only perform tap if this key wasn't already pressed (prevent key repeat)
                        if !delegate.activeMovementKeys.contains(keyCode) {
                            DispatchQueue.main.async {
                                delegate.handleDirectionPress(keyCode: keyCode)
                                delegate.activeMovementKeys.insert(keyCode)
                                delegate.startMovementTimerIfNeeded()
                            }
                        }
                        return nil // Consume
                    }
                    
                    // Scroll keys
                    if scrollKeys.contains(keyCode) {
                        DispatchQueue.main.async {
                            delegate.activeMovementKeys.insert(keyCode)
                            delegate.startMovementTimerIfNeeded()
                        }
                        return nil // Consume
                    }
                    
                    // space (49) -> right click (the left click is a lone left
                    // Option tap: handleGridTap)
                    if keyCode == 49 {
                        DispatchQueue.main.async { delegate.performRightClick() }
                        return nil
                    }
                    
                    return nil // Consume valid keys
                }

                
                // Backspace (51) - undo last letter (grid and grid-move)
                if keyCode == 51 && (delegate.currentMode == .grid || delegate.currentMode == .gridMove || delegate.currentMode == .gridDrag) {
                    DispatchQueue.main.async { delegate.handleBackspace() }
                    return nil
                }

                // Grid Mode Logic
                if delegate.currentMode == .grid {
                    // Shift / Option on the confirming key pick right / double click
                    let kind = ClickKind(flags: event.flags)

                    // Space (49) - right click (Option+Space: double click). The
                    // left click is a lone left Option tap (handleGridTap).
                    if keyCode == 49 {
                        let spaceKind: ClickKind = event.flags.contains(.maskAlternate) ? .double : .right
                        DispatchQueue.main.async { delegate.handleConfirm(kind: spaceKind) }
                        return nil // Swallow space
                    }
                    
                    // Try to capture characters
                    if let nsEvent = NSEvent(cgEvent: event), let chars = nsEvent.charactersIgnoringModifiers?.lowercased() {
                        if let firstChar = chars.first.map(GridConfig.normalize) {
                            if GridConfig.validInputChars.contains(firstChar) {
                                DispatchQueue.main.async {
                                    delegate.handleInput(char: firstChar, kind: kind)
                                }
                                return nil // Swallow valid input
                            }
                        }
                    }
                }
                
                // Grid Move Mode Logic (similar to grid but moves instead of clicks)
                if delegate.currentMode == .gridMove {
                    // Space (49) - Confirm
                    if keyCode == 49 {
                        DispatchQueue.main.async { delegate.handleGridMoveConfirm() }
                        return nil // Swallow space
                    }
                    
                    // Try to capture characters
                    if let nsEvent = NSEvent(cgEvent: event), let chars = nsEvent.charactersIgnoringModifiers?.lowercased() {
                        if let firstChar = chars.first.map(GridConfig.normalize) {
                            if GridConfig.validInputChars.contains(firstChar) {
                                DispatchQueue.main.async {
                                    delegate.handleGridMoveInput(char: firstChar)
                                }
                                return nil // Swallow valid input
                            }
                        }
                    }
                }
                
                // Drag Mode Logic (two picks: start, then destination)
                if delegate.currentMode == .gridDrag {
                    // Shortcuts (e.g. switching Space while the button is held) and
                    // keys the grid doesn't use (arrows, F-keys) go to the system.
                    let flags = event.flags
                    let isLetter = (NSEvent(cgEvent: event)?.charactersIgnoringModifiers?.lowercased().first).map { GridConfig.validInputChars.contains(GridConfig.normalize($0)) } ?? false
                    if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate)
                        || (!isLetter && keyCode != 49) {
                        return Unmanaged.passUnretained(event)
                    }
                    if keyCode == 49 {
                        DispatchQueue.main.async { delegate.handleDragConfirm() }
                        return nil
                    }
                    if let nsEvent = NSEvent(cgEvent: event), let chars = nsEvent.charactersIgnoringModifiers?.lowercased(),
                       let firstChar = chars.first.map(GridConfig.normalize), GridConfig.validInputChars.contains(firstChar) {
                        DispatchQueue.main.async { delegate.handleDragInput(char: firstChar) }
                        return nil
                    }
                }

                // Swallow all other keys to block typing
                return nil
            } else {
                // Window not visible
                // Already handled at top of function
            }
        }
    }
    
    if type == .keyUp {
        if let delegate = NSApp.delegate as? AppDelegate {
            if delegate.window.isVisible && delegate.currentMode == .movement {
                let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
                
                // Active Movement Keys
                if delegate.activeMovementKeys.contains(keyCode) {
                     DispatchQueue.main.async {
                        delegate.handleDirectionRelease(keyCode: keyCode)
                        delegate.activeMovementKeys.remove(keyCode)
                     }
                     return nil // Consume
                }
                
                // Release of a Shift nudge (never added to activeMovementKeys)
                if delegate.directionVectors[keyCode] != nil {
                    return nil
                }

                // space acts on keyDown only; swallow the release too
                if keyCode == 49 {
                    return nil
                }

                // u / d act on keyDown only; swallow the release too
                if keyCode == 32 || keyCode == 2 {
                    return nil
                }
            }
        }
    }
    
    return Unmanaged.passUnretained(event)
}

// Entry point
setvbuf(stdout, nil, _IOLBF, 0)  // Line-buffer stdout so prints reach the log file when run via launchd

// launchd appends to the same log forever: start it over once it passes 5 MB
var logStat = stat()
if fstat(STDOUT_FILENO, &logStat) == 0, (logStat.st_mode & S_IFMT) == S_IFREG, logStat.st_size > 5_000_000 {
    ftruncate(STDOUT_FILENO, 0)
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
