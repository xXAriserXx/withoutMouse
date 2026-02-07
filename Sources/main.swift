import Cocoa
import SwiftUI

let appVersion = "0.1.0"

// Custom View to draw the grid
// Custom View to draw the grid
class GridView: NSView {
    enum Mode {
        case grid
        case movement
        case gridMove  // Grid mode that moves cursor without clicking
    }
    
    var mode: Mode = .grid {
        didSet { needsDisplay = true }
    }
    
    override var isFlipped: Bool { return true }

    // Track selected code for highlighting (Grid Mode)
    var selectedCode: String? {
        didSet {
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        // Background - Black with 50% opacity for Grid Mode and Grid Move Mode
        if mode == .grid || mode == .gridMove {
            NSColor.black.withAlphaComponent(0.5).setFill()
            dirtyRect.fill()
        }
        
        switch mode {
        case .grid:
            drawGrid(dirtyRect)
        case .movement:
            drawMovementUI(dirtyRect)
        case .gridMove:
            drawGrid(dirtyRect)  // Same grid display, different behavior
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
        // Grid Dimensions
        let rows = 27
        let cols = 35
        let width = bounds.width
        let height = bounds.height
        let rowHeight = height / CGFloat(rows)
        let colWidth = width / CGFloat(cols)
        
        // Text Attributes
        let fontSize = min(rowHeight, colWidth) * 0.5 
        // Font: Verdana Regular (much lighter than Bold)
        // Fallback to system .light if Verdana missing
        let font = NSFont(name: "Verdana", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize, weight: .light)
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        
        // Shadow for readability
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black
        shadow.shadowOffset = NSSize(width: 1, height: -1)
        shadow.shadowBlurRadius = 2.0
        
        // Text Color: White 90%
        let defaultAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white.withAlphaComponent(0.9),
            .paragraphStyle: paragraphStyle,
            .shadow: shadow
        ]
        
        // Draw Two-Letter Codes
        // Extended alphabet restricted to letters + punctuation (36 chars)
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz;',./!?-=\\")
        
        for r in 0..<rows {
            for c in 0..<cols {
                let x = CGFloat(c) * colWidth
                let y = CGFloat(r) * rowHeight
                let cellRect = NSRect(x: x, y: y, width: colWidth, height: rowHeight)
                
                // Code Generation
                let firstChar = alphabet[r % alphabet.count]
                let secondChar = alphabet[c % alphabet.count]
                let code = "\(firstChar)\(secondChar)".uppercased() // Uppercase as requested
                
                // Highlight if selected
                if let selected = selectedCode, selected.uppercased() == code {
                    NSColor.green.withAlphaComponent(0.6).setFill() // Slightly more transparent green for readability
                    cellRect.fill()
                    
                    // Draw Mini Grid (3 rows, 5 cols) - 15 cells (A-O)
                    let miniRows = 3
                    let miniCols = 5
                    let miniWidth = colWidth / CGFloat(miniCols)
                    let miniHeight = rowHeight / CGFloat(miniRows)
                    let miniAlphabet = Array("abcdefghijklmno")
                    
                    // Mini Text Attrs
                    let miniFontSize = min(miniWidth, miniHeight) * 0.7
                    // Lighter font for mini grid too
                    let miniFont = NSFont(name: "Verdana", size: miniFontSize) ?? NSFont.systemFont(ofSize: miniFontSize, weight: .medium)
                    let miniAttrs: [NSAttributedString.Key: Any] = [
                        .font: miniFont,
                        .foregroundColor: NSColor.white.withAlphaComponent(1.0),
                        .paragraphStyle: paragraphStyle,
                        .shadow: shadow
                    ]
                    
                    for mr in 0..<miniRows {
                        for mc in 0..<miniCols {
                            let mx = cellRect.origin.x + CGFloat(mc) * miniWidth
                            let my = cellRect.origin.y + CGFloat(mr) * miniHeight
                            let miniRect = NSRect(x: mx, y: my, width: miniWidth, height: miniHeight)
                            
                            // Draw Mini Grid Lines
                            NSColor.white.withAlphaComponent(0.5).setStroke()
                            let miniPath = NSBezierPath(rect: miniRect)
                            miniPath.lineWidth = 0.5
                            miniPath.stroke()
                            
                            // Draw Mini Label
                            let index = mr * miniCols + mc
                            if index < miniAlphabet.count {
                                let char = miniAlphabet[index]
                                let charText = String(char).uppercased()
                                let mSize = charText.size(withAttributes: miniAttrs)
                                let mTextRect = miniRect.offsetBy(dx: 0, dy: (miniHeight - mSize.height) / 2)
                                charText.draw(in: mTextRect, withAttributes: miniAttrs)
                            }
                        }
                    }
                    
                } else {
                    // Normal Text
                    let text = code
                    let stringHeight = text.size(withAttributes: defaultAttrs).height
                    let textRect = cellRect.offsetBy(dx: 0, dy: (rowHeight - stringHeight) / 2)
                    text.draw(in: textRect, withAttributes: defaultAttrs)
                }
            }
        }
        
        // Draw Lines - Subtle white grid lines
        let path = NSBezierPath()
        path.lineWidth = 1.0
        
        // Horizontal Lines
        for i in 0...rows {
            let y = CGFloat(i) * rowHeight
            path.move(to: NSPoint(x: 0, y: y))
            path.line(to: NSPoint(x: width, y: y))
        }
        
        // Vertical Lines
        for i in 0...cols {
            let x = CGFloat(i) * colWidth
            path.move(to: NSPoint(x: x, y: 0))
            path.line(to: NSPoint(x: x, y: height))
        }
        
        NSColor.white.withAlphaComponent(0.2).setStroke() 
        path.stroke()
    }
}

// Application Delegate to manage lifecycle and events
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var globalMonitor: Any?
    var eventTap: CFMachPort?

    var inputBuffer = ""
    var isCmdPotential = false
    var isCtrlPotential = false
    var isCmdDown = false
    var isCtrlDown = false
    var cmdPressTime: Date?  // Track when command key was pressed
    var ctrlPressTime: Date?  // Track when control key was pressed
    var lastCtrlReleaseTime: Date?  // Track last control release for double-tap detection
    var ctrlTapCount = 0 // Track number of consecutive control taps
    let doubleTapInterval: TimeInterval = 1.0  // Max time between taps (reduced slightly for better feel with 3 taps)
    
    // Mode Tracking
    var currentMode: GridView.Mode = .grid
    
    // Movement Parameters
    var currentSpeed: CGFloat = 0.05
    let minSpeed: CGFloat = 0.05
    let maxSpeed: CGFloat = 20.0
    let acceleration: CGFloat = 0.15
    
    // Smooth Movement State
    var activeMovementKeys: Set<Int> = []
    var movementTimer: Timer?
    var isDragging = false
    var leftClickPressTime: Date?  // Track when left click key was pressed
    var lastClickTime: Date?  // Track last click for double-click detection
    let clickInterval: TimeInterval = 0.3  // Max time between clicks for double-click
    let dragThreshold: TimeInterval = 0.2  // Hold time before drag starts
    
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
        
        print("WhiteWindow v\(appVersion) started. Press Cmd to show, Esc to hide.") 
    }
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
    
    func setupMonitors() {
        // Global monitor for flagsChanged (modifier keys)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        
        // CGEventTap for Keys (Added keyUp for smooth movement)
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.rightMouseDown.rawValue) | (1 << CGEventType.tapDisabledByTimeout.rawValue) | (1 << CGEventType.tapDisabledByUserInput.rawValue)
        
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: eventTapCallback,
            userInfo: nil
        ) else {
            print("CRITICAL ERROR: Failed to create event tap. Is the app sandboxed or lacking permissions?")
            return
        }
        
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        self.eventTap = eventTap
        print("Event tap successfully created.")
    }
    
    // ... handleFlagsChanged ... (unchanged)
    func handleFlagsChanged(_ event: NSEvent) {
        let commandKey = NSEvent.ModifierFlags.command
        let controlKey = NSEvent.ModifierFlags.control
        let otherModifiers: NSEvent.ModifierFlags = [.shift, .option, .capsLock]
        
        // Command Key Logic (Grid Mode)
        if event.modifierFlags.contains(commandKey) {
            if !isCmdDown {
                // Initial Press
                isCmdDown = true
                // Check if clean AND Left Command (55)
                // Left Command: 55, Right Command: 54
                if event.keyCode == 55 && event.modifierFlags.intersection(otherModifiers).isEmpty && !event.modifierFlags.contains(controlKey) {
                    isCmdPotential = true
                    cmdPressTime = Date()
                } else {
                    isCmdPotential = false
                    cmdPressTime = nil
                }
            } else {
                // Already Down - check if invalidated
                // If Right Command (54) interacts, invalidate
                if event.keyCode == 54 {
                    isCmdPotential = false
                    cmdPressTime = nil
                }
                
                if !event.modifierFlags.intersection(otherModifiers).isEmpty || event.modifierFlags.contains(controlKey) {
                    isCmdPotential = false
                    cmdPressTime = nil
                }
            }
        } else {
            // Command Released
            isCmdDown = false
            
            if isCmdPotential {
                // Only show grid if command was held for less than 1 second
                if let pressTime = cmdPressTime {
                    let elapsed = Date().timeIntervalSince(pressTime)
                    if elapsed < 1.0 {
                        startGridMode()
                    }
                }
            }
            isCmdPotential = false
            cmdPressTime = nil
        }
        
        // Control Key Logic (Movement Mode / Grid Move Mode)
        if event.modifierFlags.contains(controlKey) {
             if !isCtrlDown {
                 // Initial Press
                 isCtrlDown = true
                 // Check if clean
                 if event.modifierFlags.intersection(otherModifiers).isEmpty && !event.modifierFlags.contains(commandKey) {
                     isCtrlPotential = true
                     ctrlPressTime = Date()
                 } else {
                     isCtrlPotential = false
                     ctrlPressTime = nil
                 }
             } else {
                 // Already Down - check if invalidated
                 if !event.modifierFlags.intersection(otherModifiers).isEmpty || event.modifierFlags.contains(commandKey) {
                     isCtrlPotential = false
                     ctrlPressTime = nil
                 }
             }
        } else {
            // Control Released
            isCtrlDown = false
            
            if isCtrlPotential {
                // Check duration - Must be short press (< 0.25s)
                if let pressTime = ctrlPressTime {
                    let elapsed = Date().timeIntervalSince(pressTime)
                    if elapsed > 0.25 {
                        print("Control held too long (\(elapsed)s). Ignoring.")
                        isCtrlPotential = false
                        ctrlPressTime = nil
                        return
                    }
                }
                
                // Cycle Modes Logic (State-based, time-independent)
                if let win = window, win.isVisible {
                    switch currentMode {
                    case .movement:
                        startGridMoveMode()
                    case .gridMove:
                        startMovementMode()
                    case .grid:
                        startMovementMode()
                    }
                } else {
                    // Start sequence (1st tap)
                    startMovementMode()
                }
            }
            isCtrlPotential = false
            ctrlPressTime = nil
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
        if let gridView = window.contentView as? GridView {
            gridView.mode = mode
            gridView.selectedCode = nil // Reset selection
        }
        inputBuffer = "" // Reset buffer
        
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
    }
    
    func hideWindow() {
        guard let window = window else { return }
        if window.isVisible {
            window.orderOut(nil)
            inputBuffer = ""
            if let gridView = window.contentView as? GridView {
                gridView.selectedCode = nil
            }
            // Stop movement
            stopMovement()
            // Stop dragging/release mouse if active
            endDragIfNeeded()
        }
    }
    
    func stopMovement() {
        movementTimer?.invalidate()
        movementTimer = nil
        activeMovementKeys.removeAll()
        currentSpeed = minSpeed // Reset speed
    }
    
    func endDragIfNeeded() {
        if isDragging {
            isDragging = false
            performMouseUp()
        }
    }
    
    func performTapMovement(keyCode: Int) {
        // Move exactly 5 pixels in the direction of the pressed key
        let tapDistance: CGFloat = 5.0
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        
        if keyCode == 38 { dx = -tapDistance } // j -> left
        if keyCode == 41 { dx = tapDistance }  // ; -> right
        if keyCode == 40 { dy = tapDistance }  // k -> down
        if keyCode == 37 { dy = -tapDistance } // l -> up
        
        if dx != 0 || dy != 0 {
            moveCursorRelative(dx: dx, dy: dy)
        }
    }
    
    func startMovementTimerIfNeeded() {
        guard movementTimer == nil else { return }
        
        // 60 FPS timer
        movementTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            self?.updateMovement()
        }
    }
    
    func updateMovement() {
        guard !activeMovementKeys.isEmpty else { return }
        
        // Apply acceleration
        if currentSpeed < maxSpeed {
            currentSpeed += acceleration
            if currentSpeed > maxSpeed {
                currentSpeed = maxSpeed
            }
        }
        
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        var scrollY: Int32 = 0
        let speed = currentSpeed // Use accelerated speed
        let scrollSpeed: Int32 = 2 // Scroll steps per frame
        
        if activeMovementKeys.contains(38) { dx -= speed } // j -> left
        if activeMovementKeys.contains(41) { dx += speed } // ; -> right
        
        // SWAPPED K and L as requested
        // k (40) is now DOWN (+y)
        // l (37) is now UP (-y)
        if activeMovementKeys.contains(40) { dy += speed } // k -> down
        if activeMovementKeys.contains(37) { dy -= speed } // l -> up
        
        // Scrolling
        // d (2) -> Scroll Down
        // u (32) -> Scroll Up
        if activeMovementKeys.contains(2) { scrollY -= scrollSpeed }
        if activeMovementKeys.contains(32) { scrollY += scrollSpeed }

        var scrollX: Int32 = 0
        // a (0) -> Scroll Left
        // s (1) -> Scroll Right
        if activeMovementKeys.contains(0) { scrollX += scrollSpeed } // Left/Right might depend on natural scrolling, let's try + for left first? No standard is - left.
        // Actually, usually wheel2 positive is left? Let's try standard: + is right, - is left. 
        // Wait, for Y: down is -negative. up is positive.
        // So for X: left is negative? right is positive?
        // Let's implement: s (right) -> +speed, a (left) -> -speed.
        
        if activeMovementKeys.contains(0) { scrollX += scrollSpeed } // a -> left (testing +)
        if activeMovementKeys.contains(1) { scrollX -= scrollSpeed } // s -> right (testing -)
        // Note: I will just use standard logic: 
        // usually wheel2: positive = scroll left (content moves right), negative = scroll right (content moves left).
        // Let's stick to what worked for Y: d (down) -> -scrollY. 
        
        // v (9) -> Scroll Left
        // b (11) -> Scroll Right
        if activeMovementKeys.contains(9) { scrollX += scrollSpeed }
        if activeMovementKeys.contains(11) { scrollX -= scrollSpeed }
        
        if dx != 0 || dy != 0 {
            moveCursorRelative(dx: dx, dy: dy)
        }
        
        if scrollY != 0 || scrollX != 0 {
            performScroll(dx: scrollX, dy: scrollY)
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
    
    func handleInput(char: Character) {
        // Append input
        inputBuffer.append(char)
        
        // Max buffer size is now 3 (2 for parent, 1 for mini)
        if inputBuffer.count > 3 {
             inputBuffer = String(inputBuffer.suffix(3))
        }
        
        print("Input buffer: \(inputBuffer)")
        
        // Update selection in GridView (needs first 2 chars)
        if let gridView = window.contentView as? GridView {
            if inputBuffer.count >= 2 {
                gridView.selectedCode = String(inputBuffer.prefix(2))
            } else {
                gridView.selectedCode = nil
            }
        }
        
        // Immediate Click Action if count == 3
        if inputBuffer.count == 3 {
             processClick(code: inputBuffer)
             hideWindow()
        }
    }
    
    func handleConfirm() {
        // Quick Click: If buffer is empty, click at current mouse location
        if inputBuffer.isEmpty {
            performQuickClick()
            return
        }
        
        // Only confirm parent if we have exactly 2 chars
        if inputBuffer.count == 2 {
            processClick(code: inputBuffer)
            hideWindow()
        }
    }
    
    func handleGridMoveInput(char: Character) {
        // Append input
        inputBuffer.append(char)
        
        // Max buffer size is 2 for grid move (no mini grid)
        if inputBuffer.count > 2 {
             inputBuffer = String(inputBuffer.suffix(2))
        }
        
        print("GridMove Input buffer: \(inputBuffer)")
        
        // Update selection in GridView
        if let gridView = window.contentView as? GridView {
            if inputBuffer.count >= 2 {
                gridView.selectedCode = String(inputBuffer.prefix(2))
            } else {
                gridView.selectedCode = nil
            }
        }
        
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
                }
            }
        }
    }
    
    func performQuickClick() {
        // CGEvent location is already in Quartz coordinates (Top-Left Origin)
        guard let currentPos = CGEvent(source: nil)?.location else { return }
        print("Quick Click at: \(currentPos)")
        
        DispatchQueue.main.async {
            self.hideWindow()
        }
        
        executeClick(at: currentPos)
    }
    
    func processClick(code: String) {
        guard let window = window else { return }
        let chars = Array(code)
        // Extended alphabet restricted to letters + punctuation (36 chars)
        let alphabet = "abcdefghijklmnopqrstuvwxyz;',./!?-=\\"
        let miniAlphabet = "abcdefghijklmno" // 15 chars for 3x5 grid
        
        // Check for Parent Grid Code (2 chars)
        guard chars.count >= 2,
              let pcIndex1 = alphabet.firstIndex(of: chars[0])?.utf16Offset(in: alphabet),
              let pcIndex2 = alphabet.firstIndex(of: chars[1])?.utf16Offset(in: alphabet) else {
            print("Invalid parent code: \(code)")
            inputBuffer = ""
            return
        }
        
        // Parent Grid Dimensions
        let rows = 27
        let cols = 35
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
             if let miniIndex = miniAlphabet.firstIndex(of: chars[2])?.utf16Offset(in: miniAlphabet) {
                 // Mini Grid Dimensions (3 rows, 5 cols)
                 let miniRows = 3
                 let miniCols = 5
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
                 return
             }
        }
        
        // Convert to Global Cocoa Coordinates (Bottom-Left Origin)
        let globalX = window.frame.minX + targetX
        let globalY = window.frame.maxY - targetY
        
        // Convert to Quartz Coordinates (Top-Left Origin)
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 1080
        let quartzY = primaryScreenHeight - globalY
        
        let clickPoint = CGPoint(x: globalX, y: quartzY)
        print("Clicking at: \(clickPoint)")
        
        // Hide window FIRST so the click hits the app below, not our window
        // But we must do it on main thread
        DispatchQueue.main.async {
            self.hideWindow()
        }
        
        executeClick(at: clickPoint)
    }
    
    func processMove(code: String) -> Bool {
        guard let window = window else { return false }
        let chars = Array(code)
        // Extended alphabet restricted to letters + punctuation (36 chars)
        let alphabet = "abcdefghijklmnopqrstuvwxyz;',./!?-=\\"
        
        // Check for Grid Code (2 chars)
        guard chars.count >= 2,
              let pcIndex1 = alphabet.firstIndex(of: chars[0])?.utf16Offset(in: alphabet),
              let pcIndex2 = alphabet.firstIndex(of: chars[1])?.utf16Offset(in: alphabet) else {
            print("Invalid grid code: \(code)")
            inputBuffer = ""
            return false
        }
        
        // Grid Dimensions
        let rows = 27
        let cols = 35
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
        
        print("Cursor moved to: \(point)")
    }
    
    func executeClick(at point: CGPoint) {
        // Perform click with slight delay to ensure window is gone
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.05) { [weak self] in
            let source = CGEventSource(stateID: .hidSystemState)
            
            // 1. Move
            let move = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
            move?.post(tap: .cghidEventTap)
            
            Thread.sleep(forTimeInterval: 0.02)
            
            // 2. Down
            let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
            down?.post(tap: .cghidEventTap)
            
            Thread.sleep(forTimeInterval: 0.02)
            
            // 3. Up
            let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
            up?.post(tap: .cghidEventTap)
            
            print("Click simulated.")
            
            // Reset state explicitly just in case
            DispatchQueue.main.async {
                self?.inputBuffer = ""
                self?.isCmdPotential = false
                self?.isCtrlPotential = false
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
        
        // Post move/drag event for proper event propagation to apps
        let source = CGEventSource(stateID: .hidSystemState)
        let mouseType: CGEventType = isDragging ? .leftMouseDragged : .mouseMoved
        let move = CGEvent(mouseEventSource: source, mouseType: mouseType, mouseCursorPosition: newPos, mouseButton: .left)
        move?.post(tap: .cghidEventTap)
    }
    
    func performMouseDown() {
        guard let currentPos = CGEvent(source: nil)?.location else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: currentPos, mouseButton: .left)
        down?.post(tap: .cghidEventTap)
        isDragging = true
        print("Mouse Down (Drag Started)")
    }
    
    func performMouseUp() {
        guard let currentPos = CGEvent(source: nil)?.location else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: currentPos, mouseButton: .left)
        up?.post(tap: .cghidEventTap)
        isDragging = false
        print("Mouse Up (Drag Ended)")
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
        
        // Single click
        let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: currentPos, mouseButton: .left)
        down?.post(tap: .cghidEventTap)
        
        Thread.sleep(forTimeInterval: 0.02)
        
        let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: currentPos, mouseButton: .left)
        up?.post(tap: .cghidEventTap)
        
        lastClickTime = now
        print("Single Click performed")
    }
    
    func performRightClick() {
        guard let currentPos = CGEvent(source: nil)?.location else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        
        let down = CGEvent(mouseEventSource: source, mouseType: .rightMouseDown, mouseCursorPosition: currentPos, mouseButton: .right)
        down?.post(tap: .cghidEventTap)
        
        Thread.sleep(forTimeInterval: 0.02)
        
        let up = CGEvent(mouseEventSource: source, mouseType: .rightMouseUp, mouseCursorPosition: currentPos, mouseButton: .right)
        up?.post(tap: .cghidEventTap)
        
        print("Right Click performed")
    }
    
    func performDoubleClick() {
        guard let currentPos = CGEvent(source: nil)?.location else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        
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
    
    func handleLeftClickDown() {
        leftClickPressTime = Date()
    }
    
    func handleLeftClickUp() {
        guard let pressTime = leftClickPressTime else { return }
        
        let holdDuration = Date().timeIntervalSince(pressTime)
        leftClickPressTime = nil
        
        if isDragging {
            // If we were dragging, end the drag
            performMouseUp()
        } else if holdDuration < dragThreshold {
            // Quick tap - perform click
            performClick()
        }
        // If holdDuration >= dragThreshold but not dragging, we already started drag in a timer
    }
    
    func startDragIfHeld() {
        // Called after dragThreshold to start a drag
        if !isDragging && leftClickPressTime != nil {
            performMouseDown()
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

    // Invalidate triggers on Mouse Clicks or Key Presses
    // This ensures shortcuts (e.g. Cmd+A) don't trigger the "clean press" actions (Grid Mode)
    if type == .keyDown || type == .leftMouseDown || type == .rightMouseDown {
        if let delegate = NSApp.delegate as? AppDelegate {
            // Invalidate Command/Control potential on any key press or click
            if delegate.isCmdPotential || delegate.isCtrlPotential {
                print("Input detected (type: \(type.rawValue)). Invalidating triggers.")
                delegate.isCmdPotential = false
                delegate.isCtrlPotential = false
            }
        }
    }

    if type == .keyDown {
        if let delegate = NSApp.delegate as? AppDelegate {
            let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            // Only log if window is visible or if it's a key we care about for debugging
            if delegate.window.isVisible {
                print("KeyDown detected - keyCode: \(keyCode), window.isVisible: \(delegate.window.isVisible), mode: \(delegate.currentMode)")
            }
            
            // If window is visible, we intercept keys
            if delegate.window.isVisible {
                
                // Escape (53)
                if keyCode == 53 {
                    print("Escape pressed, hiding window")
                    DispatchQueue.main.async { delegate.hideWindow() }
                    return nil
                }
                
                // Movement Mode Logic
                if delegate.currentMode == .movement {
                    // Check for Modifiers (Cmd, Ctrl, Option)
                    // If any are held, pass the event through to allow system shortcuts (e.g. Cmd+A, Cmd+Tab)
                    let flags = event.flags
                    if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
                        print("Modifier detected in Movement Mode. Passing through event.")
                        return Unmanaged.passUnretained(event)
                    }

                    // 2: d (scroll down), 32: u (scroll up)
                    // 9: v (scroll left), 11: b (scroll right)
                    // 3: f (Left Click/Drag)
                    // 0: a (Right Click)
                    let directionKeys: Set<Int> = [38, 40, 37, 41]
                    let scrollKeys: Set<Int> = [2, 32, 9, 11]
                    let validMovementKeys: Set<Int> = directionKeys.union(scrollKeys).union([3, 0])
                    
                    print("Movement mode active. Valid keys: \(validMovementKeys). Pressed: \(keyCode). Is valid: \(validMovementKeys.contains(keyCode))")
                    
                    // If key is NOT a valid movement key, exit cursor mode
                    if !validMovementKeys.contains(keyCode) {
                        print(">>> INVALID KEY! Exiting movement mode <<<")
                        DispatchQueue.main.async { delegate.hideWindow() }
                        return nil
                    }
                    
                    // Handle Right Click (a)
                    if keyCode == 0 {
                         DispatchQueue.main.async { delegate.performRightClick() }
                         return nil
                    }
                    
                    // Direction keys: perform tap movement first, then start continuous
                    if directionKeys.contains(keyCode) {
                        // Only perform tap if this key wasn't already pressed (prevent key repeat)
                        if !delegate.activeMovementKeys.contains(keyCode) {
                            DispatchQueue.main.async {
                                delegate.performTapMovement(keyCode: keyCode)
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
                    
                    // f (3) -> Left Click or start drag
                    if keyCode == 3 {
                        DispatchQueue.main.async {
                            delegate.handleLeftClickDown()
                            // Schedule drag start after threshold
                            DispatchQueue.main.asyncAfter(deadline: .now() + delegate.dragThreshold) {
                                delegate.startDragIfHeld()
                            }
                        }
                        return nil
                    }
                    
                    return nil // Consume valid keys
                }

                
                // Grid Mode Logic
                if delegate.currentMode == .grid {
                    // Space (49) - Confirm
                    if keyCode == 49 {
                        DispatchQueue.main.async { delegate.handleConfirm() }
                        return nil // Swallow space
                    }
                    
                    // Try to capture characters
                    if let nsEvent = NSEvent(cgEvent: event), let chars = nsEvent.charactersIgnoringModifiers?.lowercased() {
                        if let firstChar = chars.first {
                            let validChars = "abcdefghijklmnopqrstuvwxyz;',./!?-=\\"
                            if validChars.contains(firstChar) {
                                DispatchQueue.main.async {
                                    delegate.handleInput(char: firstChar)
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
                        if let firstChar = chars.first {
                            let validChars = "abcdefghijklmnopqrstuvwxyz;',./!?-=\\"
                            if validChars.contains(firstChar) {
                                DispatchQueue.main.async {
                                    delegate.handleGridMoveInput(char: firstChar)
                                }
                                return nil // Swallow valid input
                            }
                        }
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
                        delegate.activeMovementKeys.remove(keyCode)
                        if delegate.activeMovementKeys.isEmpty {
                            delegate.stopMovement()
                        }
                     }
                     return nil // Consume
                }
                
                // f (3) -> Handle release (click or end drag)
                if keyCode == 3 {
                     DispatchQueue.main.async { delegate.handleLeftClickUp() }
                    return nil
                }
            }
        }
    }
    
    return Unmanaged.passUnretained(event)
}

// Entry point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
