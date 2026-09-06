// Player settings use Telegram's own grouped rows, navigation and modal forms.
// This file belongs to the application target, not the standalone logic package.
import Cocoa
import TGUIKit
import SwiftSignalKit
import ApiCredentials

enum PlayerSettingsPage: Equatable { case controls, shortcuts, windows }

/// A narrowly scoped editor route. Telegram's main-menu copy/paste actions can
/// otherwise target the chat window instead of the newly presented form.
private func installPlayerEditing(in controller: InputDataController) {
    var monitor: Any?
    controller.didAppear = { [weak controller] _ in
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak controller] event in
            guard let controller = controller, let window = controller.view.window,
                  !controller.view.isHiddenOrHasHiddenAncestor else { return event }
            return PlayerTextEditing.handle(event, in: window) ? nil : event
        }
    }
    controller.onDeinit = {
        if let monitor = monitor { NSEvent.removeMonitor(monitor) }
    }
}

func PlayerSettingsController(page: PlayerSettingsPage = .controls,
                              navigate: ((InputDataController) -> Void)? = nil,
                              store: PlayerSettingsStore = .shared) -> InputDataController {
    let values = ValuePromise(store.preferences, ignoreRepeated: true)
    let observer = NotificationCenter.default.addObserver(forName: PlayerSettingsStore.didChange,
        object: store, queue: .main) { _ in values.set(store.preferences) }
    weak var weakController: InputDataController?
    let navigateTo: (PlayerSettingsPage) -> Void = { next in
        let child = PlayerSettingsController(page: next, navigate: navigate, store: store)
        if let navigate = navigate { navigate(child) }
        else { weakController?.navigationController?.push(child) }
    }
    let signal = combineLatest(queue: .mainQueue(), values.get(), appearanceSignal) |> map { p, _ -> InputDataSignalValue in
        var entries: [InputDataEntry] = []
        var section: Int32 = 0
        var index: Int32 = 0
        func header(_ title: String) {
            entries.append(.sectionId(section, type: .normal)); section += 1
            entries.append(.desc(sectionId: section, index: index, text: .plain(title),
                                 data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
            index += 1
        }
        func note(_ text: String) {
            entries.append(.desc(sectionId: section, index: index, text: .plain(text),
                                 data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
            index += 1
        }
        func row(_ id: String, _ title: String, _ type: GeneralInteractedType,
                 _ viewType: GeneralViewType = .singleItem, action: (() -> Void)? = nil) {
            entries.append(.general(sectionId: section, index: index, value: .none, error: nil,
                identifier: InputDataIdentifier("player." + id), data: .init(name: title, color: theme.colors.text,
                type: type, viewType: viewType, action: action)))
            index += 1
        }
        func toggle(_ id: String, _ title: String, _ key: WritableKeyPath<PlayerPreferences, Bool>, _ type: GeneralViewType) {
            row(id, title, .switchable(p[keyPath: key]), type, action: { store.update { $0[keyPath: key].toggle() } })
        }
        func number(_ id: String, _ title: String, _ key: WritableKeyPath<PlayerPreferences, Double>,
                    _ range: ClosedRange<Double>, _ type: GeneralViewType) {
            row(id, title, .nextContext(String(format: "%.3g", p[keyPath: key])), type, action: {
                guard let window = weakController?.view.window as? Window else { return }
                showModal(with: PlayerNumberController(title: title, value: store.preferences[keyPath: key], range: range, updated: { value in
                    store.update { $0[keyPath: key] = value }
                }), for: window)
            })
        }
        func choice<T: Equatable>(_ id: String, _ title: String, _ current: T,
                                  _ options: [(T, String)], _ type: GeneralViewType, change: @escaping(T) -> Void) {
            let items = options.map { value, name -> ContextMenuItem in
                return ContextMenuItem(name, handler: { change(value) }, state: value == current ? .on : nil)
            }
            row(id, title, .contextSelector(options.first(where: { $0.0 == current })?.1 ?? "", items), type)
        }
        switch page {
        case .controls:
            header(playerText("播放", "Playback"))
            toggle("enabled", playerText("增强播放器控制", "Enhanced player controls"), \.enabled, .firstItem)
            choice("default", playerText("打开视频时", "Open videos in"), p.defaultPresentation,
                   [(.gallery, playerText("媒体浏览器", "Gallery")), (.detached, playerText("独立播放器", "Detached player")),
                    (.mini, playerText("迷你画中画", "Mini player"))], .lastItem) { mode in store.update { $0.defaultPresentation = mode } }
            note(playerText("使用同一播放会话切换窗口，不会重新打开视频。", "Window changes reuse the current playback session."))
            header(playerText("自定义", "Customize"))
            row("shortcuts", playerText("键盘快捷键", "Keyboard shortcuts"), .next, .firstItem, action: { navigateTo(.shortcuts) })
            row("windows", playerText("窗口与画中画", "Windows and picture in picture"), .next, .lastItem, action: { navigateTo(.windows) })
            header(playerText("快进与快退", "Seeking"))
            number("seek", playerText("普通步长（秒）", "Normal step (seconds)"), \.seekStep, 0.1...600, .firstItem)
            number("fine", playerText("精细步长（秒）", "Fine step (seconds)"), \.fineSeekStep, 0.1...600, .innerItem)
            number("large", playerText("大步长（秒）", "Large step (seconds)"), \.largeSeekStep, 0.1...3600, .lastItem)
            header(playerText("音量与倍速", "Volume and speed"))
            number("volume", playerText("音量步长（%）", "Volume step (%)"), \.volumeStep, 1...25, .firstItem)
            number("speed", playerText("倍速步长", "Speed step"), \.speedStep, 0.05...0.5, .innerItem)
            number("boost", playerText("按住时的临时倍速", "Temporary speed while holding"), \.temporarySpeed, 0.25...2.5, .innerItem)
            toggle("rememberSpeed", playerText("记住最后使用的倍速", "Remember playback speed"), \.rememberSpeed, .lastItem)
            header(playerText("鼠标与提示", "Mouse and feedback"))
            choice("scroll", playerText("滚轮 / 双指滚动", "Wheel / two-finger scroll"), p.scrollAction,
                   [(.volume, playerText("音量", "Volume")), (.seek, playerText("进度", "Seek")), (.none, playerText("不接管", "Disabled"))], .firstItem) { mode in store.update { $0.scrollAction = mode } }
            choice("double", playerText("双击视频", "Double-click video"), p.doubleClick,
                   [(.fullscreen, playerText("全屏", "Fullscreen")), (.playPause, playerText("播放 / 暂停", "Play / pause")),
                    (.regionalSeek, playerText("分区快进快退", "Regional seeking")), (.none, playerText("不接管", "Disabled"))], .innerItem) { mode in store.update { $0.doubleClick = mode } }
            toggle("osd", playerText("显示操作提示", "Show on-screen feedback"), \.showOSD, .lastItem)
        case .windows:
            header(playerText("独立播放器", "Detached player"))
            toggle("rememberWindow", playerText("记住窗口大小和位置", "Remember window size and position"), \.rememberWindow, .firstItem)
            toggle("top", playerText("默认置顶", "Keep on top by default"), \.detachedOnTop, .innerItem)
            toggle("spaces", playerText("显示在所有桌面", "Show on all Spaces"), \.detachedAllSpaces, .lastItem)
            note(playerText("关闭或最小化聊天窗口不会停止独立播放；关闭播放器暂停视频。", "Closing or minimizing the chat window does not stop playback. Closing the player pauses it."))
            header(playerText("迷你画中画", "Mini player"))
            toggle("miniTop", playerText("默认置顶", "Keep on top by default"), \.miniOnTop, .firstItem)
            toggle("miniSpaces", playerText("显示在所有桌面", "Show on all Spaces"), \.miniAllSpaces, .innerItem)
            toggle("snap", playerText("靠近角落时吸附", "Snap near screen corners"), \.snapToCorners, .lastItem)
            header(playerText("控制栏", "Controls"))
            number("hide", playerText("自动隐藏等待时间（秒）", "Auto-hide delay (seconds)"), \.controlsHideDelay, 0.5...15, .singleItem)
        case .shortcuts:
            header(playerText("键盘快捷键", "Keyboard shortcuts"))
            let actions = PlayerAction.allCases
            for (i, action) in actions.enumerated() {
                let viewType: GeneralViewType = i == 0 ? .firstItem : (i == actions.count - 1 ? .lastItem : .innerItem)
                let key = p.shortcuts[action.rawValue]?.display ?? playerText("未设置", "Unassigned")
                row(action.rawValue, action.title, .nextContext(key), viewType, action: {
                    guard let window = weakController?.view.window as? Window else { return }
                    showModal(with: PlayerShortcutRecorderController(action: action, store: store), for: window)
                })
            }
            note(playerText("点击录入。支持 Hyper 组合；仅播放器获得焦点时生效，不拦截文本编辑。", "Click to record, including Hyper combinations. Player shortcuts never intercept text editing."))
        }
        header(playerText("重置", "Reset"))
        row("reset", page == .shortcuts ? playerText("恢复默认快捷键", "Reset shortcuts") : playerText("恢复播放器默认设置", "Reset playback settings"), .none, .singleItem, action: {
            guard let window = weakController?.view.window as? Window else { return }
            verifyAlert_button(for: window, information: playerText("恢复默认设置？不会影响其他 Telegram 设置。", "Restore defaults? Other Telegram settings are unaffected."), successHandler: { _ in
                if page == .shortcuts { store.update { $0.shortcuts = PlayerPreferences.defaultShortcuts } }
                else { store.reset() }
            })
        })
        entries.append(.sectionId(section + 1, type: .normal))
        return InputDataSignalValue(entries: entries, animated: false)
    }
    let title: String
    switch page {
    case .controls: title = playerText("播放器", "Playback")
    case .shortcuts: title = playerText("键盘快捷键", "Keyboard shortcuts")
    case .windows: title = playerText("窗口与画中画", "Windows and picture in picture")
    }
    let controller = InputDataController(dataSignal: signal, title: title, hasDone: false)
    weakController = controller
    controller.onDeinit = { NotificationCenter.default.removeObserver(observer) }
    return controller
}

func showPlayerSettings(for window: Window, store: PlayerSettingsStore = .shared) {
    weak var modal: InputDataModalController?
    let controller = PlayerSettingsController(navigate: { next in
        next.leftModalHeader = ModalHeaderData(image: theme.icons.chatNavigationBack, handler: { modal?.pop(animated: true) })
        modal?.push(next, animated: true)
    }, store: store)
    let host = InputDataModalController(controller, size: NSSize(width: 520, height: 540))
    modal = host
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak host] in host?.close() })
    window.makeKeyAndOrderFront(nil)
    showModal(with: host, for: window)
}

private func PlayerNumberController(title: String, value: Double, range: ClosedRange<Double>, updated: @escaping(Double) -> Void) -> InputDataModalController {
    let identifier = InputDataIdentifier("player.number")
    let entries: [InputDataEntry] = [
        .sectionId(0, type: .normal),
        .input(sectionId: 1, index: 0, value: .string(String(format: "%.3g", value)), error: nil,
               identifier: identifier, mode: .plain, data: .init(viewType: .singleItem), placeholder: nil,
               inputPlaceholder: title, filter: { $0 }, limit: 20),
        .desc(sectionId: 1, index: 1, text: .plain(String(format: "%.3g – %.3g", range.lowerBound, range.upperBound)),
              data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)),
        .sectionId(2, type: .normal)
    ]
    let controller = InputDataController(dataSignal: .single(InputDataSignalValue(entries: entries)), title: title)
    installPlayerEditing(in: controller)
    let interactions = ModalInteractions(acceptTitle: strings().modalDone, accept: { [weak controller] in _ = controller?.returnKeyAction() }, singleButton: true)
    let modal = InputDataModalController(controller, modalInteractions: interactions, size: NSSize(width: 380, height: 160))
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modal] in modal?.close() })
    controller.validateData = { [weak modal] data in
        let text = (data[identifier]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard let number = Double(text), number.isFinite, range.contains(number) else {
            return .fail(.alert(playerText("请输入范围内的有效数字。", "Enter a valid number within the range.")))
        }
        updated(number)
        modal?.close()
        return .none
    }
    return modal
}

private final class PlayerShortcutRecorderView: View {
    private let key = TextView()
    private let help = TextView()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        key.isSelectable = false; help.isSelectable = false
        addSubview(key); addSubview(help)
        update(message: playerText("按下新的快捷键", "Press a new shortcut"))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func update(message: String) {
        backgroundColor = theme.colors.background
        let label = TextViewLayout(.initialize(string: message, color: theme.colors.text, font: .medium(.title)), alignment: .center)
        label.measure(width: frame.width - 40); key.update(label)
        let text = playerText("Esc 取消 · Delete 清除绑定\n可使用 ⌃ ⌥ ⇧ ⌘ 及 Hyper 组合", "Esc cancels · Delete clears the binding\nControl, Option, Shift, Command and Hyper supported")
        let desc = TextViewLayout(.initialize(string: text, color: theme.colors.grayText, font: .normal(.text)), alignment: .center)
        desc.measure(width: frame.width - 40); help.update(desc)
        needsLayout = true
    }
    override func layout() {
        super.layout()
        key.centerX(y: 22); help.centerX(y: 64)
    }
}

final class PlayerShortcutRecorderController: ModalViewController {
    private let action: PlayerAction
    private let store: PlayerSettingsStore
    init(action: PlayerAction, store: PlayerSettingsStore) {
        self.action = action; self.store = store
        super.init(frame: NSRect(x: 0, y: 0, width: 420, height: 125))
        bar = .init(height: 0)
    }
    override func viewClass() -> AnyClass { PlayerShortcutRecorderView.self }
    override var modalHeader: (left: ModalHeaderData?, center: ModalHeaderData?, right: ModalHeaderData?)? {
        return (ModalHeaderData(image: theme.icons.modalClose, handler: { [weak self] in self?.close() }), ModalHeaderData(title: action.title), nil)
    }
    override func viewDidLoad() { super.viewDidLoad(); readyOnce() }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        window?.makeFirstResponder(nil)
        window?.set(handler: { [weak self] event in self?.capture(event) ?? .rejected }, with: self, for: .All, priority: .supreme)
    }
    override func viewDidDisappear(_ animated: Bool) {
        window?.removeAllHandlers(for: self)
        super.viewDidDisappear(animated)
    }
    func capture(_ event: NSEvent) -> KeyHandlerResult {
        if event.keyCode == 53 { close(); return .invoked }
        let shortcut = PlayerShortcut(event.keyCode, event.modifierFlags.rawValue)
        if event.keyCode == 51 && shortcut.modifiers == 0 {
            store.update { $0.shortcuts.removeValue(forKey: action.rawValue) }
            close(); return .invoked
        }
        let problem: String?
        if shortcut.isReserved { problem = playerText("此组合保留给系统", "Reserved system shortcut") }
        else if let conflict = store.preferences.conflict(for: shortcut, except: action) { problem = playerText("已用于：", "Assigned to: ") + conflict.title }
        else { problem = nil }
        if let problem = problem {
            (view as? PlayerShortcutRecorderView)?.update(message: problem)
        } else {
            store.update { $0.shortcuts[action.rawValue] = shortcut }
            close()
        }
        return .invoked
    }
}

/// Before account initialization, use the same themed form as the rest of the
/// app instead of NSAlert accessory fields with a broken main-menu responder.
func showPlayerCredentials(for window: Window, completed: @escaping() -> Void) {
    let id = InputDataIdentifier("player.api.id")
    let hash = InputDataIdentifier("player.api.hash")
    let entries: [InputDataEntry] = [
        .sectionId(0, type: .normal),
        .desc(sectionId: 1, index: 0, text: .plain(playerText("仅保存在这台 Mac 的钥匙串中，不会发送到 GitHub。", "Stored only in this Mac's Keychain, never sent to GitHub.")), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)),
        .input(sectionId: 1, index: 1, value: .string(""), error: nil, identifier: id, mode: .plain, data: .init(viewType: .firstItem), placeholder: InputDataInputPlaceholder("API ID"), inputPlaceholder: "12345678", filter: { $0 }, limit: 15),
        .input(sectionId: 1, index: 2, value: .string(""), error: nil, identifier: hash, mode: .secure, data: .init(viewType: .lastItem), placeholder: InputDataInputPlaceholder("API Hash"), inputPlaceholder: playerText("32 位十六进制字符串", "32 hexadecimal characters"), filter: { $0 }, limit: 64),
        .sectionId(2, type: .normal)
    ]
    let controller = InputDataController(dataSignal: .single(InputDataSignalValue(entries: entries)), title: playerText("配置 Telegram API", "Telegram API application"))
    installPlayerEditing(in: controller)
    let interactions = ModalInteractions(acceptTitle: playerText("保存并继续", "Save and continue"), accept: { [weak controller] in _ = controller?.returnKeyAction() }, singleButton: true)
    let modal = InputDataModalController(controller, modalInteractions: interactions, size: NSSize(width: 440, height: 200))
    modal.closableImpl = { false }
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { NSApp.terminate(nil) })
    controller.validateData = { [weak modal] data in
        if let error = ApiEnvironment.storePersonalCredentials(id: data[id]?.stringValue ?? "", hash: data[hash]?.stringValue ?? "") {
            return .fail(.alert(error))
        }
        modal?.close()
        DispatchQueue.main.async { completed() }
        return .none
    }
    window.makeKeyAndOrderFront(nil)
    showModal(with: modal, for: window)
}
