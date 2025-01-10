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

import AppKit
import SwiftUI
import UserNotifications
import os.log
import Foundation

enum PermissionError: Error {
    case notificationsDenied
    case accessibilityDenied
    case automationDenied
    case shortcutsDenied
    case fileSaveAccessDenied
    
    var localizedDescription: String {
        switch self {
        case .notificationsDenied:
            return "Notifications permission denied"
        case .accessibilityDenied:
            return "Accessibility permission denied"
        case .automationDenied:
            return "Automation permission denied"
        case .shortcutsDenied:
            return "Shortcuts permission denied"
        case .fileSaveAccessDenied:
            return "File save location access denied"
        }
    }
}

@MainActor
class PermissionManager {
    static let shared = PermissionManager()
    private let logger: Logger
    private let defaults = UserDefaults.standard
    
    enum Permission {
        case notifications
        case accessibility
        case automation
        case shortcuts
        case fileSave
        
        var title: String {
            switch self {
            case .notifications: return "Notifications"
            case .accessibility: return "Accessibility"
            case .automation: return "Automation"
            case .shortcuts: return "Shortcuts"
            case .fileSave: return "File Save Location"
            }
        }
        
        var description: String {
            switch self {
            case .notifications:
                return "NeoPaste needs notifications permission to alert you when files are saved."
            case .accessibility:
                return "NeoPaste needs accessibility permission to work with keyboard shortcuts."
            case .automation:
                return "NeoPaste needs automation permission to save files automatically."
            case .shortcuts:
                return "NeoPaste needs shortcuts permission to record custom keyboard shortcuts."
            case .fileSave:
                return "NeoPaste needs permission to save files to your chosen location."
            }
        }
    }
    
    private init() {
        let subsystem = Bundle.main.bundleIdentifier ?? "com.yourapp.neopaste"
        self.logger = Logger(subsystem: subsystem, category: "PermissionManager")
    }
    
    func requestPermissions() async throws {
        logger.info("Starting permission requests...")
        
        // Request notifications permission first
        try await requestNotificationsPermission()
        
        // Then request accessibility permission
        try await requestAccessibilityPermission()
        
        // Request file save location permission
        try await requestFileSaveLocationPermission()
        
        logger.info("All permissions granted successfully")
    }
    
    private func requestNotificationsPermission() async throws {
        logger.debug("Requesting notification permissions...")
        let center = UNUserNotificationCenter.current()
        let options: UNAuthorizationOptions = [.alert, .sound]
        
        do {
            let granted = try await center.requestAuthorization(options: options)
            if !granted {
                logger.error("Notification permission denied by user")
                throw PermissionError.notificationsDenied
            }
            logger.debug("Notification permission granted")
        } catch {
            logger.error("Error requesting notification permission: \(error.localizedDescription)")
            throw PermissionError.notificationsDenied
        }
    }
    
    private func requestAccessibilityPermission() async throws {
        logger.debug("Requesting accessibility permission...")
        let options = NSDictionary(
            object: kAXTrustedCheckOptionPrompt.takeUnretainedValue(),
            forKey: kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString
        )
        
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted {
            logger.error("Accessibility permission denied")
            throw PermissionError.accessibilityDenied
        }
        logger.debug("Accessibility permission granted")
    }
    
    func requestFileSaveLocationPermission() async throws {
        logger.debug("Requesting file save location permission...")
        
        // Check if save location is already set and valid
        if hasSaveLocationPermission() {
            logger.debug("Existing save location permission is valid")
            return
        }
        
        // Request folder selection
        try await selectSaveLocation()
    }
    
    private func hasSaveLocationPermission() -> Bool {
        guard let bookmarkData = defaults.data(forKey: UserDefaultsKeys.customSaveLocation) else {
            return false
        }
        
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            
            // Start accessing the security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                return false
            }
            
            // Check if directory exists and is writable
            var isDirectory: ObjCBool = false
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  fileManager.isWritableFile(atPath: url.path) else {
                return false
            }
            
            // Stop accessing the resource
            url.stopAccessingSecurityScopedResource()
            
            return !isStale
        } catch {
            logger.error("Error checking save location permission: \(error.localizedDescription)")
            return false
        }
    }
    
    private func selectSaveLocation() async throws {
        try await MainActor.run {
            let openPanel = NSOpenPanel()
            openPanel.canChooseFiles = false
            openPanel.canChooseDirectories = true
            openPanel.canCreateDirectories = true
            openPanel.allowsMultipleSelection = false
            openPanel.title = "Select Save Location"
            openPanel.message = "Choose a folder to save your files"
            
            let response = openPanel.runModal()
            
            guard response == .OK, let selectedURL = openPanel.url else {
                // Show alert to guide user
                showPermissionAlert(for: .fileSave)
                throw PermissionError.fileSaveAccessDenied
            }
            
            // Create security-scoped bookmark
            do {
                let bookmarkData = try selectedURL.bookmarkData(options: .withSecurityScope)
                defaults.set(bookmarkData, forKey: UserDefaultsKeys.customSaveLocation)
                logger.debug("Save location bookmark created successfully")
            } catch {
                logger.error("Failed to create bookmark: \(error.localizedDescription)")
                showPermissionAlert(for: .fileSave)
                throw PermissionError.fileSaveAccessDenied
            }
        }
    }
    
    @MainActor
    func showPermissionAlert(for permission: Permission) {
        logger.debug("Showing permission alert for: \(permission.title)")
        let alert = NSAlert()
        alert.messageText = "\(permission.title) Permission Required"
        alert.informativeText = "\(permission.description)\n\nWould you like to open System Settings to grant permission?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            switch permission {
            case .notifications:
                openNotificationPreferences()
            case .accessibility:
                openAccessibilityPreferences()
            case .automation:
                openAutomationPreferences()
            case .shortcuts:
                openShortcutsPreferences()
            case .fileSave:
                openFileSavePreferences()
            }
        }
    }
    
    private func openNotificationPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func openAccessibilityPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func openAutomationPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func openShortcutsPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func openFileSavePreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Files") {
            NSWorkspace.shared.open(url)
        }
    }
}
