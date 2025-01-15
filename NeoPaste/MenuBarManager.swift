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
import QuickLookUI

@MainActor
class MenuBarManager: NSObject, ObservableObject {
    
    
    private static var sharedInstance: MenuBarManager?
    
    static var shared: MenuBarManager {
        if let existing = sharedInstance {
            return existing
        }
        let new = MenuBarManager()
        sharedInstance = new
        return new
    }
    
    
    private func setupNotifications() async {
        // Request notification permissions
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound])
            print("Notification authorization granted: \(granted)")
        } catch {
            print("Notification permission error: \(error.localizedDescription)")
        }
        
        // Set up notification observers
        NotificationCenter.default.addObserver(
            forName: AppNotification.recentFilesCleared,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateMenu()  // Removed await since updateMenu() isn't async
            }
        }
    }



    
    // MARK: - Properties
    private var statusItem: NSStatusItem!
    private let clipboardMonitor = ClipboardMonitor.shared
    private var cancellables = Set<AnyCancellable>()
    private let fileSaver = FileSaver.shared
    private let notificationCenter = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private var previewURL: URL?
    
    // MARK: - Initialization
    private override init() {
        super.init()
        Task {
            await setupNotifications()
            setupStatusItem()
            setupObservers()
            updateMenu()
        }
    }
    // MARK: - Setup Methods

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
    
    func updateMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false  // Important: Prevent auto-enabling of menu items
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
        saveAsMenu.autoenablesItems = false  // Important: Prevent auto-enabling of submenu items
        
        if !content.availableFormats.isEmpty {
            for format in content.availableFormats {
                let menuItem = NSMenuItem(
                    title: format.uppercased(),
                    action: #selector(handleSaveWithFormat(_:)),
                    keyEquivalent: ""
                )
                menuItem.target = self
                menuItem.isEnabled = true
                saveAsMenu.addItem(menuItem)
            }

            let saveAsItem = NSMenuItem(title: "Save As", action: nil, keyEquivalent: "")
            saveAsItem.submenu = saveAsMenu
            saveAsItem.isEnabled = true
            menu.addItem(saveAsItem)
        } else {
            let emptyItem = NSMenuItem(title: "No Content to Save", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            saveAsMenu.addItem(emptyItem)
            let saveAsItem = NSMenuItem(title: "Save As", action: nil, keyEquivalent: "")
            saveAsItem.submenu = saveAsMenu
            saveAsItem.isEnabled = false
            menu.addItem(saveAsItem)
        }

        // Quick Save
        let quickSaveItem = NSMenuItem(
            title: "Quick Save",
            action: #selector(handleQuickSave(_:)),
            keyEquivalent: "s"
        )
        quickSaveItem.target = self
        quickSaveItem.isEnabled = !content.availableFormats.isEmpty
        menu.addItem(quickSaveItem)

        menu.addItem(NSMenuItem.separator())

        // Recent Files
        // Recent Files section in updateMenu()
        let recentFilesMenu = NSMenu()
        recentFilesMenu.autoenablesItems = false

        print("Checking recent files in updateMenu")
        if let recentFiles = defaults.stringArray(forKey: "RecentFiles") {
            print("Found recent files: \(recentFiles)")
            if !recentFiles.isEmpty {
                let recentItem = NSMenuItem(title: "Recent Files", action: nil, keyEquivalent: "")
                let submenu = NSMenu()
                
                for path in recentFiles.prefix(5) {
                    let menuItem = NSMenuItem(
                        title: (path as NSString).lastPathComponent,
                        action: #selector(handleOpenRecentFile(_:)),
                        keyEquivalent: ""
                    )
                    menuItem.target = self
                    menuItem.isEnabled = true
                    menuItem.representedObject = path
                    submenu.addItem(menuItem)
                }
                
                recentItem.submenu = submenu
                menu.addItem(recentItem)
                menu.addItem(NSMenuItem.separator())
            } else {
                print("Recent files array is empty")
            }
        } else {
            print("No recent files array found in UserDefaults")
        }
        
        // Add this before the "Preferences" section
        let quickLookItem = NSMenuItem(
            title: "Quick Preview",
            action: #selector(handleQuickLookPreview(_:)),
            keyEquivalent: "p"
        )
        quickLookItem.target = self
        quickLookItem.isEnabled = !content.availableFormats.isEmpty
        menu.addItem(quickLookItem)


        // Preferences
        let preferencesItem = NSMenuItem(
            title: "Preferences...",
            action: #selector(showPreferences),
            keyEquivalent: ","
        )
        preferencesItem.target = self
        preferencesItem.isEnabled = true
        menu.addItem(preferencesItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        quitItem.isEnabled = true
        menu.addItem(quitItem)

        statusItem.menu = menu
    }
    
    // MARK: - Action Handlers
    @objc private func handleQuickSave(_ sender: NSMenuItem) {
        Task {
            do {
                let menuBarStyle = defaults.string(forKey: UserDefaultsKeys.menuBarSaveStyle) ?? "direct"
                let format = clipboardMonitor.currentContent.defaultFormat
                defaults.set(format, forKey: "lastSelectedFormat")

                let savedURL = try await menuBarStyle == "direct" ?
                    fileSaver.saveDirectly(clipboardMonitor.currentContent, format: format) :
                    fileSaver.saveWithDialog(clipboardMonitor.currentContent)

                updateRecentFiles(with: savedURL.path)
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
                let format = sender.title.lowercased()
                let menuBarStyle = defaults.string(forKey: UserDefaultsKeys.menuBarSaveStyle) ?? "direct"
                defaults.set(format, forKey: "lastSelectedFormat")
                
                // Store the selected format
                defaults.set(format, forKey: UserDefaultsKeys.selectedSaveFormat)

                let savedURL: URL
                if menuBarStyle == "direct" {
                    savedURL = try await fileSaver.saveDirectly(clipboardMonitor.currentContent, format: format)
                } else {
                    savedURL = try await fileSaver.saveWithDialog(clipboardMonitor.currentContent)
                }

                updateRecentFiles(with: savedURL.path)
                print("Content saved successfully at: \(savedURL.path)")
                NotificationCenter.default.post(name: .saveCompleted, object: nil)
            } catch {
                print("Failed to save: \(error.localizedDescription)")
                await showError(error)
            }
        }
    }
    
    
    @objc private func handleOpenRecentFile(_ sender: NSMenuItem) {
        guard let filePath = sender.representedObject as? String else { return }
        let url = URL(fileURLWithPath: filePath)
        NSWorkspace.shared.open(url)
    }
    
    @objc private func showPreferences() {
        DispatchQueue.main.async {
            AppDelegate.shared.showPreferences(nil)
        }
    }
    
    @objc private func handleQuickLookPreview(_ sender: NSMenuItem) {
    Task {
        do {
            let content = clipboardMonitor.currentContent
            guard let url = try await createTemporaryPreviewFile(for: content) else {
                print("No preview available")
                return
            }
            
            // Store the URL for later use in the QuickLook panel
            self.previewURL = url
            
            // Show the QuickLook panel
            DispatchQueue.main.async {
                if let panel = QLPreviewPanel.shared() {
                    panel.dataSource = self
                    panel.delegate = self
                    panel.makeKeyAndOrderFront(nil)
                }
            }
        } catch {
            print("Failed to create preview: \(error.localizedDescription)")
        }
    }
}
    


    
    func updateRecentFiles(with filePath: String) {
        print("Updating recent files with path: \(filePath)")
        var recentFiles = defaults.stringArray(forKey: "RecentFiles") ?? []
        print("Current recent files: \(recentFiles)")
        
        // Remove duplicate if exists
        if let index = recentFiles.firstIndex(of: filePath) {
            recentFiles.remove(at: index)
        }
        
        // Add to front of array
        recentFiles.insert(filePath, at: 0)
        
        // Limit to 5 recent files
        let limitedRecentFiles = Array(recentFiles.prefix(5))
        print("New recent files after update: \(limitedRecentFiles)")
        
        defaults.set(limitedRecentFiles, forKey: "RecentFiles")
        defaults.synchronize()
        
        // Update menu
        DispatchQueue.main.async { [weak self] in
            self?.updateMenu()
        }
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
    
    private func createTemporaryPreviewFile(for content: ClipboardContent) async throws -> URL? {
        let tempDirectory = FileManager.default.temporaryDirectory
        let uniqueFilename = "preview-\(UUID().uuidString)"
        
        switch content {
        case .image(let image):
            let tempURL = tempDirectory.appendingPathComponent("\(uniqueFilename).png")
            guard let tiffRepresentation = image.tiffRepresentation,
                  let bitmapImage = NSBitmapImageRep(data: tiffRepresentation),
                  let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
                return nil
            }
            try pngData.write(to: tempURL)
            return tempURL
            
        case .text(let text):
            let tempURL = tempDirectory.appendingPathComponent("\(uniqueFilename).txt")
            try text.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
            
        case .rtf(let data):
            let tempURL = tempDirectory.appendingPathComponent("\(uniqueFilename).rtf")
            try data.write(to: tempURL)
            return tempURL
            
        case .pdf(let data):
            let tempURL = tempDirectory.appendingPathComponent("\(uniqueFilename).pdf")
            try data.write(to: tempURL)
            return tempURL
            
        case .file(let url):
            return url
            
        case .multiple(let urls):
            // For multiple files, return the first file
            return urls.first
            
        case .empty:
            return nil
        }
    }
    

}

extension MenuBarManager: QLPreviewPanelDataSource {
    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        return 1
    }
    
    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        // Using runLoop to access MainActor property synchronously
        let runLoop = CFRunLoopGetCurrent()
        var previewItem: QLPreviewItem?
        
        Task { @MainActor in
            previewItem = MenuBarManager.shared.previewURL as QLPreviewItem?
            CFRunLoopStop(runLoop)
        }
        
        CFRunLoopRun()
        return previewItem
    }
}

extension MenuBarManager: QLPreviewPanelDelegate {
    nonisolated func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: QLPreviewItem!) -> NSRect {
        return .zero
    }
    
    nonisolated func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        return false
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
