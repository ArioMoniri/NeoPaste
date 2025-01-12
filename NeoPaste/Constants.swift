import Foundation
import UniformTypeIdentifiers
import SwiftUI

// MARK: - App Configuration
enum AppConstants {
    static let appName = "NeoPaste"
    static let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    static let appBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    
    // Window sizes
    static let preferencesWindowSize = CGSize(width: 500, height: 400)
    static let minimumWindowSize = CGSize(width: 400, height: 300)
    
    // Time intervals
    static let clipboardCheckInterval: TimeInterval = 0.5
    static let notificationDuration: TimeInterval = 2.0
    
    // File size limits
    static let maxFileSizeMB: Int64 = 100
    static let maxCompressedSizeMB: Int64 = 500
}

// MARK: - UserDefaults Keys
enum UserDefaultsKeys {
    static let customSaveLocation = "customSaveLocation"
    static let defaultImageFormat = "defaultImageFormat"
    static let defaultTextFormat = "defaultTextFormat"
    static let compressionEnabled = "compressionEnabled"
    static let compressionFormat = "compressionFormat"
    static let showNotifications = "showNotifications"
    static let darkModeEnabled = "darkModeEnabled"
    static let autoStartEnabled = "autoStartEnabled"
    static let compressFiles = "compressFiles"
    static let useFinderWindow = "useFinderWindow"
}

// MARK: - Notification Names
extension Notification.Name {
    static let clipboardContentChanged = Notification.Name("clipboardContentChanged")
    static let saveCompleted = Notification.Name("saveCompleted")
    static let saveError = Notification.Name("saveError")
    static let preferencesChanged = Notification.Name("preferencesChanged")
}

// MARK: - UI Constants
enum UIConstants {
    // Colors
    static let accentColor = Color("AccentColor")
    static let backgroundColor = Color("BackgroundColor")
    static let textColor = Color("TextColor")
    
    // Dimensions
    static let cornerRadius: CGFloat = 8
    static let defaultPadding: CGFloat = 16
    static let iconSize: CGFloat = 20
    static let menuBarIconSize: CGFloat = 18
    
    // Animation
    static let defaultAnimation: Animation = .easeInOut(duration: 0.3)
    static let quickAnimation: Animation = .easeOut(duration: 0.2)
}

// MARK: - File Types
enum SupportedFileTypes {
    // Image Formats
    static let imageTypes: [UTType] = [.png, .jpeg, .tiff, .gif, .heic]
    static let imageExtensions = ["png", "jpg", "tiff", "gif", "heic"]
    
    // Text Formats
    static let textTypes: [UTType] = [.plainText, .rtf, .html]
    static let textExtensions = ["txt", "rtf", "html", "md"]
    
    // Compression Formats
    static let compressionTypes: [UTType] = [.zip]
    static let compressionExtensions = ["zip"]
    
    // Combined Types
    static let allTypes: [UTType] = imageTypes + textTypes + compressionTypes
    static let allExtensions = imageExtensions + textExtensions + compressionExtensions
}

// MARK: - Error Messages
enum ErrorMessages {
    static let generalError = "An unexpected error occurred"
    static let invalidFormat = "Invalid file format"
    static let conversionError = "Failed to convert file"
    static let saveError = "Failed to save file"
    static let accessDenied = "Access denied to save location"
    static let fileTooLarge = "File size exceeds maximum limit"
    static let compressionError = "Failed to compress file"
    static let invalidPath = "Invalid save location path"
}

// MARK: - Menu Items
enum MenuItemTitles {
    static let saveClipboard = "Save Clipboard"
    static let preferences = "Preferences..."
    static let quit = "Quit NeoPaste"
    static let compressionOptions = "Compression Options"
}

// MARK: - Keyboard Shortcuts
enum DefaultShortcuts {
    static let saveClipboard = "⌘S"
    static let preferences = "⌘,"
    static let quit = "⌘Q"
}

// MARK: - Default Save Location
enum DefaultSaveLocation {
    static let fallbackSaveLocation = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
}
extension AppConstants {
    static func getSaveLocation() -> URL {
        if let customLocationPath = UserDefaults.standard.string(forKey: UserDefaultsKeys.customSaveLocation),
           let customLocation = URL(string: customLocationPath) {
            return customLocation
        } else {
            return DefaultSaveLocation.fallbackSaveLocation
        }
    }
}

// MARK: - Debug Constants
#if DEBUG
enum DebugConstants {
    static let isLoggingEnabled = true
    static let isMockDataEnabled = false
    static let mockDelay: TimeInterval = 0.5
    static let debugSaveLocation = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
}
#endif
