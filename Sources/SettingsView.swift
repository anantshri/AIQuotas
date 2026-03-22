import SwiftUI

struct SettingsView: View {
    @ObservedObject var quotaManager: QuotaManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("AI Quota Configuration")
                    .font(.title2)
                    .bold()
                Spacer()
                Button(action: {
                    quotaManager.providers.append(ProviderModel(
                        label: "New Account",
                        providerType: .openrouter,
                        authMethod: .apiKey,
                        apiKey: ""
                    ))
                }) {
                    HStack {
                        Image(systemName: "plus")
                        Text("Add Account")
                    }
                }
            }
            
            Text("Only providers with real usage APIs are shown. Auto-detect reads tokens from local config files.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            ScrollView {
                VStack(spacing: 20) {
                    ForEach($quotaManager.providers) { $provider in
                        VStack(alignment: .leading, spacing: 12) {
                            // Header: label + delete
                            HStack {
                                TextField("Account Label", text: $provider.label)
                                    .font(.headline)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                Spacer()
                                Button(action: {
                                    quotaManager.providers.removeAll { $0.id == provider.id }
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            
                            // Provider type picker
                            Picker("Service", selection: $provider.providerType) {
                                ForEach(ProviderType.allCases) { type in
                                    Text(type.rawValue).tag(type)
                                }
                            }
                            .onChange(of: provider.providerType) { _, newType in
                                // Reset auth method to the provider's default
                                provider.authMethod = newType.defaultAuthMethod
                                provider.apiKey = ""
                                provider.quotaWindows = []
                                provider.statusMessage = nil
                            }
                            
                            // Auth method — only show supported methods
                            let supportedMethods = provider.providerType.supportedAuthMethods
                            if supportedMethods.count > 1 {
                                Picker("Auth Method", selection: $provider.authMethod) {
                                    ForEach(supportedMethods) { method in
                                        Text(method.rawValue).tag(method)
                                    }
                                }
                                .pickerStyle(SegmentedPickerStyle())
                            }
                            
                            // Auth-specific fields
                            if provider.authMethod == .apiKey {
                                SecureField(apiKeyPlaceholder(for: provider.providerType), text: $provider.apiKey)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            } else if provider.authMethod == .autoDetect {
                                HStack(spacing: 6) {
                                    Image(systemName: tokenDetected(for: provider.providerType) ? "checkmark.circle.fill" : "xmark.circle")
                                        .foregroundColor(tokenDetected(for: provider.providerType) ? .green : .orange)
                                    Text(autoDetectDescription(for: provider.providerType))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            // Status
                            if let msg = provider.statusMessage {
                                Text(msg)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding()
        .frame(width: 520, height: 600)
    }
    
    private func apiKeyPlaceholder(for type: ProviderType) -> String {
        switch type {
        case .openrouter: return "sk-or-..."
        case .deepseek: return "sk-..."
        case .openai: return "sk-... (admin key recommended)"
        case .anthropic: return "sk-ant-..."
        default: return "API key..."
        }
    }
    
    private func tokenDetected(for type: ProviderType) -> Bool {
        switch type {
        case .codex: return AuthTokenDetector.detectCodexToken() != nil
        case .claudeCode: return AuthTokenDetector.detectClaudeToken() != nil
        case .antigravity: 
            return LocalAntigravityService.shared.isProcessRunning()
        default: return false
        }
    }
    
    private func autoDetectDescription(for type: ProviderType) -> String {
        switch type {
        case .codex:
            let found = AuthTokenDetector.detectCodexToken() != nil
            return found ? "Connected to Codex" : "Codex credentials not found."
        case .claudeCode:
            let found = AuthTokenDetector.detectClaudeToken() != nil
            return found ? "Connected to Claude" : "Claude credentials not found."
        case .antigravity:
            if LocalAntigravityService.shared.isProcessRunning() {
                return "Connected to IDE instance"
            }
            return "Antigravity IDE not found. Open the IDE to track usage."
        default:
            return "Auto-detect not available for this provider"
        }
    }
}
