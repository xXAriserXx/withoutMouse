import Cocoa
import SwiftUI

// Custom View to draw the grid
// Custom View to draw the grid
class GridView: NSView {
    enum Mode {
        case grid
        case movement
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
        // Background - Black with 50% opacity ONLY for Grid Mode
        if mode == .grid {
            NSColor.black.withAlphaComponent(0.5).setFill()
            dirtyRect.fill()
        }
        
        switch mode {
        case .grid:
            drawGrid(dirtyRect)
        case .movement:
            drawMovementUI(dirtyRect)
        }
    }
    
    func drawMovementUI(_ dirtyRect: NSRect) {
        // Draw a blue border to distinguish - Minimalist as requested
        NSColor.systemBlue.setStroke()
        let borderPath = NSBezierPath(rect: bounds.insetBy(dx: 2, dy: 2))
        borderPath.lineWidth = 4
        borderPath.stroke()
    }

    func drawGrid(_ dirtyRect: NSRect) {
        // Grid Dimensions
        let rows = 25
        let cols = 26
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
            .foregroundColor: NSColor.green.withAlphaComponent(0.9),
            .paragraphStyle: paragraphStyle,
            .shadow: shadow
        ]
        
        // Draw Two-Letter Codes
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz")
        
        for r in 0..<rows {
            for c in 0..<cols {
                let x = CGFloat(c) * colWidth
                let y = CGFloat(r) * rowHeight
                let cellRect = NSRect(x: x, y: y, width: colWidth, height: rowHeight)
                
                // Code Generation
                let firstChar = alphabet[r % 26]
                let secondChar = alphabet[c % 26]
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
                        .foregroundColor: NSColor.green.withAlphaComponent(1.0),
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
    
    // Mode Tracking
    var currentMode: GridView.Mode = .grid
    
    // Smooth Movement State
    var activeMovementKeys: Set<Int> = []
    var movementTimer: Timer?
    var isDragging = false
    
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
        
        window.level = .floating 
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
        
        print("WhiteWindow started. Press Cmd to show, Esc to hide.") 
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
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.tapDisabledByTimeout.rawValue) | (1 << CGEventType.tapDisabledByUserInput.rawValue)
        
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
            // If other modifiers are pressed, cancel potental
            if !event.modifierFlags.intersection(otherModifiers).isEmpty || event.modifierFlags.contains(controlKey) {
                isCmdPotential = false
                return
            }
            if !isCmdPotential {
                isCmdPotential = true
            }
        } else {
            // Command Released
            if isCmdPotential {
                // If we are already visible, toggle off? Or maybe just re-show/reset?
                // Standard behavior: show grid
                startGridMode()
            }
            isCmdPotential = false
        }
        
        // Control Key Logic (Movement Mode)
        if event.modifierFlags.contains(controlKey) {
             if !event.modifierFlags.intersection(otherModifiers).isEmpty || event.modifierFlags.contains(commandKey) {
                isCtrlPotential = false
                return
            }
            if !isCtrlPotential {
                isCtrlPotential = true
            }
        } else {
            // Control Released
            if isCtrlPotential {
                startMovementMode()
            }
            isCtrlPotential = false
        }
    }
    
    func startGridMode() {
        showWindow(mode: .grid)
    }
    
    func startMovementMode() {
        showWindow(mode: .movement)
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
    }
    
    func endDragIfNeeded() {
        if isDragging {
            isDragging = false
            performMouseUp()
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
        
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        var scrollY: Int32 = 0
        let speed: CGFloat = 8.0 // Vertically/Horizontally pixels per frame. 8 * 60 = 480px/sec.
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
        
        if dx != 0 || dy != 0 {
            moveCursorRelative(dx: dx, dy: dy)
        }
        
        if scrollY != 0 {
            performScroll(dy: scrollY)
        }
    }
    
    func performScroll(dy: Int32) {
        let source = CGEventSource(stateID: .hidSystemState)
        // scrollWheelEvent2Source uses (lines, rows, columns). We usually just want 'lines' (axis 1).
        // A simpler initializer is `CGEvent(scrollWheelEvent2Source:units:wheelCount:wheel1:wheel2:wheel3:)`
        // wheel1 is Y axis usually.
        
        if let scroll = CGEvent(scrollWheelEvent2Source: source, units: .line, wheelCount: 1, wheel1: dy, wheel2: 0, wheel3: 0) {
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
        let alphabet = "abcdefghijklmnopqrstuvwxyz"
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
        let rows = 25
        let cols = 26
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

    if type == .keyDown {
        if let delegate = NSApp.delegate as? AppDelegate {
            // If window is visible, we intercept keys
            if delegate.window.isVisible {
                let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
                
                // Escape (53)
                if keyCode == 53 {
                    DispatchQueue.main.async { delegate.hideWindow() }
                    return nil
                }
                
                // Movement Mode Logic
                if delegate.currentMode == .movement {
                    // Start tracking key if it's one of ours
                    if [38, 40, 37, 41, 2, 32].contains(keyCode) {
                        DispatchQueue.main.async {
                            delegate.activeMovementKeys.insert(keyCode)
                            delegate.startMovementTimerIfNeeded()
                        }
                        return nil // Consume
                    }
                    
                    // Spacebar (49) -> Mouse Down
                    if keyCode == 49 {
                        if !delegate.isDragging {
                            DispatchQueue.main.async { delegate.performMouseDown() }
                        }
                        return nil
                    }
                    
                    return nil // Consume all keys in movement mode to block typing
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
                        if let firstChar = chars.first, firstChar.isLetter {
                            DispatchQueue.main.async {
                                delegate.handleInput(char: firstChar)
                            }
                            return nil // Swallow valid input
                        }
                    }
                }
                
                // Swallow all other keys to block typing
                return nil
            } else {
                // Window not visible
                // Invalidate Command/Control potential on any key press
                delegate.isCmdPotential = false
                delegate.isCtrlPotential = false
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
                
                // Spacebar (49) -> Mouse Up
                if keyCode == 49 {
                    if delegate.isDragging {
                         DispatchQueue.main.async { delegate.performMouseUp() }
                    }
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
