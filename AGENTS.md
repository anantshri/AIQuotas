# AGENTS.md for [AIQuota](https://github.com/anantshri/AIQuotas)

This document provides instructions for AI agents and developers on how to build, maintain, and extend the AIQuota project.

## Project Architecture

- **`AIQuotaApp.swift`**: Entry point and high-level application state.
- **`QuotaManager.swift`**: Core logic for managing providers, refreshing data, and overall health status.
- **`ProviderAPIs.swift`**: Contains the API implementation for each AI service. This is where you add new providers.
- **`AuthTokenDetector.swift`**: Handles logic for finding session tokens for Claude and Codex in local file systems or keychains.
- **`LocalAntigravityService.swift`**: Handles specialized communication with a running Antigravity IDE process. **Note**: Antigravity monitoring is local-only and requires the IDE to be open.
- **`MenuBarView.swift` & `SettingsView.swift`**: UI components for the status bar menu and the configuration settings.
- **`StatusBarController.swift`**: The bridge between SwiftUI and the macOS menu bar system.
- **`KeychainHelper.swift`**: Utility for secure storage of sensitive data.

## Building the Project

The project uses a standard `Makefile` for compilation.

- **To build**: `make`
- **To run**: `make run`
- **To clean**: `make clean`

The build process generates a standalone `.app` bundle in the `dist/` directory.

## Extending the Project

### Adding a New Provider

To add support for a new AI service:

1.  **Define the Provider**: Add a new case to `ProviderType` in `QuotaManager.swift`.
2.  **Implement the API Fetching**: In `ProviderAPIs.swift`, create a new method (e.g., `fetchMyNewServiceUsage(apiKey:)`) that performs the necessary network requests and returns a `QuotaResult`.
3.  **Update `QuotaManager.refreshQuotas()`**: Add a case for your new provider to the `refreshQuotas` switch statement to call your new API method.
4.  **Token Detection (Optional)**: If the service has a local configuration tool (like Claude Code or Codex), add logic to `AuthTokenDetector.swift` to automatically find it.

### Modifying the UI

- The main popover UI is defined in `MenuBarView.swift`.
- Settings and provider configuration are in `SettingsView.swift`.
- To change the menu bar icon behavior, see `StatusBarController.swift`.

### Working with the Keychain

Sensitive data should always be stored through `KeychainHelper.shared`. Do not use `UserDefaults` for API keys or tokens.

## AI Assistant Guidelines

When working on this codebase:
1.  **Keep it Native**: Stick to SwiftUI and AppKit. Avoid adding external dependencies if possible.
2.  **Security First**: Never log full API keys or tokens. Use the Keychain for storage.
3.  **Efficiency**: Favor lightweight networking and background refreshes to keep the menu bar responsive.
4.  **Error Handling**: Always provide meaningful status messages to the user when a fetch fails, but avoid UI-blocking errors.

---
*Developed with AI Assisted Development by Antigravity.*
