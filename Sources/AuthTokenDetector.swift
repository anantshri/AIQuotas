import Foundation

class AuthTokenDetector {
    
    struct CodexAuth: Codable {
        let token: String?
        let apiKey: String?
        let access_token: String?
        let session_token: String?
    }
    
    struct ClaudeOAuth: Codable {
        struct OAuthData: Codable {
            let accessToken: String?
        }
        let claudeAiOauth: OAuthData?
    }
    
    private static var cachedClaudeToken: String?
    private static var lastClaudeDetection: Date?
    
    static func detectCodexToken() -> String? {
        let path = NSHomeDirectory() + "/.codex/auth.json"
        
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        
        // Try to decode varying JSON structures
        if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
            if let tokens = json["tokens"] as? [String: Any] {
                return (tokens["access_token"] as? String) ?? (tokens["session_token"] as? String)
            }
            return (json["session_token"] as? String) ?? 
                   (json["token"] as? String) ?? 
                   (json["access_token"] as? String) ??
                   (json["OPENAI_API_KEY"] as? String)
        }
        
        return nil
    }
    
    static func detectClaudeToken() -> String? {
        // Cache detection for 60 seconds to avoid prompt spam
        if let cached = cachedClaudeToken, let last = lastClaudeDetection, Date().timeIntervalSince(last) < 60 {
            return cached
        }
        
        // Only try Keychain (Modern Claude Code storage)
        if let data = KeychainHelper.standard.read(service: "Claude Code-credentials") {
            var token: String?
            
            if let oauth = try? JSONDecoder().decode(ClaudeOAuth.self, from: data) {
                token = oauth.claudeAiOauth?.accessToken
            }
            
            // Fallback for flat JSON in keychain if any
            if token == nil, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let oauth = json["claudeAiOauth"] as? [String: Any] {
                    token = oauth["accessToken"] as? String
                } else {
                    token = json["accessToken"] as? String ?? json["sessionKey"] as? String
                }
            }
            
            if let foundToken = token {
                cachedClaudeToken = foundToken
                lastClaudeDetection = Date()
                return foundToken
            }
        }
        
        return nil
    }
}
