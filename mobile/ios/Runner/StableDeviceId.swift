// =========================================================================
// HR Pro v6.0 - معرّف جهاز ثابت لقفل الجهاز الواحد
// =========================================================================
// يُحفظ في Keychain فيبقى ثابتاً بعد حذف التطبيق وإعادة تثبيته
// (بعكس SharedPreferences و identifierForVendor).
// =========================================================================

import Foundation
import Security

enum StableDeviceId {
  private static let service = "com.batra.hrpro.device"
  private static let account = "stable_device_id"

  static func get() -> String {
    if let existing = read() {
      return existing
    }
    let id = "ios-" + UUID().uuidString.lowercased()
    save(id)
    return id
  }

  private static func read() -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
          let data = item as? Data
    else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  private static func save(_ id: String) {
    let attributes: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecValueData as String: Data(id.utf8),
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    SecItemAdd(attributes as CFDictionary, nil)
  }
}
