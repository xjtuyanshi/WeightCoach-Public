import Foundation
import Security

/// 当前版本不再使用客户端 Claude API。升级后一次性移除旧版本遗留的钥匙串凭据。
enum LegacyCredentialCleaner {
    private static let cleanupMarker = "legacyClaudeCredentialRemoved.v1"
    private static let service = "com.lukegogogo.WeightCoach"
    private static let account = "anthropic-api-key"

    static func removeDeprecatedClaudeKeyIfNeeded(
        defaults: UserDefaults = .standard
    ) {
        guard !defaults.bool(forKey: cleanupMarker) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { return }
        defaults.set(true, forKey: cleanupMarker)
    }
}
