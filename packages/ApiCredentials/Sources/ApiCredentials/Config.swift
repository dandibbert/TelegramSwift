import Cocoa
import Security

public final class ApiEnvironment {
    // Personal builds never use Telegram's bundled test application credentials.
    // A single first-launch dialog stores the user's own API application in Keychain.
    private struct Credentials: Codable { let id: Int32; let hash: String }
    private static var cachedCredentials: Credentials?
    private static let credentialService = "io.github.dandibbert.TelegramPlayer.api"
    private static let credentialAccount = "telegram-api-application"

    public static var apiId: Int32 { credentials?.id ?? 0 }
    public static var apiHash: String { credentials?.hash ?? "" }
    public static var bundleId: String { "io.github.dandibbert.TelegramPlayer" }
    public static var intentsBundleId: String { bundleId + ".FocusIntents" }
    public static var teamId: String { "" }
    public static var group: String { bundleId }
    public static let isPersonalPlayerBuild = true

    private static var keychainQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: credentialService,
         kSecAttrAccount as String: credentialAccount]
    }
    private static var credentials: Credentials? {
        if let value = cachedCredentials { return value }
        var query = keychainQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = try? JSONDecoder().decode(Credentials.self, from: data),
              validCredentials(id: value.id, hash: value.hash) else { return nil }
        cachedCredentials = value
        return value
    }
    private static func validCredentials(id: Int32, hash: String) -> Bool {
        return id > 0 && hash.count == 32 && hash.unicodeScalars.allSatisfy {
            (48...57).contains($0.value) || (65...70).contains($0.value) || (97...102).contains($0.value)
        }
    }

    // Called on the main thread before creating any Telegram network/account objects.
    // No API hash is ever written to UserDefaults, a build log, or the repository.
    public static func ensurePersonalCredentials() -> Bool {
        precondition(Thread.isMainThread)
        if credentials != nil { return true }
        let zh = (Locale.preferredLanguages.first ?? "en").hasPrefix("zh")
        let alert = NSAlert()
        alert.messageText = zh ? "配置你的 Telegram API" : "Your Telegram API application"
        alert.informativeText = zh
            ? "填写你已申请的 API ID 和 API Hash。它们仅保存在这台 Mac 的钥匙串中，不会上传到 GitHub。这不是 Bot Token，也不需要提供给任何人。"
            : "Enter your API ID and API Hash. They are stored only in this Mac's Keychain, never in GitHub. These are not a bot token."
        alert.addButton(withTitle: zh ? "保存并继续" : "Save and Continue")
        alert.addButton(withTitle: zh ? "退出" : "Quit")
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 146))
        let idLabel = NSTextField(labelWithString: "API ID")
        idLabel.frame = NSRect(x: 0, y: 116, width: 90, height: 20)
        let idField = NSTextField(frame: NSRect(x: 94, y: 112, width: 306, height: 26))
        idField.placeholderString = "12345678"
        let hashLabel = NSTextField(labelWithString: "API Hash")
        hashLabel.frame = NSRect(x: 0, y: 77, width: 90, height: 20)
        let hashField = NSSecureTextField(frame: NSRect(x: 94, y: 72, width: 306, height: 26))
        hashField.placeholderString = zh ? "32 位十六进制字符串" : "32 hexadecimal characters"
        let errorLabel = NSTextField(wrappingLabelWithString: "")
        errorLabel.frame = NSRect(x: 0, y: 0, width: 400, height: 58)
        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.textColor = .systemRed
        [idLabel, idField, hashLabel, hashField, errorLabel].forEach { container.addSubview($0) }
        alert.accessoryView = container
        alert.window.initialFirstResponder = idField
        NSApp.activate(ignoringOtherApps: true)
        while alert.runModal() == .alertFirstButtonReturn {
            let id = Int32(idField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            let hash = hashField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard validCredentials(id: id, hash: hash) else {
                errorLabel.stringValue = zh ? "请检查 API ID（正整数）和 API Hash（32 位十六进制）。" : "Use a positive API ID and a 32-character hexadecimal API Hash."
                continue
            }
            let value = Credentials(id: id, hash: hash)
            guard let data = try? JSONEncoder().encode(value) else { return false }
            var status = SecItemUpdate(keychainQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if status == errSecItemNotFound {
                var query = keychainQuery
                query[kSecValueData as String] = data
                query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                status = SecItemAdd(query as CFDictionary, nil)
            }
            guard status == errSecSuccess else {
                errorLabel.stringValue = zh ? "无法写入钥匙串（\(status)）。请先解锁登录钥匙串后重试。" : "Keychain error \(status). Unlock your login keychain and try again."
                continue
            }
            cachedCredentials = value
            hashField.stringValue = ""
            return true
        }
        hashField.stringValue = ""
        return false
    }

    public static var containerURL: URL? {
        // Ad-hoc personal builds have no Apple app-group entitlement. Keep this
        // database completely separate from official Telegram and Telegram Lite.
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let url = root.appendingPathComponent("TelegramPlayer", isDirectory: true).appendingPathComponent(prefix, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            return url
        } catch { return nil }
    }
    public static var legacyContainerURL: URL? { nil }
    public static func migrate() { /* Never move or open another Telegram app's database. */ }

    public static var appData: Data {
        let apiData = evaluateApiData() ?? ""
        let dict:[String: String] = ["bundleId": bundleId, "data": apiData]
        return try! JSONSerialization.data(withJSONObject: dict, options: [])
    }
    public static var language: String {
        return "macos"
    }
    
    public static var prefixList:[String] {
        return ["debug", "stable", "appstore", "beta"]
    }
    
    public static var resolvedDeviceName:[String : String]? {
        if let file = Bundle.main.path(forResource: "mac_devices", ofType: "txt") {
            if let string = try? String(contentsOf: .init(fileURLWithPath: file)) {
                let lines = string.components(separatedBy: "\n\n")
                
                var result:[String : String] = [:]
                for line in lines {
                    let resolved = line.components(separatedBy: "\n")
                    if resolved.count == 2 {
                        result[resolved[1]] = resolved[0]
                    }
                }
                
                return result
            }
        }
        return nil
    }
    
    public static var prefix: String {
        var prefix: String = ""
        switch Configuration.value(for: .source) {
        case "DEBUG":
            prefix = "debug"
        case "STABLE":
            prefix = "stable"
        case "APP_STORE":
            prefix = "appstore"
        default:
            prefix = "beta"
        }
        return prefix
    }
    
    public static var version: String {
        var suffix: String = ""
        
        suffix = Configuration.value(for: .source) ?? "DEBUG"
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? ""
        return "\(shortVersion) \(suffix)"
    }
    
    public static var premiumProductId: String {
        return "org.telegram.telegramPremium.monthly"
    }
}



