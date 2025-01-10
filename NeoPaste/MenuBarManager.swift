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
import Combine
import UserNotifications

@MainActor
class MenuBarManager: ObservableObject {
    private static var sharedInstance: MenuBarManager?
    
    static var shared: MenuBarManager {
        if let existing = sharedInstance {
            return existing
        }
        let new = MenuBarManager()
        sharedInstance = new
        return new
    }
    
    // MARK: - Properties
    private var statusItem: NSStatusItem!
    private let clipboardMonitor = ClipboardMonitor.shared
    private var cancellables = Set<AnyCancellable>()
    private let fileSaver = FileSaver.shared
    private let notificationCenter = UNUserNotificationCenter.current()
    
    // MARK: - Initialization
    private init() {
        setupNotifications()
        setupStatusItem()
        setupObservers()
        updateMenu()
    }
    
    // MARK: - Setup Methods
    private func setupNotifications() {
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
            }
        }
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard",
                                 accessibilityDescription: AppConstants.appName)
        }
        updateStatusIcon(for: clipboardMonitor.currentContent)
    }
    
    private func setupObservers() {
        NotificationCenter.default.publisher(for: .clipboardContentChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.handleClipboardChange()
                }
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .saveCompleted)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.showSaveCompletedNotification()
                }
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .saveError)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                if let error = notification.object as? Error {
                    Task { @MainActor [weak self] in
                        await self?.showError(error)
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    private func updateMenu() {
        let menu = NSMenu()
        let content = clipboardMonitor.currentContent
        
        // Content Type Indicator
        let contentTypeItem = NSMenuItem(title: "Content: \(content.typeDescription)",
                                       action: nil,
                                       keyEquivalent: "")
        contentTypeItem.isEnabled = false
        menu.addItem(contentTypeItem)
        menu.addItem(NSMenuItem.separator())
        
        // Save As Menu
        let saveAsMenu = NSMenu()
        for format in content.availableFormats {
            let menuItem = NSMenuItem(title: format, action: #selector(handleSaveWithFormat(_:)), keyEquivalent: "")
            menuItem.representedObject = format // Store the format
            saveAsMenu.addItem(menuItem)
        }

        let saveAsItem = NSMenuItem(title: "Save As", action: nil, keyEquivalent: "")
        saveAsItem.submenu = saveAsMenu
        menu.addItem(saveAsItem)
        
        // Quick Save
        menu.addItem(withTitle: "Quick Save",
                    action: #selector(handleQuickSave(_:)),
                    keyEquivalent: "s")
        
        menu.addItem(NSMenuItem.separator())
        
        // Recent Files
        if let recentFiles = UserDefaults.standard.stringArray(forKey: "RecentFiles"),
           !recentFiles.isEmpty {
            let recentMenu = NSMenu()
            for path in recentFiles.prefix(5) {
                recentMenu.addItem(withTitle: (path as NSString).lastPathComponent,
                                 action: #selector(handleOpenRecentFile(_:)),
                                 keyEquivalent: "")
            }
            
            let recentItem = NSMenuItem(title: "Recent Files", action: nil, keyEquivalent: "")
            recentItem.submenu = recentMenu
            menu.addItem(recentItem)
            menu.addItem(NSMenuItem.separator())
        }
        
        // Preferences & Quit
        menu.addItem(withTitle: "Preferences...",
                    action: #selector(AppDelegate.shared.showPreferences(_:)),
                    keyEquivalent: ",")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit",
                    action: #selector(NSApplication.terminate(_:)),
                    keyEquivalent: "q")
        
        statusItem.menu = menu
    }
    
    // MARK: - Action Handlers
    @objc private func handleQuickSave(_ sender: NSMenuItem) {
        Task {
            do {
                // Retrieve the selected format from the menu item's representedObject
                UserDefaults.standard.set(sender.title.lowercased(), forKey: "lastSelectedFormat")
                guard let format = sender.representedObject as? String else {
                    throw FileSavingError.invalidFileFormat
                }
                let savedURL = try await fileSaver.saveDirectly(clipboardMonitor.currentContent, format:format)
                print("Content saved successfully at: \(savedURL.path)")
                NotificationCenter.default.post(name: .saveCompleted, object: nil)
            } catch {
                print("Failed to save: \(error.localizedDescription)")
                await showError(error)
            }
        }
    }

    @objc private func handleSaveWithFormat(_ sender: NSMenuItem) {
        Task {
            do {
                // Store the selected format in UserDefaults for future use
                UserDefaults.standard.set(sender.title.lowercased(), forKey: "lastSelectedFormat")
                
                // Retrieve the selected format from the menu item's representedObject
                guard let format = sender.representedObject as? String else {
                    throw FileSavingError.invalidFileFormat
                }

                // Use the format retrieved from representedObject
                let savedURL = try await fileSaver.saveDirectly(clipboardMonitor.currentContent, format: format)
                print("Content saved successfully at: \(savedURL.path)")
                NotificationCenter.default.post(name: .saveCompleted, object: nil)
            } catch {
                print("Failed to save: \(error.localizedDescription)")
                await showError(error)
            }
        }
    }

    @objc private func handleOpenRecentFile(_ sender: NSMenuItem) {
        // Implementation for opening recent files
        print("Opening recent file: \(sender.title)")
    }
    

    
    // MARK: - Helper Methods
    private func handleClipboardChange() async {
        updateStatusIcon(for: clipboardMonitor.currentContent)
        updateMenu()
    }
    
    private func updateStatusIcon(for content: ClipboardContent) {
        guard let button = statusItem.button else { return }
        
        let symbolName: String
        let description: String
        
        switch content {
        case .image:
            symbolName = "photo"
            description = "Image"
        case .text:
            symbolName = "doc.text"
            description = "Text"
        case .pdf:
            symbolName = "doc.fill"
            description = "PDF"
        case .rtf:
            symbolName = "doc.richtext"
            description = "RTF"
        case .file:
            symbolName = "doc"
            description = "File"
        case .multiple:
            symbolName = "doc.on.doc"
            description = "Multiple Files"
        case .empty:
            symbolName = "doc.on.clipboard"
            description = "Empty"
        }
        
        button.image = NSImage(systemSymbolName: symbolName,
                             accessibilityDescription: description)
    }
    
    private func showError(_ error: Error) async {
        let content = UNMutableNotificationContent()
        content.title = "Error"
        content.body = error.localizedDescription
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        do {
            try await notificationCenter.add(request)
        } catch {
            print("Failed to show notification: \(error.localizedDescription)")
        }
    }
    
    private func showSaveCompletedNotification() async {
        let content = UNMutableNotificationContent()
        content.title = "Save Completed"
        content.body = "Content saved successfully"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        do {
            try await notificationCenter.add(request)
        } catch {
            print("Failed to show notification: \(error.localizedDescription)")
        }
    }
}

// MARK: - Preview Support
#if DEBUG
extension MenuBarManager {
    static var preview: MenuBarManager {
        return MenuBarManager.shared
    }
}
#endif
