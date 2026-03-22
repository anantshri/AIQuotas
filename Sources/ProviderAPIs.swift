import Foundation

enum WebAPIError: Error, LocalizedError {
    case invalidURL
    case requestFailed(String)
    case unauthenticated
    case noData
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .requestFailed(let msg): return msg
        case .unauthenticated: return "Authentication failed — token may be expired"
        case .noData: return "No usage data returned"
        }
    }
}

class ProviderAPIs {
    static let shared = ProviderAPIs()
    private let urlSession: URLSession
    
    /// Result type: either real quota windows or a status message
    enum QuotaResult {
        case windows([QuotaWindow])
        case message(String)
    }
    
    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        self.urlSession = URLSession(configuration: config)
    }
    
    // MARK: - OpenRouter (API Key)
    // Real endpoint: GET https://openrouter.ai/api/v1/auth/key
    // Response: { data: { limit, usage } } (dollar amounts)
    
    func fetchOpenRouterQuota(apiKey: String) async throws -> QuotaResult {
        guard let url = URL(string: "https://openrouter.ai/api/v1/auth/key") else { throw WebAPIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw WebAPIError.requestFailed("No response") }
        
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw WebAPIError.unauthenticated
        }
        guard httpResponse.statusCode == 200 else {
            throw WebAPIError.requestFailed("HTTP \(httpResponse.statusCode)")
        }
        
        struct OpenRouterResponse: Codable {
            struct DataInfo: Codable { let limit: Double?; let usage: Double? }
            let data: DataInfo
        }
        let decoded = try JSONDecoder().decode(OpenRouterResponse.self, from: data)
        
        let usage = decoded.data.usage ?? 0
        let limit = decoded.data.limit ?? 0
        
        if limit <= 0 {
            return .message("OpenRouter: No spending limit set. Usage: $\(String(format: "%.2f", usage))")
        }
        
        let usedPercent = (usage / limit) * 100.0
        return .windows([
            QuotaWindow(name: "Credits", usedPercent: min(usedPercent, 100), resetAt: nil)
        ])
    }
    
    // MARK: - DeepSeek (API Key)
    // Real endpoint: GET https://api.deepseek.com/user/balance
    // Response: { is_available, balance_infos: [{ currency, total_balance, granted_balance, topped_up_balance }] }
    
    func fetchDeepSeekBalance(apiKey: String) async throws -> QuotaResult {
        guard let url = URL(string: "https://api.deepseek.com/user/balance") else { throw WebAPIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw WebAPIError.requestFailed("No response") }
        
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw WebAPIError.unauthenticated
        }
        guard httpResponse.statusCode == 200 else {
            throw WebAPIError.requestFailed("HTTP \(httpResponse.statusCode)")
        }
        
        // Parse the balance response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WebAPIError.noData
        }
        
        let isAvailable = json["is_available"] as? Bool ?? false
        
        if let balanceInfos = json["balance_infos"] as? [[String: Any]], let first = balanceInfos.first {
            let totalBalance = parseDouble(first["total_balance"]) ?? 0
            let grantedBalance = parseDouble(first["granted_balance"]) ?? 0
            let toppedUpBalance = parseDouble(first["topped_up_balance"]) ?? 0
            
            // DeepSeek shows remaining balance, not usage percentage
            // We'll show it as a balance indicator
            let totalCredit = grantedBalance + toppedUpBalance
            let usedPercent: Double
            if totalCredit > 0 {
                usedPercent = max(0, ((totalCredit - totalBalance) / totalCredit) * 100.0)
            } else if totalBalance > 0 {
                usedPercent = 0  // has balance, unknown total
            } else {
                usedPercent = 100  // no balance
            }
            
            let windows = [
                QuotaWindow(name: "Balance: $\(String(format: "%.2f", totalBalance))", usedPercent: min(usedPercent, 100), resetAt: nil)
            ]
            
            if !isAvailable {
                return .message("DeepSeek: Balance insufficient ($\(String(format: "%.2f", totalBalance)))")
            }
            
            return .windows(windows)
        }
        
        return .message("DeepSeek: Connected but no balance data returned")
    }
    
    // MARK: - Claude Code (Auto-detect token from Keychain)
    // Real endpoint from OmniRoute: GET https://api.anthropic.com/api/oauth/usage
    // Headers: Authorization: Bearer {token}, anthropic-beta: oauth-2025-04-20, anthropic-version: 2023-06-01
    // Response: { five_hour: { utilization, resets_at }, seven_day: { utilization, resets_at } }
    
    func fetchClaudeCodeUsage(token: String) async throws -> QuotaResult {
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else { throw WebAPIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw WebAPIError.requestFailed("No response") }
        
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw WebAPIError.unauthenticated
        }
        guard httpResponse.statusCode == 200 else {
            throw WebAPIError.requestFailed("Claude API HTTP \(httpResponse.statusCode)")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WebAPIError.noData
        }
        
        var windows: [QuotaWindow] = []
        
        // five_hour window (session)
        if let fiveHour = json["five_hour"] as? [String: Any],
           let utilization = parseDouble(fiveHour["utilization"]) {
            // utilization = percentage USED (from OmniRoute: "utilization = % used")
            let resetAt = parseISO8601(fiveHour["resets_at"] as? String)
            windows.append(QuotaWindow(name: "Session (5h)", usedPercent: clamp(utilization, 0, 100), resetAt: resetAt))
        }
        
        // seven_day window (weekly)
        if let sevenDay = json["seven_day"] as? [String: Any],
           let utilization = parseDouble(sevenDay["utilization"]) {
            let resetAt = parseISO8601(sevenDay["resets_at"] as? String)
            windows.append(QuotaWindow(name: "Weekly (7d)", usedPercent: clamp(utilization, 0, 100), resetAt: resetAt))
        }
        
        // Model-specific weekly windows (seven_day_sonnet, seven_day_opus, etc.)
        for (key, value) in json {
            if key.hasPrefix("seven_day_") && key != "seven_day",
               let windowData = value as? [String: Any],
               let utilization = parseDouble(windowData["utilization"]) {
                let modelName = key.replacingOccurrences(of: "seven_day_", with: "")
                let resetAt = parseISO8601(windowData["resets_at"] as? String)
                windows.append(QuotaWindow(name: "Weekly \(modelName) (7d)", usedPercent: clamp(utilization, 0, 100), resetAt: resetAt))
            }
        }
        
        if windows.isEmpty {
            return .message("Claude Code: Connected but no quota windows returned")
        }
        
        return .windows(windows)
    }
    
    // MARK: - Codex / ChatGPT (Auto-detect token from ~/.codex/auth.json)
    // Real endpoint from OmniRoute: GET https://chatgpt.com/backend-api/wham/usage
    // Response: { rate_limit: { primary_window: { used_percent, reset_at }, secondary_window: { ... } } }
    
    func fetchCodexUsage(token: String) async throws -> QuotaResult {
        guard let url = URL(string: "https://chatgpt.com/backend-api/wham/usage") else { throw WebAPIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw WebAPIError.requestFailed("No response") }
        
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw WebAPIError.unauthenticated
        }
        guard httpResponse.statusCode == 200 else {
            throw WebAPIError.requestFailed("Codex API HTTP \(httpResponse.statusCode)")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WebAPIError.noData
        }
        
        var windows: [QuotaWindow] = []
        
        // Parse rate_limit → primary_window and secondary_window (from OmniRoute getCodexUsage)
        let rateLimit = json["rate_limit"] as? [String: Any] ?? [:]
        
        // Primary window (session / 5-hour)
        if let primaryWindow = rateLimit["primary_window"] as? [String: Any] {
            let usedPercent = parseDouble(primaryWindow["used_percent"]) ?? 0
            let resetAt = parseCodexResetTime(primaryWindow)
            windows.append(QuotaWindow(name: "Session", usedPercent: clamp(usedPercent, 0, 100), resetAt: resetAt))
        }
        
        // Secondary window (weekly)
        if let secondaryWindow = rateLimit["secondary_window"] as? [String: Any] {
            let usedPercent = parseDouble(secondaryWindow["used_percent"]) ?? 0
            let resetAt = parseCodexResetTime(secondaryWindow)
            windows.append(QuotaWindow(name: "Weekly", usedPercent: clamp(usedPercent, 0, 100), resetAt: resetAt))
        }
        
        // Code review rate limit (3rd window)
        if let codeReviewRateLimit = json["code_review_rate_limit"] as? [String: Any],
           let codeReviewWindow = codeReviewRateLimit["primary_window"] as? [String: Any] {
            let usedPercent = parseDouble(codeReviewWindow["used_percent"]) ?? 0
            let resetAt = parseCodexResetTime(codeReviewWindow)
            windows.append(QuotaWindow(name: "Code Review", usedPercent: clamp(usedPercent, 0, 100), resetAt: resetAt))
        }
        
        if windows.isEmpty {
            return .message("Codex: Connected but no usage data returned")
        }
        
        return .windows(windows)
    }
    
    // MARK: - OpenAI (API Key)
    // Tries GET /v1/organization/costs — requires admin API key
    
    func fetchOpenAIUsage(apiKey: String) async throws -> QuotaResult {
        // Try the organization costs endpoint
        guard let url = URL(string: "https://api.openai.com/v1/organization/costs?start_time=\(startOfMonthTimestamp())&limit=1") else {
            throw WebAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw WebAPIError.requestFailed("No response") }
        
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            return .message("OpenAI: API key lacks admin scope. Check platform.openai.com/usage for details.")
        }
        
        guard httpResponse.statusCode == 200 else {
            return .message("OpenAI: Usage API returned HTTP \(httpResponse.statusCode). Check platform.openai.com/usage")
        }
        
        // Parse cost data if available
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let results = json["data"] as? [[String: Any]] {
            var totalCost = 0.0
            for result in results {
                if let costs = result["results"] as? [[String: Any]] {
                    for cost in costs {
                        totalCost += parseDouble(cost["amount_cents"]) ?? 0
                    }
                }
            }
            totalCost = totalCost / 100.0 // cents to dollars
            return .message("OpenAI: $\(String(format: "%.2f", totalCost)) spent this month. See platform.openai.com for limits.")
        }
        
        return .message("OpenAI: Connected. Check platform.openai.com/usage for details.")
    }
    
    // MARK: - Antigravity (Google Cloud Code)
    
    func fetchAntigravityUsageLocal() async throws -> QuotaResult {
        return try await LocalAntigravityService.shared.fetchLocalUsage()
    }
    
    // MARK: - Helpers
    
    private func parseDouble(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let s = value as? String { return Double(s) }
        return nil
    }
    
    private func clamp(_ value: Double, _ lo: Double, _ hi: Double) -> Double {
        return max(lo, min(hi, value))
    }
    
    private func parseISO8601(_ string: String?) -> Date? {
        guard let string = string else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
    
    /// Codex reset_at is Unix timestamp in seconds; reset_after_seconds is relative
    private func parseCodexResetTime(_ window: [String: Any]) -> Date? {
        if let resetAt = parseDouble(window["reset_at"]), resetAt > 0 {
            return Date(timeIntervalSince1970: resetAt)
        }
        if let resetAfterSeconds = parseDouble(window["reset_after_seconds"]), resetAfterSeconds > 0 {
            return Date(timeIntervalSinceNow: resetAfterSeconds)
        }
        return nil
    }
    
    /// Returns Unix timestamp (seconds) for the start of the current month
    private func startOfMonthTimestamp() -> Int {
        let cal = Calendar.current
        let now = Date()
        let comps = cal.dateComponents([.year, .month], from: now)
        let startOfMonth = cal.date(from: comps) ?? now
        return Int(startOfMonth.timeIntervalSince1970)
    }
}
