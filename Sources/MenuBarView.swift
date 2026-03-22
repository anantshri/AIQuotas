import SwiftUI

struct MenuBarView: View {
    @ObservedObject var quotaManager: QuotaManager
    @Environment(\.openSettings) private var openSettings
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with Logo
            HStack(spacing: 12) {
                if let logo = loadLogo() {
                    Image(nsImage: logo)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                        .cornerRadius(6)
                }
                
                VStack(alignment: .leading, spacing: 0) {
                    Text("AI Quotas")
                        .font(.headline)
                    Text("Track your usage")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    quotaManager.refreshQuotas()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(Angle.degrees(quotaManager.isRefreshing ? 360 : 0))
                        .animation(quotaManager.isRefreshing ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: quotaManager.isRefreshing)
                }
                .buttonStyle(.plain)
                .disabled(quotaManager.isRefreshing)
            }
            .padding()
            
            Divider()
            
            if quotaManager.providers.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 30))
                        .foregroundColor(.secondary)
                    Text("No accounts configured.")
                        .foregroundColor(.secondary)
                    Button("Open Settings") {
                        openSettings()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(quotaManager.providers) { provider in
                            ProviderRow(provider: provider)
                        }
                    }
                    .padding()
                }
            }
            
            Divider()
            
            HStack {
                Button(action: {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    if #available(macOS 14.0, *) {
                        openSettings()
                    } else {
                        NSApplication.shared.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    }
                }) {
                    Label("Settings", systemImage: "gearshape")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Text("Quit")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
            }
            .padding()
        }
        .frame(minWidth: 320, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity)
    }
    
    private func loadLogo() -> NSImage? {
        // 1. Try NSImage(named:) which is best for bundled resources
        if let image = NSImage(named: "logo") {
            return image
        }
        
        // 2. Try finding by name in bundle with any extension
        if let bundlePath = Bundle.main.resourcePath {
            let fm = FileManager.default
            let extensions = ["png", "jpg", "jpeg"]
            for ext in extensions {
                let fullPath = (bundlePath as NSString).appendingPathComponent("logo.\(ext)")
                if fm.fileExists(atPath: fullPath) {
                    return NSImage(contentsOfFile: fullPath)
                }
            }
        }
        
        // 3. Fallback or development path
        let devPath = "/Users/ion1/WORK/research/universal-taskbar-ai-usage/AIQuota/Sources/Resources/logo.png"
        if FileManager.default.fileExists(atPath: devPath) {
            return NSImage(contentsOfFile: devPath)
        }
        
        return nil
    }
}

struct ProviderRow: View {
    let provider: ProviderModel
    
    private var timeAgo: String {
        guard let lastFetched = provider.lastFetchedAt else { return "" }
        let seconds = Int(Date().timeIntervalSince(lastFetched))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        return "\(minutes / 60)h ago"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack {
                Text(provider.label)
                    .font(.subheadline)
                    .bold()
                Spacer()
                if !timeAgo.isEmpty {
                    Text(timeAgo)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            if !provider.isConfigured {
                Text("Not configured — add credentials in Settings")
                    .font(.caption)
                    .foregroundColor(.orange)
            } else if let statusMessage = provider.statusMessage, provider.quotaWindows.isEmpty {
                // Show message only if no windows
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            } else if provider.quotaWindows.isEmpty {
                Text("No data yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Show each quota window as a progress bar
            ForEach(provider.quotaWindows) { window in
                QuotaWindowRow(window: window)
            }
            
            // Show status message as a note if we also have windows
            if let statusMessage = provider.statusMessage, !provider.quotaWindows.isEmpty {
                Text(statusMessage)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

struct QuotaWindowRow: View {
    let window: QuotaWindow
    
    private var remainingPercent: Int {
        return max(0, Int(100 - window.usedPercent))
    }
    
    private var barColor: Color {
        let remaining = 100 - window.usedPercent
        if remaining > 50 { return .green }
        if remaining > 20 { return .orange }
        return .red
    }
    
    private var resetText: String {
        guard let resetAt = window.resetAt else { return "" }
        let seconds = Int(resetAt.timeIntervalSinceNow)
        if seconds <= 0 { return "resets soon" }
        if seconds < 3600 { return "resets in \(seconds / 60)m" }
        return "resets in \(seconds / 3600)h"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(window.name)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(remainingPercent)% remaining")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if !resetText.isEmpty {
                    Text("· \(resetText)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .frame(width: geometry.size.width, height: 5)
                        .opacity(0.15)
                        .foregroundColor(Color.gray)
                    
                    Rectangle()
                        .frame(width: max(0, min(CGFloat(1.0 - window.usedPercent / 100.0) * geometry.size.width, geometry.size.width)), height: 5)
                        .foregroundColor(barColor)
                        .animation(.linear, value: window.usedPercent)
                }
                .cornerRadius(2.5)
            }
            .frame(height: 5)
        }
    }
}
