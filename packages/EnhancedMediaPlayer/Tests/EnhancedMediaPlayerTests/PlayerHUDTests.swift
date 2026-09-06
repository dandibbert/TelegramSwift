#if canImport(AppKit)
import AppKit
import XCTest
@testable import EnhancedMediaPlayer

private final class FlippedVideoCanvas: NSView {
    override var isFlipped: Bool { true }
}
final class PlayerHUDTests: XCTestCase {
    func testHUDDrawsVisibleTextOnFrameBasedCanvasAndSurvivesResize() throws {
        _ = NSApplication.shared
        for flipped in [false, true] {
            let parent: NSView = flipped ? FlippedVideoCanvas() : NSView()
            parent.frame = NSRect(x: 0, y: 0, width: 800, height: 450)
            parent.wantsLayer = true
            let window = NSWindow(contentRect: parent.bounds, styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = parent
            defer { window.close() }
            let hud = PlayerHUD(in: parent)
            hud.show("+15 s", detail: "02:15 / 24:00")
            XCTAssertTrue(hud.subviews.isEmpty, "HUD must not depend on field-editor or label sublayers")
            XCTAssertEqual(hud.frame.midX, parent.bounds.midX, accuracy: 1)
            XCTAssertTrue(parent.bounds.contains(hud.frame))
            XCTAssertLessThan(hud.frame.height, 60)
            let image = try XCTUnwrap(hud.bitmapImageRepForCachingDisplay(in: hud.bounds))
            hud.cacheDisplay(in: hud.bounds, to: image)
            var brightPixels = 0
            for y in 0..<image.pixelsHigh {
                for x in 0..<image.pixelsWide {
                    if let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                       color.alphaComponent > 0.5, color.redComponent > 0.65, color.greenComponent > 0.65 {
                        brightPixels += 1
                    }
                }
            }
            XCTAssertGreaterThan(brightPixels, 30, "A black rounded rectangle is not a rendered HUD")
            parent.setFrameSize(NSSize(width: 320, height: 180))
            hud.show("1.5×", detail: "")
            XCTAssertEqual(hud.frame.midX, 160, accuracy: 1)
            XCTAssertTrue(parent.bounds.contains(hud.frame))
            XCTAssertEqual(hud.frame.height, 34)
            XCTAssertNil(hud.hitTest(.zero))
            if let path = ProcessInfo.processInfo.environment["PLAYER_UI_SNAPSHOT_DIR"] {
                try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
                try image.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path).appendingPathComponent("hud-\(flipped).png"))
            }
        }
    }
    func testCopyPasteSelectAllInAddedFormsTargetOwnEditor() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 150), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; defer { window.close() }
        let editor = NSTextView(frame: window.contentView!.bounds)
        window.contentView!.addSubview(editor)
        XCTAssertTrue(window.makeFirstResponder(editor))
        func event(_ key: UInt16) throws -> NSEvent {
            return try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: key))
        }
        editor.string = "12345"
        XCTAssertTrue(PlayerTextEditing.handle(try event(0), in: window))
        XCTAssertEqual(editor.selectedRange().length, 5)
        XCTAssertTrue(PlayerTextEditing.handle(try event(8), in: window))
        editor.string = ""
        XCTAssertTrue(PlayerTextEditing.handle(try event(9), in: window))
        XCTAssertEqual(editor.string, "12345")
    }
}
#endif
