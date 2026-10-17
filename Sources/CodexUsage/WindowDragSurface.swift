import AppKit
import SwiftUI

// Opt-in diagnostics for real pointer tests; never records account or session data.
@MainActor func recordDragDiagnostic(_ event: String, view: NSView? = nil, window: NSWindow? = nil, point: NSPoint? = nil) {
    guard let index = CommandLine.arguments.firstIndex(of: "--drag-log"), CommandLine.arguments.count > index + 1 else { return }
    let destination = URL(fileURLWithPath: CommandLine.arguments[index + 1])
    let currentWindow = window ?? view?.window
    var record: [String: Any] = ["event": event, "time": Date().timeIntervalSince1970]
    if let view { record["bounds"] = NSStringFromRect(view.bounds); record["viewFrame"] = NSStringFromRect(view.frame) }
    if let currentWindow {
        record["windowFrame"] = NSStringFromRect(currentWindow.frame)
        record["movable"] = currentWindow.isMovable
        record["level"] = currentWindow.level.rawValue
        record["activeSpace"] = currentWindow.isOnActiveSpace
        record["fullScreenAuxiliary"] = currentWindow.collectionBehavior.contains(.fullScreenAuxiliary)
        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        let index = windows.firstIndex { ($0[kCGWindowNumber as String] as? NSNumber)?.intValue == currentWindow.windowNumber }
        record["onScreen"] = index != nil
        if let index {
            // Only record counts/layers, never other apps' names or window titles.
            record["normalWindowsBelow"] = windows.dropFirst(index + 1).filter {
                ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 &&
                ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value != ProcessInfo.processInfo.processIdentifier
            }.count
        }
    }
    if let point { record["point"] = NSStringFromPoint(point) }
    guard var data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else { return }
    data.append(10)
    if !FileManager.default.fileExists(atPath: destination.path) { FileManager.default.createFile(atPath: destination.path, contents: nil) }
    if let file = try? FileHandle(forWritingTo: destination) {
        defer { try? file.close() }
        _ = try? file.seekToEnd(); try? file.write(contentsOf: data)
    }
}

struct WindowDragSurface: NSViewRepresentable {
    let showMenu: (NSEvent) -> Void

    func makeNSView(context: Context) -> NativeWindowDragView {
        let view = NativeWindowDragView()
        view.setAccessibilityElement(false)
        return view
    }
    func updateNSView(_ view: NativeWindowDragView, context: Context) {
        view.showMenu = showMenu
        recordDragDiagnostic("update", view: view)
    }
}

/// A native overlay catches the left mouse down even over SwiftUI text and rings.
/// Settings live in native context/menu-bar menus; the entire card is draggable.
final class NativeWindowDragView: NSView {
    var showMenu: ((NSEvent) -> Void)?
    private var grabOffset: NSPoint?
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        recordDragDiagnostic("hitTest", view: self, point: local)
        let card = NSBezierPath(roundedRect: bounds, xRadius: 24, yRadius: 24)
        guard card.contains(local) else { return nil }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        recordDragDiagnostic("mouseDown", view: self, point: event.locationInWindow)
        grabOffset = event.locationInWindow
    }
    override func mouseDragged(with event: NSEvent) {
        guard let window, let grabOffset else { return }
        let pointer = window.convertPoint(toScreen: event.locationInWindow)
        window.setFrameOrigin(NSPoint(x: pointer.x - grabOffset.x, y: pointer.y - grabOffset.y))
        recordDragDiagnostic("mouseDragged", view: self, point: event.locationInWindow)
    }
    override func mouseUp(with event: NSEvent) {
        defer { grabOffset = nil }
        guard let window, grabOffset != nil else { return }
        // Keep the complete card on a connected display after dropping it.
        let pointer = window.convertPoint(toScreen: event.locationInWindow)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) {
            let visible = screen.visibleFrame
            let frame = window.frame
            let origin = NSPoint(x: min(max(frame.minX, visible.minX), max(visible.minX, visible.maxX - frame.width)),
                                 y: min(max(frame.minY, visible.minY), max(visible.minY, visible.maxY - frame.height)))
            window.setFrameOrigin(origin)
        }
        recordDragDiagnostic("mouseUp", view: self)
    }
    override func rightMouseDown(with event: NSEvent) {
        showMenu?(event)
    }
}
