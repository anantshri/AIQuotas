import SwiftUI
import Combine

enum AuthMethod: String, Codable, CaseIterable, Identifiable {
    case apiKey = "API Key"
    case autoDetect = "Auto-Detect"
    var id: String { self.rawValue }
}

enum ProviderType: String, Codable, CaseIterable, Identifiable {
    case claudeCode = "Claude Code"
    case codex = "Codex (ChatGPT)"
    case openrouter = "OpenRouter"
    case deepseek = "DeepSeek"
    case openai = "OpenAI"
    case anthropic = "Anthropic"
    case antigravity = "Antigravity"
    var id: String { self.rawValue }
    
    /// Which auth methods are valid for this provider
    var supportedAuthMethods: [AuthMethod] {
        switch self {
        case .claudeCode, .codex, .antigravity:
            return [.autoDetect]
        case .openrouter, .deepseek, .openai, .anthropic:
            return [.apiKey]
        }
    }
    
    /// Default auth method for new accounts
    var defaultAuthMethod: AuthMethod {
        return supportedAuthMethods.first!
    }
}

struct QuotaWindow: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String          // e.g. "session (5h)", "weekly (7d)", "balance"
    var usedPercent: Double   // 0-100
    var resetAt: Date?
}

struct ProviderModel: Identifiable, Codable {
    var id = UUID()
    var label: String
    var providerType: ProviderType
    var authMethod: AuthMethod
    var apiKey: String
    
    // Real quota data
    var quotaWindows: [QuotaWindow] = []
    var statusMessage: String?
    var lastFetchedAt: Date?
    
    var isConfigured: Bool {
        switch authMethod {
        case .apiKey: return !apiKey.isEmpty
        case .autoDetect: return true
        }
    }
    
    /// Overall health: worst window, or 100 if no windows
    var worstUsedPercent: Double {
        guard !quotaWindows.isEmpty else { return 0 }
        return quotaWindows.map { $0.usedPercent }.max() ?? 0
    }
    
    /// For the progress bar: remaining fraction (0-1)
    var remainingFraction: Double {
        guard !quotaWindows.isEmpty else { return 1.0 }
        return max(0, min(1, (100 - worstUsedPercent) / 100.0))
    }
}

class QuotaManager: ObservableObject {
    @Published var providers: [ProviderModel] = [] {
        didSet {
            debouncedSaveToKeychain()
        }
    }
    
    private var pendingSaveTask: Task<Void, Never>?
    
    private func debouncedSaveToKeychain() {
        pendingSaveTask?.cancel()
        pendingSaveTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            if !Task.isCancelled {
                saveToKeychain()
            }
        }
    }
    
    var overallHealthIcon: String {
        let icon = calculateHealthIcon()
        // If the icon changed, notify listeners
        if icon != lastHealthIcon {
            NotificationCenter.default.post(name: NSNotification.Name("QuotaHealthChanged"), object: nil)
            lastHealthIcon = icon
        }
        return icon
    }
    
    private var lastHealthIcon = "chart.bar.fill"
    
    private func calculateHealthIcon() -> String {
        let worst = providers.filter { !$0.quotaWindows.isEmpty }.map { $0.worstUsedPercent }.max() ?? 0
        if worst > 90 {
            return "exclamationmark.triangle.fill"
        } else {
            return "chart.bar.fill"
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        loadFromKeychain()
        
        if providers.isEmpty {
            // Start with auto-detected providers if tokens exist
            var defaults: [ProviderModel] = []
            if AuthTokenDetector.detectClaudeToken() != nil {
                defaults.append(ProviderModel(label: "Claude Code", providerType: .claudeCode, authMethod: .autoDetect, apiKey: ""))
            }
            if AuthTokenDetector.detectCodexToken() != nil {
                defaults.append(ProviderModel(label: "Codex (ChatGPT)", providerType: .codex, authMethod: .autoDetect, apiKey: ""))
            }
            if LocalAntigravityService.shared.isProcessRunning() {
                defaults.append(ProviderModel(label: "Antigravity", providerType: .antigravity, authMethod: .autoDetect, apiKey: ""))
            }
            if defaults.isEmpty {
                // Add a placeholder so the user sees something in settings
                defaults.append(ProviderModel(label: "OpenRouter", providerType: .openrouter, authMethod: .apiKey, apiKey: ""))
            }
            providers = defaults
        }
        
        refreshQuotas()
        
        Timer.publish(every: 600, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshQuotas()
            }
            .store(in: &cancellables)
    }
    
    private func saveToKeychain() {
        if let data = try? JSONEncoder().encode(providers) {
            KeychainHelper.standard.save(data, service: "AIQuotaApp", account: "ProvidersV2")
        }
    }
    
    private func loadFromKeychain() {
        if let data = KeychainHelper.standard.read(service: "AIQuotaApp", account: "ProvidersV2"),
           let decoded = try? JSONDecoder().decode([ProviderModel].self, from: data) {
            self.providers = decoded
        }
    }
    
    @Published var isRefreshing = false
    
    func refreshQuotas() {
        guard !isRefreshing else { return }
        isRefreshing = true
        
        Task {
            for i in 0..<providers.count {
                let p = providers[i]
                guard p.isConfigured else { continue }
                
                var activeToken = ""
                
                if p.authMethod == .apiKey {
                    activeToken = p.apiKey
                } else if p.authMethod == .autoDetect {
                    if p.providerType == .codex {
                        activeToken = AuthTokenDetector.detectCodexToken() ?? ""
                    } else if p.providerType == .claudeCode {
                        activeToken = AuthTokenDetector.detectClaudeToken() ?? ""
                    }
                }
                
                // For Antigravity, we use local detection which doesn't need a token
                if activeToken.isEmpty && p.providerType != .antigravity {
                    await MainActor.run {
                        if i < self.providers.count {
                            self.providers[i].statusMessage = "Token not found. Check local config files."
                        }
                    }
                    continue
                }
                
                do {
                    var result: ProviderAPIs.QuotaResult
                    
                    switch p.providerType {
                    case .claudeCode:
                        result = try await ProviderAPIs.shared.fetchClaudeCodeUsage(token: activeToken)
                    case .codex:
                        result = try await ProviderAPIs.shared.fetchCodexUsage(token: activeToken)
                    case .openrouter:
                        result = try await ProviderAPIs.shared.fetchOpenRouterQuota(apiKey: activeToken)
                    case .deepseek:
                        result = try await ProviderAPIs.shared.fetchDeepSeekBalance(apiKey: activeToken)
                    case .openai:
                        result = try await ProviderAPIs.shared.fetchOpenAIUsage(apiKey: activeToken)
                    case .anthropic:
                        result = .message("Anthropic API keys don't expose usage data. Check console.anthropic.com")
                    case .antigravity:
                        do {
                            // Only local extraction (works if IDE is running)
                            result = try await ProviderAPIs.shared.fetchAntigravityUsageLocal()
                        } catch {
                            throw WebAPIError.requestFailed("Antigravity IDE not found or not running. Open the IDE to track usage.")
                        }
                    }
                    
                    let finalResult = result
                    let finalNowAt = Date()
                    await MainActor.run {
                        if i < self.providers.count {
                            switch finalResult {
                            case .windows(let windows):
                                self.providers[i].quotaWindows = windows
                                self.providers[i].statusMessage = nil
                            case .message(let msg):
                                self.providers[i].statusMessage = msg
                            }
                            self.providers[i].lastFetchedAt = finalNowAt
                        }
                    }
                } catch {
                    await MainActor.run {
                        if i < self.providers.count {
                            self.providers[i].statusMessage = "Error: \(error.localizedDescription)"
                            self.providers[i].lastFetchedAt = Date()
                        }
                    }
                }
            }
            
            await MainActor.run {
                self.isRefreshing = false
            }
        }
    }
}
}
