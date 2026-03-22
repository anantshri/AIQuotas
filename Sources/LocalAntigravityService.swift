import Foundation

class LocalAntigravityService {
    static let shared = LocalAntigravityService()
    
    struct LocalProcessInfo {
        let pid: Int
        let csrfToken: String?
    }
    
    struct UserStatusResponse: Codable {
        struct UserStatus: Codable {
            let email: String?
            let isAuthenticated: Bool?
            let planStatus: PlanStatus?
            let cascadeModelConfigData: CascadeModelConfigData?
        }
        
        struct PlanStatus: Codable {
            let availablePromptCredits: Double?
            struct PlanInfo: Codable {
                let monthlyPromptCredits: Double?
            }
            let planInfo: PlanInfo?
        }
        
        struct CascadeModelConfigData: Codable {
            struct ClientModelConfig: Codable {
                struct ModelOrAlias: Codable {
                    let model: String?
                }
                struct QuotaInfo: Codable {
                    let remainingFraction: Double?
                    let resetTime: String?
                }
                let modelOrAlias: ModelOrAlias?
                let quotaInfo: QuotaInfo?
                let label: String?
            }
            let clientModelConfigs: [ClientModelConfig]?
        }
        
        let userStatus: UserStatus?
    }
    
    func isProcessRunning() -> Bool {
        return detectProcess() != nil
    }
    
    /// Main entry point to fetch local usage
    func fetchLocalUsage() async throws -> ProviderAPIs.QuotaResult {
        // 1. Detect process
        guard let processInfo = detectProcess() else {
            throw WebAPIError.requestFailed("Antigravity process not found")
        }
        
        // 2. Discover ports
        let ports = discoverPorts(pid: processInfo.pid)
        guard !ports.isEmpty else {
            throw WebAPIError.requestFailed("No listening ports found for Antigravity")
        }
        
        // 3. Probe ports to find the Connect API
        for port in ports {
            if let result = await fetchFromPort(port, csrfToken: processInfo.csrfToken) {
                return result
            }
        }
        
        throw WebAPIError.requestFailed("Could not connect to Antigravity API on any port")
    }
    
    private func detectProcess() -> LocalProcessInfo? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["aux"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }
            
            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                let lower = line.lowercased()
                if lower.contains("antigravity") && (lower.contains("language-server") || lower.contains("lsp")) {
                    // Extract PID
                    let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                    guard parts.count > 1, let pid = Int(parts[1]) else { continue }
                    
                    // Extract CSRF token
                    let csrfToken = extractArgument(line, name: "--csrf_token")
                    return LocalProcessInfo(pid: pid, csrfToken: csrfToken)
                }
            }
        } catch {
            return nil
        }
        return nil
    }
    
    private func extractArgument(_ line: String, name: String) -> String? {
        let pattern = "\(name)[=\\s]+([^\\s\"']+|\"[^\"]*\"|'[^']*')"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        if let match = regex.firstMatch(in: line, options: [], range: range) {
            if let argRange = Range(match.range(at: 1), in: line) {
                return String(line[argRange]).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }
        return nil
    }
    
    private func discoverPorts(pid: Int) -> [Int] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-p", "\(pid)"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return [] }
            
            var ports: [Int] = []
            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                // Look for :PORT (LISTEN)
                let pattern = ":(\\d+)\\s+\\(LISTEN\\)"
                guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                if let match = regex.firstMatch(in: line, options: [], range: range) {
                    if let portRange = Range(match.range(at: 1), in: line), let port = Int(line[portRange]) {
                        if !ports.contains(port) {
                            ports.append(port)
                        }
                    }
                }
            }
            return ports
        } catch {
            return []
        }
    }
    
    private func fetchFromPort(_ port: Int, csrfToken: String?) async -> ProviderAPIs.QuotaResult? {
        // Try both HTTPS and HTTP (like antigravity-usage does)
        let protocols = ["https", "http"]
        for proto in protocols {
            let url = URL(string: "\(proto)://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/GetUserStatus")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 2.0
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
            if let token = csrfToken {
                request.addValue(token, forHTTPHeaderField: "X-Codeium-Csrf-Token")
            }
            
            let body: [String: Any] = [
                "metadata": [
                    "ideName": "antigravity",
                    "extensionName": "antigravity",
                    "locale": "en"
                ]
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            
            // Allow self-signed certs for local server
            let config = URLSessionConfiguration.ephemeral
            let session = URLSession(configuration: config, delegate: UnsafeSessionDelegate(), delegateQueue: nil)
            
            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    continue
                }
                
                let decoder = JSONDecoder()
                let status = try decoder.decode(UserStatusResponse.self, from: data)
                
                return parseStatusResponse(status)
            } catch {
                continue
            }
        }
        return nil
    }
    
    private func parseStatusResponse(_ response: UserStatusResponse) -> ProviderAPIs.QuotaResult {
        guard let userStatus = response.userStatus else {
            return .message("Antigravity: No user status returned from local server")
        }
        
        var windows: [QuotaWindow] = []
        
        // 1. Credits
        if let planStatus = userStatus.planStatus {
            let available = planStatus.availablePromptCredits ?? 0
            if let monthly = planStatus.planInfo?.monthlyPromptCredits, monthly > 0 {
                let used = max(0, monthly - available)
                let percent = (used / monthly) * 100.0
                windows.append(QuotaWindow(name: "Credits (\(Int(available)) left)", usedPercent: clamp(percent, 0, 100), resetAt: nil))
            } else if available > 0 {
                windows.append(QuotaWindow(name: "Credits (\(Int(available)) available)", usedPercent: 0, resetAt: nil))
            }
        }
        
        // 2. Models
        if let modelConfigs = userStatus.cascadeModelConfigData?.clientModelConfigs {
            for config in modelConfigs {
                guard let modelId = config.modelOrAlias?.model,
                      let remainingFraction = config.quotaInfo?.remainingFraction else { continue }
                
                let usedPercent = (1.0 - remainingFraction) * 100.0
                let displayName = config.label ?? modelId
                let resetAt = parseISO8601(config.quotaInfo?.resetTime)
                
                windows.append(QuotaWindow(name: displayName, usedPercent: clamp(usedPercent, 0, 100), resetAt: resetAt))
            }
        }
        
        if windows.isEmpty {
            if let email = userStatus.email {
                return .message("Antigravity local: Connected as \(email)")
            }
            return .message("Antigravity local: Connected")
        }
        
        return .windows(windows)
    }
    
    private func clamp(_ value: Double, _ lo: Double, _ hi: Double) -> Double {
        return max(lo, min(hi, value))
    }
    
    private func parseISO8601(_ string: String?) -> Date? {
        guard let string = string else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

/// Helper to ignore SSL errors for local server
class UnsafeSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            // For 127.0.0.1, always trust
            if challenge.protectionSpace.host == "127.0.0.1" {
                completionHandler(.useCredential, URLCredential(trust: challenge.protectionSpace.serverTrust!))
                return
            }
        }
        completionHandler(.performDefaultHandling, nil)
    }
}
