import SwiftUI

@main
struct AIQuotaApp: App {
    @StateObject private var quotaManager = QuotaManager()
    
    // We use a static property or a separate class to hold the controller 
    // to avoid struct mutation issues in init
    private static var statusBarController: StatusBarController?

    var body: some Scene {
        Settings {
            SettingsView(quotaManager: quotaManager)
        }
    }
    
    init() {
        let manager = QuotaManager()
        _quotaManager = StateObject(wrappedValue: manager)
        
        // Initialize the status bar controller 
        // We can do this synchronously here or in a static way
        DispatchQueue.main.async {
            Self.statusBarController = StatusBarController(quotaManager: manager)
        }
    }
}
