#if canImport(AppKit)
import AppKit

public final class PlayerSettingsWindow: NSWindowController {
    private static var instance: PlayerSettingsWindow?
    private let store: PlayerSettingsStore
    private let tabs = NSSegmentedControl(labels: [playerText("控制", "Controls"), playerText("快捷键", "Shortcuts"), playerText("窗口", "Windows")], trackingMode: .selectOne, target: nil, action: nil)
    private let scroll = SettingsScrollView()
    private let feedback = NSTextField(labelWithString: "")
    private var recorders: [PlayerAction: ShortcutRecorder] = [:]

    public static func show() {
        if instance == nil { instance = PlayerSettingsWindow(store: .shared) }
        instance?.reload()
        instance?.showWindow(nil)
        instance?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    public init(store: PlayerSettingsStore) {
        self.store = store
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 750, height: 660),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = playerText("播放器设置", "Playback Settings")
        window.minSize = NSSize(width: 680, height: 440)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.center()
        let root = SettingsBackgroundView(frame: window.contentView!.bounds)
        window.contentView = root
        let heading = NSTextField(labelWithString: playerText("让播放顺手一点", "Make playback yours"))
        heading.font = .systemFont(ofSize: 22, weight: .semibold)
        let subtitle = NSTextField(labelWithString: playerText("快捷操作、独立窗口，以及不打断聊天的迷你播放器。", "Keyboard-first controls, independent windows, and a focused mini player."))
        subtitle.font = .systemFont(ofSize: 12); subtitle.textColor = .secondaryLabelColor
        tabs.target = self; tabs.action = #selector(selectTab); tabs.selectedSegment = 0
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.drawsBackground = false; scroll.borderType = .noBorder
        feedback.font = .systemFont(ofSize: 11); feedback.textColor = .secondaryLabelColor
        feedback.lineBreakMode = .byTruncatingTail
        let reset = CallbackButton(title: playerText("恢复全部默认值…", "Restore All Defaults…")) { [weak self] in
            guard let self = self else { return }
            let alert = NSAlert()
            alert.messageText = playerText("恢复播放器默认设置？", "Restore default playback settings?")
            alert.informativeText = playerText("包括自定义快捷键。不会影响 Telegram 的其他设置。", "This includes custom shortcuts. Other Telegram settings are unaffected.")
            alert.addButton(withTitle: playerText("恢复默认", "Restore Defaults"))
            alert.addButton(withTitle: playerText("取消", "Cancel"))
            if alert.runModal() == .alertFirstButtonReturn { self.store.reset(); self.reload() }
        }
        for view in [heading, subtitle, tabs, scroll, feedback, reset] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: root.topAnchor, constant: 22), heading.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 26),
            subtitle.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 6), subtitle.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            subtitle.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -22),
            tabs.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 18), tabs.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            scroll.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 14), scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor), scroll.bottomAnchor.constraint(equalTo: reset.topAnchor, constant: -12),
            reset.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24), reset.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            feedback.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 26), feedback.centerYAnchor.constraint(equalTo: reset.centerYAnchor),
            feedback.trailingAnchor.constraint(lessThanOrEqualTo: reset.leadingAnchor, constant: -16)
        ])
        reload()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    @objc private func selectTab() { reload() }
    // Also used by UI smoke tests to verify all settings pages at narrow widths.
    func selectPage(_ index: Int) { tabs.selectedSegment = max(0, min(2, index)); reload() }
    public func reload() {
        recorders.removeAll()
        feedback.stringValue = playerText("自动保存 · 仅在播放器内响应按键", "Saved automatically · Shortcuts are local to the player")
        feedback.textColor = .secondaryLabelColor
        let document = FlippedSettingsView()
        let stack = NSStackView()
        document.autoresizingMask = [.width]
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 13
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        scroll.documentView = document
        let p = store.preferences
        switch tabs.selectedSegment {
        case 1:
            heading(playerText("键盘快捷键", "Keyboard shortcuts"), in: stack)
            note(playerText("点击右侧录入；Esc 取消，Delete 清空。支持 Control / Option / Shift / Command 组合及 Hyper。", "Click to record; Esc cancels, Delete clears. Control / Option / Shift / Command and Hyper combinations are supported."), in: stack)
            let reset = CallbackButton(title: playerText("仅恢复快捷键默认值", "Reset Shortcuts Only")) { [weak self] in
                self?.store.update { $0.shortcuts = PlayerPreferences.defaultShortcuts }; self?.reload()
            }
            stack.addArrangedSubview(reset)
            for action in PlayerAction.allCases {
                let button = ShortcutRecorder(shortcut: p.shortcuts[action.rawValue])
                button.onCommit = { [weak self, weak button] shortcut in
                    guard let self = self else { return false }
                    if let shortcut = shortcut {
                        if shortcut.isReserved {
                            self.showError(playerText("这个组合键保留给系统。", "This shortcut is reserved for the system.")); return false
                        }
                        if let conflict = self.store.preferences.conflict(for: shortcut, except: action) {
                            self.showError(playerText("已用于：", "Already assigned to: ") + conflict.title); return false
                        }
                    }
                    self.store.update { $0.shortcuts[action.rawValue] = shortcut }
                    button?.shortcut = shortcut
                    self.feedback.textColor = .secondaryLabelColor
                    self.feedback.stringValue = playerText("已保存：", "Saved: ") + action.title
                    return true
                }
                recorders[action] = button
                let clear = CallbackButton(title: "×") { [weak self, weak button] in
                    self?.store.update { $0.shortcuts.removeValue(forKey: action.rawValue) }
                    button?.shortcut = nil
                }
                clear.toolTip = playerText("清除此快捷键", "Clear shortcut")
                let controls = NSStackView(views: [button, clear]); controls.spacing = 6
                button.widthAnchor.constraint(equalToConstant: 148).isActive = true
                row(action.title, control: controls, in: stack)
            }
        case 2:
            heading(playerText("独立播放器", "Detached player"), in: stack)
            toggle(playerText("记住窗口大小和位置", "Remember window size and position"), value: p.rememberWindow, in: stack) { $0.rememberWindow = $1 }
            toggle(playerText("默认置顶独立播放器", "Keep detached player on top by default"), value: p.detachedOnTop, in: stack) { $0.detachedOnTop = $1 }
            toggle(playerText("独立播放器显示在所有桌面", "Show detached player on all Spaces"), value: p.detachedAllSpaces, in: stack) { $0.detachedAllSpaces = $1 }
            note(playerText("关闭或最小化聊天窗口不会停止独立播放。关闭播放器则暂停；退出整个 App 仍会停止播放。", "Closing or minimizing the chat window does not stop detached playback. Closing the player pauses it; quitting the app stops playback."), in: stack)
            heading(playerText("迷你画中画", "Mini player"), in: stack)
            toggle(playerText("画中画默认置顶", "Keep mini player on top by default"), value: p.miniOnTop, in: stack) { $0.miniOnTop = $1 }
            toggle(playerText("画中画显示在所有桌面", "Show mini player on all Spaces"), value: p.miniAllSpaces, in: stack) { $0.miniAllSpaces = $1 }
            toggle(playerText("接近屏幕角落时吸附", "Snap near screen corners"), value: p.snapToCorners, in: stack) { $0.snapToCorners = $1 }
            number(playerText("控制栏自动隐藏（秒）", "Hide controls after (seconds)"), value: p.controlsHideDelay, range: 0.5...15, in: stack) { $0.controlsHideDelay = $1 }
            note(playerText("D 切换独立窗口，P 切换迷你模式，T 切换当前播放器置顶。Esc 先退出全屏，再返回媒体浏览器。所有按键都可在「快捷键」修改。", "D detaches, P toggles mini mode, T pins the player. Esc exits fullscreen first, then returns to the gallery. Change these keys in Shortcuts."), in: stack)
        default:
            toggle(playerText("启用增强播放器控制", "Enable enhanced player controls"), value: p.enabled, in: stack) { $0.enabled = $1 }
            heading(playerText("时间轴与声音", "Timeline and audio"), in: stack)
            number(playerText("正常快进 / 快退（秒）", "Normal seek (seconds)"), value: p.seekStep, range: 0.1...600, in: stack) { $0.seekStep = $1 }
            number(playerText("精细快进 / 快退（秒）", "Fine seek (seconds)"), value: p.fineSeekStep, range: 0.1...600, in: stack) { $0.fineSeekStep = $1 }
            number(playerText("大步快进 / 快退（秒）", "Large seek (seconds)"), value: p.largeSeekStep, range: 0.1...3600, in: stack) { $0.largeSeekStep = $1 }
            number(playerText("音量步长（%）", "Volume step (%)"), value: p.volumeStep, range: 1...25, in: stack) { $0.volumeStep = $1 }
            heading(playerText("播放速度", "Playback speed"), in: stack)
            number(playerText("倍速调整步长", "Speed adjustment step"), value: p.speedStep, range: 0.05...0.5, in: stack) { $0.speedStep = $1 }
            number(playerText("按住按键时的临时倍速", "Speed while holding the boost key"), value: p.temporarySpeed, range: 0.25...2.5, in: stack) { $0.temporarySpeed = $1 }
            toggle(playerText("记住最后使用的倍速", "Remember last playback speed"), value: p.rememberSpeed, in: stack) { $0.rememberSpeed = $1 }
            note(playerText("临时倍速默认按住 Tab；松开、切换窗口或打开菜单时恢复此前速度，不会污染记忆值。", "Hold Tab for temporary speed. Releasing it, changing windows, or opening a menu restores the previous speed without changing the saved preference."), in: stack)
            heading(playerText("鼠标与屏幕提示", "Mouse and on-screen display"), in: stack)
            choice(playerText("滚轮 / 双指滚动", "Wheel / Two-finger scroll"), labels: [playerText("调整音量", "Volume"), playerText("调整进度", "Seek"), playerText("不接管", "Disabled")], selected: PlayerScrollAction.allCases.firstIndex(of: p.scrollAction) ?? 0, in: stack) { $0.scrollAction = PlayerScrollAction.allCases[$1] }
            choice(playerText("双击视频画面", "Double-click video"), labels: [playerText("切换全屏", "Fullscreen"), playerText("播放 / 暂停", "Play / Pause"), playerText("左右区域快退 / 快进", "Seek in left / right regions"), playerText("不接管", "Disabled")], selected: PlayerDoubleClick.allCases.firstIndex(of: p.doubleClick) ?? 0, in: stack) { $0.doubleClick = PlayerDoubleClick.allCases[$1] }
            toggle(playerText("显示进度、音量和倍速提示", "Show seek, volume and speed feedback"), value: p.showOSD, in: stack) { $0.showOSD = $1 }
            note(playerText("Shift + 滚动临时调整进度。触控板惯性不会在松手后继续改变音量或进度。", "Shift + scroll seeks. Trackpad inertia never keeps changing volume or position after you release."), in: stack)
        }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 26),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -26),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 12)
        ])
        window?.contentView?.layoutSubtreeIfNeeded()
        scroll.fitDocument()
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
    }
    private func showError(_ text: String) { feedback.textColor = .systemRed; feedback.stringValue = text; NSSound.beep() }
    private func heading(_ text: String, in stack: NSStackView) {
        let label = NSTextField(labelWithString: text); label.font = .systemFont(ofSize: 13, weight: .semibold)
        stack.addArrangedSubview(label); stack.setCustomSpacing(7, after: label)
    }
    private func note(_ text: String, in stack: NSStackView) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11); label.textColor = .secondaryLabelColor
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(label)
        label.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    private func row(_ text: String, control: NSView, in stack: NSStackView) {
        let label = NSTextField(labelWithString: text); label.font = .systemFont(ofSize: 13)
        label.lineBreakMode = .byTruncatingTail
        let spacer = NSView()
        let row = NSStackView(views: [label, spacer, control]); row.orientation = .horizontal; row.spacing = 12
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
    }
    private func number(_ title: String, value: Double, range: ClosedRange<Double>, in stack: NSStackView, edit: @escaping (inout PlayerPreferences, Double) -> Void) {
        let field = NumberField(value: value, range: range) { [weak self] value in self?.store.update { edit(&$0, value) } }
        field.widthAnchor.constraint(equalToConstant: 100).isActive = true
        row(title, control: field, in: stack)
    }
    private func toggle(_ title: String, value: Bool, in stack: NSStackView, edit: @escaping (inout PlayerPreferences, Bool) -> Void) {
        let button = CallbackButton(title: title) {}
        button.setButtonType(.switch); button.bezelStyle = .regularSquare
        button.state = value ? .on : .off
        button.callback = { [weak self, weak button] in self?.store.update { edit(&$0, button?.state == .on) } }
        stack.addArrangedSubview(button)
    }
    private func choice(_ title: String, labels: [String], selected: Int, in stack: NSStackView, edit: @escaping (inout PlayerPreferences, Int) -> Void) {
        let popup = ChoicePopup(labels: labels, selected: selected) { [weak self] index in self?.store.update { edit(&$0, index) } }
        popup.widthAnchor.constraint(equalToConstant: 220).isActive = true
        row(title, control: popup, in: stack)
    }
}

// An NSScrollView owns its document frame. Do not constrain that frame back to
// NSClipView: legacy scrollers change the viewport after the document is fitted,
// and a circular width dependency can leave the document 15 points too wide.
private final class SettingsScrollView: NSScrollView {
    private var fittingDocument = false
    override func tile() { super.tile(); fitDocument() }
    override func layout() { super.layout(); fitDocument() }
    func fitDocument() {
        guard !fittingDocument, let document = documentView,
              let stack = document.subviews.first as? NSStackView else { return }
        fittingDocument = true
        defer { fittingDocument = false }
        // A document-height change may reveal a legacy scrollbar. Retile and
        // fit once more using its actual reduced viewport; never reset bounds
        // origin here, otherwise resizing would jump back to the top.
        for _ in 0..<3 {
            let width = max(1, contentSize.width)
            document.setFrameSize(NSSize(width: width, height: document.frame.height))
            document.layoutSubtreeIfNeeded()
            let height = ceil(stack.fittingSize.height + 32)
            document.setFrameSize(NSSize(width: width, height: height))
            document.layoutSubtreeIfNeeded()
            super.tile()
        }
    }
}
private final class SettingsBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }
}
private final class FlippedSettingsView: NSView {
    override var isFlipped: Bool { true }
}
private final class CallbackButton: NSButton {
    var callback: () -> Void
    init(title: String, callback: @escaping () -> Void) {
        self.callback = callback
        super.init(frame: .zero)
        self.title = title; bezelStyle = .rounded
        target = self; action = #selector(invoke)
    }
    @objc private func invoke() { callback() }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
private final class ChoicePopup: NSPopUpButton {
    private let callback: (Int) -> Void
    init(labels: [String], selected: Int, callback: @escaping (Int) -> Void) {
        self.callback = callback
        super.init(frame: .zero, pullsDown: false)
        addItems(withTitles: labels); selectItem(at: selected)
        target = self; action = #selector(invoke)
    }
    @objc private func invoke() { callback(indexOfSelectedItem) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
private final class NumberField: NSTextField, NSTextFieldDelegate {
    private let callback: (Double) -> Void
    private let range: ClosedRange<Double>
    init(value: Double, range: ClosedRange<Double>, callback: @escaping (Double) -> Void) {
        self.range = range; self.callback = callback
        super.init(frame: .zero)
        let formatter = NumberFormatter(); formatter.numberStyle = .decimal
        formatter.minimum = NSNumber(value: range.lowerBound); formatter.maximum = NSNumber(value: range.upperBound)
        formatter.maximumFractionDigits = 2
        self.formatter = formatter; doubleValue = value
        alignment = .right; delegate = self
    }
    func controlTextDidEndEditing(_ obj: Notification) {
        let value = doubleValue
        guard value.isFinite, range.contains(value) else { NSSound.beep(); return }
        callback(value)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
private final class ShortcutRecorder: NSButton {
    var onCommit: ((PlayerShortcut?) -> Bool)?
    var shortcut: PlayerShortcut? { didSet { updateTitle() } }
    private var recording = false
    init(shortcut: PlayerShortcut?) {
        self.shortcut = shortcut
        super.init(frame: .zero)
        bezelStyle = .rounded; font = .systemFont(ofSize: 12)
        target = self; action = #selector(beginRecording)
        updateTitle()
    }
    override var acceptsFirstResponder: Bool { true }
    @objc private func beginRecording() {
        recording = true; window?.makeFirstResponder(self); updateTitle()
    }
    private func updateTitle() {
        title = recording ? playerText("请按快捷键…", "Press shortcut…") : (shortcut?.display ?? playerText("未设置", "Unassigned"))
    }
    override func resignFirstResponder() -> Bool { recording = false; updateTitle(); return super.resignFirstResponder() }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if recording { keyDown(with: event); return true }
        return super.performKeyEquivalent(with: event)
    }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { recording = false; updateTitle(); window?.makeFirstResponder(nil); return }
        let shortcut = event.keyCode == 51 && event.modifierFlags.rawValue & PlayerShortcut.modifierMask == 0 ? nil : PlayerShortcut(event.keyCode, event.modifierFlags.rawValue)
        if onCommit?(shortcut) == true { recording = false; updateTitle(); window?.makeFirstResponder(nil) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
#endif
