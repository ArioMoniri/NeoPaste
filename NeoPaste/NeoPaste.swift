//
// Copyright 2025 Ariorad Moniri
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import SwiftUI
import AppKit
import HotKey
import UniformTypeIdentifiers
import UserNotifications
import os.log

@main
struct NeoPaste: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var clipboardMonitor = ClipboardMonitor.shared
    @StateObject private var shortcutManager = ShortcutManager.shared
    
    private let logger: Logger
    
    init() {
        // Setup logging
        let subsystem = Bundle.main.bundleIdentifier ?? "com.Falcon.neopaste"
        self.logger = Logger(subsystem: subsystem, category: "MainApp")
        
        // Configure app defaults
        setupDefaults()
        
        // Suppress unnecessary system logs
        suppressSystemLogs()
        
        // Setup notification handlers
        setupNotificationHandlers()
        
        // Setup logging
        Self.setupLogging()
    }
    
    var body: some Scene {
        WindowGroup("Preferences") {
            PreferencesView()
                .environmentObject(clipboardMonitor)
                .environmentObject(shortcutManager)
                .frame(
                    width: AppConstants.preferencesWindowSize.width,
                    height: AppConstants.preferencesWindowSize.height
                )
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: AppConstants.preferencesWindowSize.width,
                    height: AppConstants.preferencesWindowSize.height)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Preferences...") {
                    logger.debug("Opening preferences window")
                    NSApp.sendAction(#selector(AppDelegate.showPreferences(_:)), to: nil, from: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            
            CommandGroup(after: .pasteboard) {
                Button("Save Clipboard") {
                    Task {
                        await handleSaveClipboard()
                    }
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }
    }
    
    // MARK: - Setup Methods
    private func setupDefaults() {
        let defaults: [String: Any] = [
            UserDefaultsKeys.showNotifications: true,
            UserDefaultsKeys.defaultImageFormat: "png",
            UserDefaultsKeys.defaultTextFormat: "txt",
            UserDefaultsKeys.compressFiles: false,
            UserDefaultsKeys.darkModeEnabled: true,
            UserDefaultsKeys.autoStartEnabled: true
        ]
        
        UserDefaults.standard.register(defaults: defaults)
    }
    
    private func suppressSystemLogs() {
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            UserDefaults.standard.setValue(false, forKey: "NSConstraintBasedLayoutVisualizeMutuallyExclusiveConstraints")
            UserDefaults.standard.setValue(false, forKey: "\(bundleIdentifier).debugPrintingEnabled")
        }
    }
    
    private func setupNotificationHandlers() {
        NotificationCenter.default.addObserver(
            forName: .saveCompleted,
            object: nil,
            queue: .main
        ) { _ in
            logger.info("Save operation completed successfully")
        }
        
        NotificationCenter.default.addObserver(
            forName: .saveError,
            object: nil,
            queue: .main
        ) { notification in
            if let error = notification.object as? Error {
                logger.error("Save operation failed: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Action Handlers
    @MainActor
    private func handleSaveClipboard() async {
        do {
            logger.debug("Starting clipboard save operation")
            let savedURL = try await FileSaver.shared.saveWithDialog(clipboardMonitor.currentContent)
            logger.info("Content saved successfully at: \(savedURL.path)")
            NotificationCenter.default.post(name: .saveCompleted, object: nil)
        } catch {
            if case FileSavingError.userCancelled = error {
                logger.debug("Save operation cancelled by user")
            } else {
                logger.error("Failed to save clipboard: \(error.localizedDescription)")
                NotificationCenter.default.post(name: .saveError, object: error)
            }
        }
    }
}

// MARK: - Preview Provider
#Preview {
    PreferencesView()
        .environmentObject(ClipboardMonitor.shared)
        .environmentObject(ShortcutManager.shared)
}

// MARK: - App Launch Setup
extension NeoPaste {
    static func setupLogging() {
        guard let logFileURL = getLogFileURL() else { return }
        freopen(logFileURL.path, "a+", stdout)
        freopen(logFileURL.path, "a+", stderr)
    }
    
    private static func getLogFileURL() -> URL? {
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        let bundleID = Bundle.main.bundleIdentifier ?? "com.Falcon.neopaste"
        let appLogDirectory = appSupportURL.appendingPathComponent(bundleID).appendingPathComponent("Logs")
        
        do {
            try FileManager.default.createDirectory(at: appLogDirectory, withIntermediateDirectories: true)
            return appLogDirectory.appendingPathComponent("app.log")
        } catch {
            print("Failed to create log directory: \(error)")
            return nil
        }
    }
}
