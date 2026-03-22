import Foundation
import Security

class KeychainHelper {
    static let standard = KeychainHelper()
    
    private init() {}
    
    func save(_ data: Data, service: String, account: String) {
        let query = [
            kSecValueData: data,
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ] as CFDictionary
        
        // Add data in keychain to get the status.
        let status = SecItemAdd(query, nil)
        
        if status == errSecDuplicateItem {
            // Item already exist, thus update it.
            let query = [
                kSecAttrService: service,
                kSecAttrAccount: account,
                kSecClass: kSecClassGenericPassword
            ] as CFDictionary
            
            let attributesToUpdate = [kSecValueData: data] as CFDictionary
            
            SecItemUpdate(query, attributesToUpdate)
        }
    }
    
    func read(service: String, account: String? = nil) -> Data? {
        var query: [String: Any] = [
            kSecAttrService as String: service,
            kSecClass as String: kSecClassGenericPassword,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        if let account = account {
            query[kSecAttrAccount as String] = account
        }
        
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        
        return (result as? Data)
    }
    
    func delete(service: String, account: String? = nil) {
        var query: [String: Any] = [
            kSecAttrService as String: service,
            kSecClass as String: kSecClassGenericPassword
        ]
        
        if let account = account {
            query[kSecAttrAccount as String] = account
        }
        
        SecItemDelete(query as CFDictionary)
    }
}
