import Foundation
import SwiftUI
import UserNotifications

class AppUpdater: ObservableObject {
    static let shared = AppUpdater()
    @Published var isChecking = false
    @Published var updateAvailable: GithubRelease?
    @Published private(set) var lastChecked: Date?
    @Published var downloadProgress: Double = 0
    @Published var isDownloading = false
    
    private let githubRepo = "ArioMoniri/NeoPaste"
    
    struct GithubRelease: Codable {
        let tagName: String
        let name: String
        let body: String
        let assets: [Asset]
        
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case body
            case assets
        }
    }
    
    struct Asset: Codable {
        let name: String
        let browserDownloadURL: String
        let size: Int
        
        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
            case size = "size"
        }
    }
    
    func checkForUpdates() async throws {
        await MainActor.run {
            isChecking = true
            updateAvailable = nil
        }
        
        defer {
            Task { @MainActor in
                isChecking = false
                lastChecked = Date()
            }
        }
        
        guard let url = URL(string: "https://api.github.com/repos/\(githubRepo)/releases/latest") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let release = try JSONDecoder().decode(GithubRelease.self, from: data)
        
        let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.4.0"
        if isNewerVersion(release.tagName, than: currentVersion) {
            await MainActor.run { updateAvailable = release }
        }
    }
    
    private func isNewerVersion(_ version1: String, than version2: String) -> Bool {
        let v1Components = version1.replacingOccurrences(of: "v", with: "").split(separator: ".")
        let v2Components = version2.replacingOccurrences(of: "v", with: "").split(separator: ".")
        
        let maxLength = max(v1Components.count, v2Components.count)
        
        for i in 0..<maxLength {
            let v1Num = i < v1Components.count ? Int(v1Components[i]) ?? 0 : 0
            let v2Num = i < v2Components.count ? Int(v2Components[i]) ?? 0 : 0
            
            if v1Num > v2Num {
                return true
            } else if v1Num < v2Num {
                return false
            }
        }
        return false
    }
    
    func downloadAndInstallUpdate(_ release: GithubRelease) async throws {
        // First try to find DMG, then fallback to ZIP
        let asset: Asset
        if let dmgAsset = release.assets.first(where: { $0.name.hasSuffix(".dmg") }) {
            asset = dmgAsset
            print("Found DMG update package")
        } else if let zipAsset = release.assets.first(where: { $0.name.hasSuffix(".app.zip") }) {
            asset = zipAsset
            print("Found ZIP update package")
        } else {
            print("No valid update package found")
            throw UpdateError.noValidAssetFound
        }
        
        guard let downloadURL = URL(string: asset.browserDownloadURL) else {
            print("Invalid download URL")
            throw UpdateError.noValidAssetFound
        }
        
        // Start download
        await MainActor.run {
            isDownloading = true
            downloadProgress = 0
        }
        
        do {
            let (localURL, response) = try await downloadWithProgress(from: downloadURL)
            
            // Verify download
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("Download failed with invalid response")
                throw UpdateError.downloadFailed
            }
            
            // Handle different package types
            if asset.name.hasSuffix(".dmg") {
                print("Processing DMG update")
                // Open DMG file
                NSWorkspace.shared.open(localURL)
                
                // Notify user
                let content = UNMutableNotificationContent()
                content.title = "NeoPaste Update Downloaded"
                content.body = "Please follow the installation instructions in the mounted disk image to complete the update."
                content.sound = .default
                
                let request = UNNotificationRequest(
                    identifier: UUID().uuidString,
                    content: content,
                    trigger: nil
                )
                
                try await UNUserNotificationCenter.current().add(request)
                
            } else if asset.name.hasSuffix(".app.zip") {
                print("Processing ZIP update")
                try await unzipAndInstall(localURL)
            }
            
        } catch {
                    print("Update installation failed: \(error.localizedDescription)")
                    await MainActor.run {
                        isDownloading = false
                        downloadProgress = 0
                    }
                    throw error
                }
                
                // Cleanup runs whether successful or not
                await MainActor.run {
                    isDownloading = false
                    downloadProgress = 0
                }
            }
    
    
    private func downloadWithProgress(from url: URL) async throws -> (URL, URLResponse) {
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        let totalBytes = Int(response.expectedContentLength)
        var downloadedBytes = 0
        
        let temporaryDirectory = FileManager.default.temporaryDirectory
        let destinationURL = temporaryDirectory.appendingPathComponent(url.lastPathComponent)
        
        let fileHandle = try FileHandle(forWritingTo: destinationURL)
        defer { try? fileHandle.close() }
        
        for try await byte in bytes {
            try fileHandle.write(contentsOf: [byte])
            downloadedBytes += 1
            
            if totalBytes > 0 {
                let progress = Double(downloadedBytes) / Double(totalBytes)
                await MainActor.run {
                    self.downloadProgress = progress
                }
            }
        }
        
        return (destinationURL, response)
    }
    
    private var backupURL: URL?
    
    // Add the logging function
    private func logUpdateEvent(_ event: String, error: Error? = nil) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .medium)
        print("[\(timestamp)] Update event: \(event) \(error?.localizedDescription ?? "")")
    }
    
    private func backupCurrentApp() async throws {
        logUpdateEvent("Starting app backup")
        let fileManager = FileManager.default
        
        // Get current app URL
        let currentAppURL = Bundle.main.bundleURL
        
        // Create backup directory
        let backupDir = fileManager.temporaryDirectory.appendingPathComponent("NeoPasteBackup-\(UUID().uuidString)")
        try fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)
        
        // Create backup
        let backupAppURL = backupDir.appendingPathComponent(currentAppURL.lastPathComponent)
        try fileManager.copyItem(at: currentAppURL, to: backupAppURL)
        
        backupURL = backupAppURL
        logUpdateEvent("App backup created successfully")
    }
    
    private func restoreFromBackup() async throws {
        guard let backupURL = backupURL else {
            logUpdateEvent("Restore failed: No backup found")
            throw UpdateError.fileSystemError("No backup found")
        }
        
        logUpdateEvent("Starting app restore from backup")
        let fileManager = FileManager.default
        
        let currentAppURL = Bundle.main.bundleURL
        
        // Remove failed update if exists
        if fileManager.fileExists(atPath: currentAppURL.path) {
            try fileManager.removeItem(at: currentAppURL)
        }
        
        // Restore from backup
        try fileManager.copyItem(at: backupURL, to: currentAppURL)
        logUpdateEvent("App restored successfully from backup")
        
        // Launch restored version
        DispatchQueue.main.async {
            NSWorkspace.shared.open(currentAppURL)
            NSApplication.shared.terminate(nil)
        }
    }
    
    private func cleanupBackup() {
        if let backupURL = backupURL {
            do {
                try FileManager.default.removeItem(at: backupURL)
                logUpdateEvent("Backup cleaned up successfully")
                self.backupURL = nil
            } catch {
                logUpdateEvent("Failed to cleanup backup", error: error)
            }
        }
    }

    
    private func unzipAndInstall(_ zipURL: URL) async throws {
        logUpdateEvent("Starting update installation")
        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory
        let extractDirectory = tempDirectory.appendingPathComponent(UUID().uuidString)
        
        // Create backup first
        try await backupCurrentApp()
        
        do {
            let fileManager = FileManager.default
            let tempDirectory = fileManager.temporaryDirectory
            let extractDirectory = tempDirectory.appendingPathComponent(UUID().uuidString)
            
            // Create temporary directory for extraction
            try fileManager.createDirectory(at: extractDirectory, withIntermediateDirectories: true)
            
            // Unzip the file
            logUpdateEvent("Extracting update package")
            try await Task.detached {
                try fileManager.unzipItem(at: zipURL, to: extractDirectory)
            }.value
            
            // Find the .app in the extracted directory
            let extractedContents = try fileManager.contentsOfDirectory(
                at: extractDirectory,
                includingPropertiesForKeys: nil
            )
            guard let appPath = extractedContents.first(where: { $0.pathExtension == "app" }) else {
                throw UpdateError.installationFailed
            }
            
            // Move to Applications folder
            let applicationsURL = try fileManager.url(
                for: .applicationDirectory,
                in: .localDomainMask,
                appropriateFor: nil,
                create: false
            )
            let destinationURL = applicationsURL.appendingPathComponent(appPath.lastPathComponent)
            
            // Remove existing version if present
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            
            // Move new version to Applications
            try fileManager.moveItem(at: appPath, to: destinationURL)
            
            // Clean up
            try fileManager.removeItem(at: extractDirectory)
            try fileManager.removeItem(at: zipURL)
            
            // If we got here, installation was successful
            cleanupBackup()
            logUpdateEvent("Update installed successfully")
            
            // Launch new version
            DispatchQueue.main.async {
                NSWorkspace.shared.open(destinationURL)
                NSApplication.shared.terminate(nil)
            }
            
        } catch {
            logUpdateEvent("Installation failed, attempting restore", error: error)
            try await restoreFromBackup()
            throw error
        }
    
        
        // Create temporary directory for extraction
        try fileManager.createDirectory(at: extractDirectory, withIntermediateDirectories: true)
        
        // Unzip the file
        try await Task.detached {
            try fileManager.unzipItem(at: zipURL, to: extractDirectory)
        }.value
        
        // Find the .app in the extracted directory
        let extractedContents = try fileManager.contentsOfDirectory(at: extractDirectory,
                                                                  includingPropertiesForKeys: nil)
        guard let appPath = extractedContents.first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError.installationFailed
        }
        
        // Move to Applications folder
        let applicationsURL = try fileManager.url(for: .applicationDirectory,
                                                in: .localDomainMask,
                                                appropriateFor: nil,
                                                create: false)
        let destinationURL = applicationsURL.appendingPathComponent(appPath.lastPathComponent)
        
        // Remove existing version if present
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        
        // Move new version to Applications
        try fileManager.moveItem(at: appPath, to: destinationURL)
        
        // Clean up
        try fileManager.removeItem(at: extractDirectory)
        try fileManager.removeItem(at: zipURL)
        
        // Launch new version
        DispatchQueue.main.async {
            NSWorkspace.shared.open(destinationURL)
            NSApplication.shared.terminate(nil)
        }
    }
    
}

enum UpdateError: Error {
    case noValidAssetFound
    case downloadFailed
    case installationFailed
    case unzipFailed
    case invalidVersionFormat
    case networkError(String)
    case fileSystemError(String)
    case permissionDenied
}


