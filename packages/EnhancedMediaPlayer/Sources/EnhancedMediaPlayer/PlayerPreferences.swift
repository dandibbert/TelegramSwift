import Foundation

public enum PlayerAction: String, Codable, CaseIterable {
    case playPause, seekBackward, seekForward, fineBackward, fineForward, largeBackward, largeForward
    case volumeDown, volumeUp, mute, speedDown, speedUp, resetSpeed, temporarySpeed
    case fullscreen, pictureInPicture, detach, pin, previous, next, settings, escape

    public var repeats: Bool {
        switch self {
        case .seekBackward, .seekForward, .fineBackward, .fineForward, .largeBackward, .largeForward,
             .volumeDown, .volumeUp, .speedDown, .speedUp: return true
        default: return false
        }
    }

    public var title: String {
        switch self {
        case .playPause: return playerText("播放 / 暂停", "Play / Pause")
        case .seekBackward: return playerText("后退", "Seek backward")
        case .seekForward: return playerText("前进", "Seek forward")
        case .fineBackward: return playerText("小步后退", "Fine seek backward")
        case .fineForward: return playerText("小步前进", "Fine seek forward")
        case .largeBackward: return playerText("大步后退", "Large seek backward")
        case .largeForward: return playerText("大步前进", "Large seek forward")
        case .volumeDown: return playerText("减小音量", "Volume down")
        case .volumeUp: return playerText("增大音量", "Volume up")
        case .mute: return playerText("静音 / 恢复", "Mute / Unmute")
        case .speedDown: return playerText("降低倍速", "Decrease speed")
        case .speedUp: return playerText("提高倍速", "Increase speed")
        case .resetSpeed: return playerText("恢复 1×", "Reset to 1×")
        case .temporarySpeed: return playerText("按住临时倍速", "Hold for temporary speed")
        case .fullscreen: return playerText("全屏", "Fullscreen")
        case .pictureInPicture: return playerText("迷你画中画", "Mini player")
        case .detach: return playerText("独立播放器 / 返回", "Detach / Return to gallery")
        case .pin: return playerText("播放器置顶", "Keep player on top")
        case .previous: return playerText("上一个媒体（浏览器内）", "Previous media (gallery)")
        case .next: return playerText("下一个媒体（浏览器内）", "Next media (gallery)")
        case .settings: return playerText("播放器设置", "Playback settings")
        case .escape: return playerText("退出当前播放器层级", "Exit current player layer")
        }
    }
}

public func playerText(_ chinese: String, _ english: String) -> String {
    return (Locale.preferredLanguages.first ?? "en").hasPrefix("zh") ? chinese : english
}

/// Store physical key codes and exactly the four assignable modifiers. Caps Lock,
/// Fn and numeric-pad bits must not change shortcut matching (arrows set those bits).
public struct PlayerShortcut: Codable, Equatable, Hashable {
    public static let shift: UInt = 1 << 17
    public static let control: UInt = 1 << 18
    public static let option: UInt = 1 << 19
    public static let command: UInt = 1 << 20
    public static let modifierMask = shift | control | option | command
    public var keyCode: UInt16
    public var modifiers: UInt
    public init(_ keyCode: UInt16, _ modifiers: UInt = 0) {
        self.keyCode = keyCode
        self.modifiers = modifiers & Self.modifierMask
    }
    public var normalized: PlayerShortcut { PlayerShortcut(keyCode, modifiers) }
    public var isReserved: Bool {
        // Leave the OS's quit, application switcher and spotlight escape hatches alone.
        return (keyCode == 12 && modifiers & Self.command != 0)
            || (keyCode == 48 && modifiers & Self.command != 0)
            || (keyCode == 49 && modifiers & Self.command != 0)
    }
    public var display: String {
        var text = ""
        if modifiers & Self.control != 0 { text += "⌃" }
        if modifiers & Self.option != 0 { text += "⌥" }
        if modifiers & Self.shift != 0 { text += "⇧" }
        if modifiers & Self.command != 0 { text += "⌘" }
        let labels: [UInt16: String] = [
            0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",
            12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",
            22:"6",23:"5",24:"=",25:"9",26:"7",27:"−",28:"8",29:"0",30:"]",31:"O",
            32:"U",33:"[",34:"I",35:"P",36:"↩",37:"L",38:"J",39:"'",40:"K",41:";",
            42:"\\",43:",",44:"/",45:"N",46:"M",47:".",48:"⇥",49:"Space",50:"`",51:"⌫",
            53:"Esc",65:"Keypad .",67:"Keypad *",69:"Keypad +",75:"Keypad /",76:"Keypad ↩",
            78:"Keypad −",82:"Keypad 0",83:"Keypad 1",84:"Keypad 2",85:"Keypad 3",
            86:"Keypad 4",87:"Keypad 5",88:"Keypad 6",89:"Keypad 7",91:"Keypad 8",92:"Keypad 9",
            96:"F5",97:"F6",98:"F7",99:"F3",100:"F8",101:"F9",103:"F11",109:"F10",
            111:"F12",115:"Home",116:"Page Up",117:"⌦",118:"F4",119:"End",120:"F2",
            121:"Page Down",122:"F1",123:"←",124:"→",125:"↓",126:"↑"
        ]
        return text + (labels[keyCode] ?? "Key \(keyCode)")
    }
}

public enum PlayerScrollAction: String, Codable, CaseIterable { case volume, seek, none }
public enum PlayerDoubleClick: String, Codable, CaseIterable { case fullscreen, playPause, regionalSeek, none }
public enum PlayerPresentation: String, Codable, CaseIterable { case gallery, detached, mini }

public struct PlayerPreferences: Codable, Equatable {
    public var enabled = true
    public var seekStep: Double = 5
    public var fineSeekStep: Double = 1
    public var largeSeekStep: Double = 30
    public var volumeStep: Double = 5
    public var speedStep: Double = 0.1
    public var temporarySpeed: Double = 2
    public var rememberSpeed = true
    public var showOSD = true
    public var scrollAction = PlayerScrollAction.volume
    public var doubleClick = PlayerDoubleClick.fullscreen
    public var defaultPresentation = PlayerPresentation.gallery
    public var rememberWindow = true
    public var detachedOnTop = false
    public var miniOnTop = true
    public var miniAllSpaces = true
    public var detachedAllSpaces = false
    public var snapToCorners = true
    public var controlsHideDelay: Double = 2.5
    public var shortcuts: [String: PlayerShortcut] = defaultShortcuts

    public init() {}
    public static var defaultShortcuts: [String: PlayerShortcut] {
        let shift = PlayerShortcut.shift, option = PlayerShortcut.option, command = PlayerShortcut.command
        return [
            PlayerAction.playPause.rawValue: .init(49),
            PlayerAction.seekBackward.rawValue: .init(123), PlayerAction.seekForward.rawValue: .init(124),
            PlayerAction.fineBackward.rawValue: .init(123, command), PlayerAction.fineForward.rawValue: .init(124, command),
            PlayerAction.largeBackward.rawValue: .init(123, shift), PlayerAction.largeForward.rawValue: .init(124, shift),
            PlayerAction.volumeDown.rawValue: .init(125), PlayerAction.volumeUp.rawValue: .init(126),
            PlayerAction.mute.rawValue: .init(46), PlayerAction.speedDown.rawValue: .init(33),
            PlayerAction.speedUp.rawValue: .init(30), PlayerAction.resetSpeed.rawValue: .init(42),
            PlayerAction.temporarySpeed.rawValue: .init(48), PlayerAction.fullscreen.rawValue: .init(3),
            PlayerAction.pictureInPicture.rawValue: .init(35), PlayerAction.detach.rawValue: .init(2),
            PlayerAction.pin.rawValue: .init(17), PlayerAction.previous.rawValue: .init(123, option),
            PlayerAction.next.rawValue: .init(124, option), PlayerAction.settings.rawValue: .init(43, command),
            PlayerAction.escape.rawValue: .init(53)
        ]
    }
    public func action(for shortcut: PlayerShortcut) -> PlayerAction? {
        return PlayerAction.allCases.first { shortcuts[$0.rawValue]?.normalized == shortcut.normalized }
    }
    public func conflict(for shortcut: PlayerShortcut, except action: PlayerAction) -> PlayerAction? {
        return PlayerAction.allCases.first { $0 != action && shortcuts[$0.rawValue]?.normalized == shortcut.normalized }
    }
    public mutating func normalize() {
        func bounded(_ x: Double, _ fallback: Double, _ range: ClosedRange<Double>) -> Double {
            return x.isFinite ? min(range.upperBound, max(range.lowerBound, x)) : fallback
        }
        seekStep = bounded(seekStep, 5, 0.1...600)
        fineSeekStep = bounded(fineSeekStep, 1, 0.1...600)
        largeSeekStep = bounded(largeSeekStep, 30, 0.1...3600)
        volumeStep = bounded(volumeStep, 5, 1...25)
        speedStep = bounded(speedStep, 0.1, 0.05...0.5)
        temporarySpeed = bounded(temporarySpeed, 2, 0.25...2.5)
        controlsHideDelay = bounded(controlsHideDelay, 2.5, 0.5...15)
        var used = Set<PlayerShortcut>()
        var result: [String: PlayerShortcut] = [:]
        for action in PlayerAction.allCases {
            if let shortcut = shortcuts[action.rawValue]?.normalized,
               !shortcut.isReserved, used.insert(shortcut).inserted {
                result[action.rawValue] = shortcut
            }
        }
        shortcuts = result
    }
    /// Merge schema defaults without restoring deliberately unbound shortcuts.
    public static func decode(_ data: Data) -> PlayerPreferences {
        guard var raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let defaults = try? JSONEncoder().encode(Self()),
              let base = (try? JSONSerialization.jsonObject(with: defaults)) as? [String: Any] else { return Self() }
        for (key, value) in base where raw[key] == nil { raw[key] = value }
        guard let merged = try? JSONSerialization.data(withJSONObject: raw),
              var result = try? JSONDecoder().decode(Self.self, from: merged) else { return Self() }
        result.normalize()
        return result
    }
}

public final class PlayerSettingsStore {
    public static let shared = PlayerSettingsStore()
    public static let didChange = Notification.Name("EnhancedMediaPlayer.settingsChanged.v1")
    private let defaults: UserDefaults
    private let key = "EnhancedMediaPlayer.preferences.v1"
    public private(set) var preferences: PlayerPreferences
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preferences = defaults.data(forKey: key).map(PlayerPreferences.decode) ?? PlayerPreferences()
    }
    /// UI and player callbacks use this store only on the main thread.
    public func update(_ edit: (inout PlayerPreferences) -> Void) {
        precondition(Thread.isMainThread)
        var next = preferences
        edit(&next)
        next.normalize()
        guard let data = try? JSONEncoder().encode(next) else { return }
        preferences = next
        defaults.set(data, forKey: key)
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
    public func reset() { update { $0 = PlayerPreferences() } }
}

/// Pure seek planning: retain the requested position while a network seek is in
/// flight, instead of repeatedly adding to a stale playback status timestamp.
public struct PlayerSeekAccumulator {
    public private(set) var target: Double?
    private var lastInput: TimeInterval = -.infinity
    private var hasUncommittedTarget = false
    private var landingTolerance: Double = 0.35
    public init() {}
    public mutating func add(_ delta: Double, position: Double, duration: Double, now: TimeInterval) -> Double? {
        guard delta.isFinite, position.isFinite, duration.isFinite, duration > 0, now.isFinite else { return nil }
        let base = now - lastInput <= 3 ? (target ?? position) : position
        let next = min(duration, max(0, base + delta))
        target = next
        // Never acknowledge a fractional seek using an unchanged timestamp or
        // the previous seek's landing. A fixed 350 ms tolerance swallows the
        // supported 100 ms step before the backend has moved at all.
        landingTolerance = min(0.35, max(0.000001, min(abs(delta), abs(next - position)) * 0.5))
        lastInput = now
        hasUncommittedTarget = true
        return next
    }
    public mutating func take() -> Double? {
        guard hasUncommittedTarget else { return nil }
        hasUncommittedTarget = false
        return target
    }
    public mutating func observe(position: Double, now: TimeInterval) {
        guard !hasUncommittedTarget, let target = target else { return }
        if abs(position - target) < landingTolerance || now - lastInput > 3 { self.target = nil }
    }
    public mutating func reset() { self = Self() }
}

public func playerTimestamp(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max / 2) else { return "--:--" }
    let value = Int(seconds)
    return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, (value / 60) % 60, value % 60)
        : String(format: "%d:%02d", value / 60, value % 60)
}


/// One outstanding decoder seek, plus the latest user intent. A buffering status
/// often already contains the requested timestamp; it is NOT a seek completion.
/// First input is submitted immediately. Repeats update the HUD/target only until
/// a new seek generation has produced playable/paused media at the target.
public struct PlayerSeekPipeline {
    public private(set) var target: Double?
    private struct Flight {
        var target: Double
        var generation: Int
        var started: TimeInterval
        var tolerance: Double
    }
    private var flight: Flight?
    private var lastInput: TimeInterval = 0
    public init() {}
    public var isSeeking: Bool { flight != nil }
    public var hasQueuedTarget: Bool {
        guard let flight = flight, let target = target else { return false }
        return abs(target - flight.target) > 0.000001
    }
    public mutating func request(delta: Double, position: Double, duration: Double, generation: Int, now: TimeInterval) -> Double? {
        guard delta.isFinite else { return nil }
        return request(to: (target ?? position) + delta, position: position, duration: duration, generation: generation, now: now)
    }
    public mutating func request(to destination: Double, position: Double, duration: Double, generation: Int, now: TimeInterval) -> Double? {
        guard destination.isFinite, position.isFinite, duration.isFinite, duration > 0, now.isFinite else { return nil }
        let value = min(duration, max(0, destination))
        if target == nil && abs(value - position) < 0.000001 { return nil }
        target = value
        lastInput = now
        if flight == nil { return submit(position: position, generation: generation, now: now) }
        return nil
    }
    private mutating func submit(position: Double, generation: Int, now: TimeInterval) -> Double? {
        guard let value = target else { return nil }
        let tolerance = min(0.35, max(0.000001, abs(value - position) * 0.5))
        flight = Flight(target: value, generation: generation, started: now, tolerance: tolerance)
        return value
    }
    public mutating func observe(position: Double, generation: Int, buffering: Bool, now: TimeInterval) -> Double? {
        guard position.isFinite, let active = flight, !buffering,
              generation != active.generation, abs(position - active.target) < active.tolerance else { return nil }
        flight = nil
        if let value = target, abs(value - active.target) > 0.000001 {
            return submit(position: position, generation: generation, now: now)
        }
        target = nil
        return nil
    }
    /// A network seek can wait indefinitely on an obsolete segment. Supersede it
    /// only after 750 ms AND a 150 ms quiet period, never every keyboard repeat.
    /// This is not a repeating retry of an unchanged target.
    public mutating func advanceStalled(position: Double, generation: Int, now: TimeInterval) -> Double? {
        guard let active = flight, let value = target,
              abs(value - active.target) > 0.000001,
              now - active.started >= 0.75, now - lastInput >= 0.15 else { return nil }
        return submit(position: position, generation: generation, now: now)
    }
    public mutating func reset() { self = Self() }
}
