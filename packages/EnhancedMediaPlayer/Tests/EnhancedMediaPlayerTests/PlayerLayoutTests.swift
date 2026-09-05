#if canImport(AppKit)
import AppKit
import XCTest
@testable import EnhancedMediaPlayer

final class PlayerLayoutTests: XCTestCase {
    private func descendants(_ view: NSView) -> [NSView] {
        return view.subviews.flatMap { [$0] + descendants($0) }
    }
    func testAllPagesKeepEditableControlsInsideViewportAndCanScroll() throws {
        _ = NSApplication.shared
        let suite = "PlayerLayoutTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = PlayerSettingsWindow(store: PlayerSettingsStore(defaults: defaults))
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }
        let root = try XCTUnwrap(window.contentView)
        for width: CGFloat in [680, 750, 1000] {
            window.setContentSize(NSSize(width: width, height: 660))
            for page in 0..<3 {
                controller.selectPage(page)
                root.layoutSubtreeIfNeeded()
                let scroll = try XCTUnwrap(descendants(root).compactMap { $0 as? NSScrollView }.first)
                let document = try XCTUnwrap(scroll.documentView)
                XCTAssertEqual(document.frame.width, scroll.contentSize.width, accuracy: 1, "page \(page), width \(width)")
                for control in descendants(document).compactMap({ $0 as? NSControl }) {
                    let rect = control.convert(control.bounds, to: document)
                    XCTAssertGreaterThanOrEqual(rect.minX, -1, "\(type(of: control)) on page \(page)")
                    XCTAssertLessThanOrEqual(rect.maxX, document.bounds.width + 1, "\(type(of: control)) on page \(page)")
                    XCTAssertGreaterThan(rect.width, 1)
                    XCTAssertGreaterThan(rect.height, 1)
                }
                if page == 1 {
                    XCTAssertGreaterThan(document.frame.height, scroll.contentSize.height)
                    scroll.contentView.scroll(to: NSPoint(x: 0, y: 200))
                    scroll.reflectScrolledClipView(scroll.contentView)
                    XCTAssertGreaterThan(scroll.contentView.bounds.origin.y, 0)
                    scroll.contentView.scroll(to: .zero)
                }
                if width == 750, let path = ProcessInfo.processInfo.environment["PLAYER_UI_SNAPSHOT_DIR"] {
                    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
                    for dark in [false, true] {
                        if #available(macOS 10.14, *) { window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua) }
                        root.needsDisplay = true
                        root.layoutSubtreeIfNeeded()
                        if let image = root.bitmapImageRepForCachingDisplay(in: root.bounds) {
                            root.cacheDisplay(in: root.bounds, to: image)
                            let name = "page-\(page)-\(dark ? "dark" : "light").png"
                            try image.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path).appendingPathComponent(name))
                        }
                    }
                }
            }
        }
    }
}
#endif
