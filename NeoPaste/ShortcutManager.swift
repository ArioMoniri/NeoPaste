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

import Foundation
import HotKey
import AppKit
import UserNotifications

@MainActor
class ShortcutManager: ObservableObject {
    static let shared = ShortcutManager()
    
    @Published private(set) var shortcuts: [ShortcutKey: KeyCombo] = [:]
    private var hotKeys: [ShortcutKey: HotKey] = [:]
    private let defaults = UserDefaults.standard
    private let notificationCenter = UNUserNotificationCenter.current()
    
    enum ShortcutKey: String, CaseIterable {
        case saveClipboard = "SaveClipboardShortcut"
        
        var defaultKeyCombo: (keyCode: Int, modifiers: NSEvent.ModifierFlags)? {
            switch self {
            case .saveClipboard:
                return (1, [.command, .shift]) // ⌘⇧S
            }
        }
        
        enum ClipboardAction {
            case saveClipboard
        }

        var title: String {
            switch self {
            case .saveClipboard:
                return "Save Clipboard"
            }
        }
    }
    
    private init() {
        setupNotifications()
        loadShortcuts()
    }
    
    private func setupNotifications() {
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
            }
        }
    }
    
    private func loadShortcuts() {
        for key in ShortcutKey.allCases {
            if let data = defaults.data(forKey: key.rawValue),
               let keyCombo = try? JSONDecoder().decode(KeyComboData.self, from: data) {
                shortcuts[key] = KeyCombo(
                    carbonKeyCode: keyCombo.keyCode,
                    carbonModifiers: keyCombo.modifiers
                )
                registerHotKey(for: key)
            } else if let defaultCombo = key.defaultKeyCombo {
                let keyComboData = KeyComboData(
                    keyCode: UInt32(defaultCombo.keyCode),
                    modifiers: UInt32(defaultCombo.modifiers.rawValue)
                )
                shortcuts[key] = KeyCombo(
                    carbonKeyCode: keyComboData.keyCode,
                    carbonModifiers: keyComboData.modifiers
                )
                registerHotKey(for: key)
                saveShortcut(shortcuts[key]!, forKey: key)
            }
        }
    }
    
    func setShortcut(_ keyCombo: KeyCombo?, forKey key: ShortcutKey) {
        hotKeys[key]?.isPaused = true
        hotKeys[key] = nil
        
        if let keyCombo = keyCombo {
            shortcuts[key] = keyCombo
            saveShortcut(keyCombo, forKey: key)
            registerHotKey(for: key)
        } else {
            shortcuts.removeValue(forKey: key)
            defaults.removeObject(forKey: key.rawValue)
        }
        
        objectWillChange.send()
    }
    
    private func saveShortcut(_ keyCombo: KeyCombo, forKey key: ShortcutKey) {
        let data = KeyComboData(keyCode: keyCombo.carbonKeyCode, modifiers: keyCombo.carbonModifiers)
        if let encoded = try? JSONEncoder().encode(data) {
            defaults.set(encoded, forKey: key.rawValue)
        }
    }
    
    private func registerHotKey(for key: ShortcutKey) {
        guard let keyCombo = shortcuts[key] else { return }
        
        let hotKey = HotKey(
            carbonKeyCode: keyCombo.carbonKeyCode,
            carbonModifiers: keyCombo.carbonModifiers
        )
        
        hotKey.keyDownHandler = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.handleShortcut(key)
            }
        }
        
        hotKeys[key] = hotKey
    }
    
    private func handleShortcut(_ key: ShortcutKey) async {
        print("Handling shortcut for: \(key.title)")
        do {
            let content = ClipboardMonitor.shared.currentContent
            
            // Validate content type based on shortcut
            switch (key, content) {
            case (.saveClipboard, _):
                // Content type matches shortcut or it's the general save shortcut
                break
            }
            
            let savedURL = try await FileSaver.shared.saveWithDialog(content)
            print("Content saved successfully at: \(savedURL.path)")
            await showNotification(title: "Success", message: "Content saved successfully")
            NotificationCenter.default.post(name: .saveCompleted, object: nil)
        } catch FileSavingError.userCancelled {
            print("Save operation cancelled by user")
        } catch {
            print("Error handling shortcut: \(error.localizedDescription)")
            await showNotification(title: "Error", message: error.localizedDescription)
            NotificationCenter.default.post(name: .saveError, object: error)
        }
    }
    
    private func showNotification(title: String, message: String) async {
        guard defaults.bool(forKey: UserDefaultsKeys.showNotifications) else { return }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
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
    
    func unregisterAllShortcuts() {
        for (key, hotKey) in hotKeys {
            hotKey.isPaused = true
            hotKeys.removeValue(forKey: key)
        }
        shortcuts.removeAll()
        objectWillChange.send()
    }
}

// MARK: - Supporting Types
private struct KeyComboData: Codable {
    let keyCode: UInt32
    let modifiers: UInt32
}

enum ShortcutError: LocalizedError {
    case invalidContentType
    case userCancelled
    
    var errorDescription: String? {
        switch self {
        case .invalidContentType:
            return "The clipboard content doesn't match the requested format"
        case .userCancelled:
            return "Operation cancelled by user"
        }
    }
}
