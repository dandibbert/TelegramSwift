#if canImport(AppKit)
import AppKit
import XCTest
@testable import EnhancedMediaPlayer

final class PlayerScrollStyleTests: XCTestCase {
    private func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
    func testLegacyAndOverlayScrollersRetainViewportWidthAndScrollPosition() throws {
        _ = NSApplication.shared
        let suite = "PlayerScrollStyleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = PlayerSettingsWindow(store: PlayerSettingsStore(defaults: defaults))
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }
        let root = try XCTUnwrap(window.contentView)
        let scroll = try XCTUnwrap(descendants(root).compactMap { $0 as? NSScrollView }.first)
        for style: NSScroller.Style in [.legacy, .overlay] {
            scroll.scrollerStyle = style
            for width: CGFloat in [680, 750] {
                window.setContentSize(NSSize(width: width, height: 550))
                for page in 0..<3 {
                    controller.selectPage(page)
                    // AppKit can tile after document height changes. Drain the
                    // normal layout passes without relying on window activation.
                    for _ in 0..<3 { root.layoutSubtreeIfNeeded(); scroll.tile() }
                    root.layoutSubtreeIfNeeded()
                    let document = try XCTUnwrap(scroll.documentView)
                    XCTAssertEqual(document.frame.width, scroll.contentView.bounds.width, accuracy: 1)
                    XCTAssertEqual(document.frame.width, scroll.contentSize.width, accuracy: 1)
                    for control in descendants(document).compactMap({ $0 as? NSControl }) {
                        XCTAssertLessThanOrEqual(control.convert(control.bounds, to: document).maxX, document.bounds.width + 1)
                    }
                    if page == 1 {
                        scroll.contentView.scroll(to: NSPoint(x: 0, y: 200))
                        scroll.reflectScrolledClipView(scroll.contentView)
                        root.layoutSubtreeIfNeeded()
                        XCTAssertGreaterThan(scroll.contentView.bounds.origin.y, 0, "Layout must not reset user scrolling")
                    }
                }
            }
        }
    }
}
#endif
