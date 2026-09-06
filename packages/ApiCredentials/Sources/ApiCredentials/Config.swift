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

    /// Credential storage is UI-independent; the application presents its native
    /// Telegram form before creating network/account objects.
    public static func ensurePersonalCredentials() -> Bool { credentials != nil }
    public static func storePersonalCredentials(id: String, hash: String) -> String? {
        precondition(Thread.isMainThread)
        let zh = (Locale.preferredLanguages.first ?? "en").hasPrefix("zh")
        let parsedId = Int32(id.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let parsedHash = hash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard validCredentials(id: parsedId, hash: parsedHash) else {
            return zh ? "请检查 API ID（正整数）和 API Hash（32 位十六进制）。" : "Use a positive API ID and a 32-character hexadecimal API Hash."
        }
        let value = Credentials(id: parsedId, hash: parsedHash)
        guard let data = try? JSONEncoder().encode(value) else { return "Unable to encode credentials." }
        var status = SecItemUpdate(keychainQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var query = keychainQuery
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(query as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            return zh ? "无法写入钥匙串（\(status)）。请先解锁登录钥匙串后重试。" : "Keychain error \(status). Unlock your login keychain and try again."
        }
        cachedCredentials = value
        return nil
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



