import SwiftUI
import AppKit

class StatusBarController {
    private var statusItem: NSStatusItem
    private var panel: NSPanel
    private var quotaManager: QuotaManager
    
    init(quotaManager: QuotaManager) {
        self.quotaManager = quotaManager
        
        // Setup Status Item
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        // Setup Panel (the popup window)
        self.panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 500),
            styleMask: [.nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        
        self.panel.isFloatingPanel = true
        self.panel.level = .floating
        self.panel.isMovableByWindowBackground = true
        self.panel.hasShadow = true
        
        // Background: Use NSVisualEffectView for that native translucent look
        let visualEffect = NSVisualEffectView()
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.material = .menu
        
        // Important: this allows it to show even if app is hidden
        self.panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        // Set SwiftUI View
        let hostingView = NSHostingView(rootView: MenuBarView(quotaManager: quotaManager))
        
        // Wrap hosting view in visual effect
        visualEffect.frame = NSRect(x: 0, y: 0, width: 340, height: 500)
        hostingView.frame = visualEffect.bounds
        hostingView.autoresizingMask = [.width, .height]
        visualEffect.addSubview(hostingView)
        
        self.panel.contentView = visualEffect
        self.panel.backgroundColor = .clear
        
        // Setup close on blur
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.panel.orderOut(nil)
        }
        
        // Set menu bar button content
        if let button = self.statusItem.button {
            button.action = #selector(togglePanel(_:))
            button.target = self
            
            // Initial icon
            updateIcon()
        }
        
        // Listen for health changes to update icon
        NotificationCenter.default.addObserver(forName: NSNotification.Name("QuotaHealthChanged"), object: nil, queue: .main) { [weak self] _ in
            self?.updateIcon()
        }
    }
    
    func updateIcon() {
        guard let button = statusItem.button else { return }
        
        // 1. Try to use the custom logo first for a premium look
        if let logo = NSImage(named: "logo") ?? loadBundledLogo() {
            logo.isTemplate = true // Allows it to adapt to dark/light menu bars
            logo.size = NSSize(width: 18, height: 18)
            button.image = logo
            return
        }
        
        // 2. Fallback to SF Symbol from QuotaManager
        let iconName = quotaManager.overallHealthIcon
        button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "AI Quota")
    }
    
    private func loadBundledLogo() -> NSImage? {
        if let bundlePath = Bundle.main.resourcePath {
            let fullPath = (bundlePath as NSString).appendingPathComponent("logo.png")
            if FileManager.default.fileExists(atPath: fullPath) {
                return NSImage(contentsOfFile: fullPath)
            }
        }
        return nil
    }
    
    @objc func togglePanel(_ sender: Any?) {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            // Position panel relative to button
            if let button = statusItem.button, let window = button.window {
                let buttonRect = window.convertToScreen(button.frame)
                var panelRect = panel.frame
                
                // Align panel below button
                panelRect.origin.x = buttonRect.origin.x + (buttonRect.width / 2) - (panelRect.width / 2)
                panelRect.origin.y = buttonRect.origin.y - panelRect.height - 5
                
                panel.setFrameOrigin(panelRect.origin)
                panel.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
