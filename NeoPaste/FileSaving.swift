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
import AppKit
import UniformTypeIdentifiers
import ZIPFoundation

// MARK: - FileSavingError
enum FileSavingError: LocalizedError {
    case invalidData
    case conversionFailed
    case compressionFailed
    case invalidFileFormat
    case saveFailed
    case accessDenied
    case userCancelled
    
    var errorDescription: String? {
        switch self {
        case .invalidData:
            return "The clipboard data is invalid or empty"
        case .conversionFailed:
            return "Failed to convert the file to the requested format"
        case .compressionFailed:
            return "Failed to compress the file"
        case .invalidFileFormat:
            return "The selected file format is not supported"
        case .saveFailed:
            return "Failed to save the file"
        case .accessDenied:
            return "Access denied to save location"
        case .userCancelled:
            return "Save operation cancelled"
        }
    }
}

// MARK: - Supporting Types
enum ImageFormat: String, CaseIterable {
    case png = "png"
    case jpeg = "jpg"
    case tiff = "tiff"
    case gif = "gif"
    case heic = "heic"
    
    var contentType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .tiff: return .tiff
        case .gif: return .gif
        case .heic: return .heic
        }
    }
    
    var displayName: String { rawValue.uppercased() }
}

enum TextFormat: String, CaseIterable {
    case txt = "txt"
    case rtf = "rtf"
    case html = "html"
    case markdown = "md"
    
    var contentType: UTType {
        switch self {
        case .txt: return .plainText
        case .rtf: return .rtf
        case .html: return .html
        case .markdown: return .plainText
        }
    }
    
    var displayName: String { rawValue.uppercased() }
}

// MARK: - FileSaver
@MainActor
class FileSaver: @unchecked Sendable {
    static let shared = FileSaver()
    private let fileManager = FileManager.default
    private let defaults = UserDefaults.standard
    
    // Default naming patterns
    private struct DefaultNames {
        static let image = "Image"
        static let text = "Text"
        static let pdf = "Document"
        static let file = "File"
    }
    
    // MARK: - Public Methods
    
        func saveWithDialog(_ content: ClipboardContent) async throws -> URL {
            let contentCopy = content
            
            return try await withCheckedThrowingContinuation { continuation in
                Task { @MainActor in
                    let savePanel = NSSavePanel()
                    savePanel.canCreateDirectories = true
                    savePanel.isExtensionHidden = false
                    savePanel.level = .floating
                    
                    // Set initial directory synchronously before showing panel
                    if defaults.bool(forKey: UserDefaultsKeys.useFinderWindow) {
                        if let finderURL = getActiveFinderWindowPath() {
                            print("Setting directory to Finder location: \(finderURL.path)")
                            savePanel.directoryURL = finderURL
                        } else {
                            print("No active Finder window found, falling back to default location")
                            if let customLocationPath = defaults.string(forKey: UserDefaultsKeys.customSaveLocation),
                               let customLocation = URL(string: customLocationPath) {
                                savePanel.directoryURL = customLocation
                            }
                        }
                    } else if let customLocationPath = defaults.string(forKey: UserDefaultsKeys.customSaveLocation),
                              let customLocation = URL(string: customLocationPath) {
                        savePanel.directoryURL = customLocation
                    }
                    
                    if let directoryURL = savePanel.directoryURL {
                        // Verify the directory exists and is accessible
                        var isDirectory: ObjCBool = false
                        if FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory) && isDirectory.boolValue {
                            print("Directory verified: \(directoryURL.path)")
                        } else {
                            print("Invalid directory, resetting to default")
                            savePanel.directoryURL = nil
                        }
                    }
                    
                    NSApp.activate(ignoringOtherApps: true)
                    
                    // Setup format selection and compression
                    let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 64))
                    
                    // Format selection
                    let formatLabel = NSTextField(labelWithString: "Format:")
                    formatLabel.frame = NSRect(x: 0, y: 32, width: 50, height: 17)
                    
                    let formatPopup = NSPopUpButton(frame: NSRect(x: 55, y: 30, width: 140, height: 25))
                    
                    // Compression checkbox (only for files)
                    let compressionCheckbox = NSButton(checkboxWithTitle: "Compress", target: nil, action: nil)
                    compressionCheckbox.frame = NSRect(x: 0, y: 5, width: 140, height: 20)
                    compressionCheckbox.state = defaults.bool(forKey: "compressFiles") ? .on : .off
                    
                    // Configure based on content type
                    let defaultName: String
                    var selectedFormat: String = ""
                    
                    switch contentCopy {
                    case .image:
                        defaultName = generateDefaultName(base: DefaultNames.image)
                        formatPopup.addItems(withTitles: ImageFormat.allCases.map { $0.displayName })
                        selectedFormat = defaults.string(forKey: "defaultImageFormat") ?? "PNG"
                        
                        // Find the index of the selected format and select it
                        if let index = formatPopup.itemTitles.firstIndex(of: selectedFormat) {
                            formatPopup.selectItem(at: index)
                        }
                        compressionCheckbox.isHidden = true
                        
                        savePanel.nameFieldStringValue = "\(defaultName).\(selectedFormat.lowercased())"
                        
                        // Add action to update filename when format changes
                        formatPopup.target = formatPopup
                        
                    case .text, .rtf:
                        defaultName = generateDefaultName(base: DefaultNames.text)
                        formatPopup.addItems(withTitles: TextFormat.allCases.map { $0.displayName })
                        selectedFormat = defaults.string(forKey: "defaultTextFormat") ?? "TXT"
                        
                        // Find the index of the selected format and select it
                        if let index = formatPopup.itemTitles.firstIndex(of: selectedFormat) {
                            formatPopup.selectItem(at: index)
                        }
                        compressionCheckbox.isHidden = true
                        
                        savePanel.nameFieldStringValue = "\(defaultName).\(selectedFormat.lowercased())"
                        
                        
                    case .pdf:
                        defaultName = generateDefaultName(base: DefaultNames.pdf)
                        formatPopup.addItems(withTitles: ["PDF"])
                        savePanel.allowedContentTypes = [.pdf]
                        compressionCheckbox.isHidden = true
                        
                    case .file, .multiple:
                        defaultName = generateDefaultName(base: DefaultNames.file)
                        formatPopup.isHidden = true
                        formatLabel.isHidden = true
                        compressionCheckbox.isHidden = true
                        savePanel.allowedContentTypes = [.zip]
                        
                    case .empty:
                        continuation.resume(throwing: FileSavingError.invalidData)
                        return
                    }
                    
                    // Update allowed types based on format selection
                    // After configuring the formatPopup
                    formatPopup.action = #selector(savePanel.validateVisibleColumns)
                    formatPopup.target = savePanel
                    
                    accessoryView.addSubview(formatLabel)
                    accessoryView.addSubview(formatPopup)
                    accessoryView.addSubview(compressionCheckbox)
                    savePanel.accessoryView = accessoryView
                    
                    
                    // Set initial name and extension
                    savePanel.nameFieldStringValue = defaultName
                    
                    savePanel.begin { result in
                        if result == .OK {
                            Task {
                                do {
                                    let selectedFormat = formatPopup.titleOfSelectedItem?.lowercased() ?? ""
                                    let compress = compressionCheckbox.state == .on
                                    
                                    // Update compression preference
                                    self.defaults.set(compress, forKey: "compressFiles")
                                    
                                    // Ensure correct extension
                                    var finalURL = savePanel.url!
                                    if !selectedFormat.isEmpty {
                                        finalURL = finalURL.deletingPathExtension().appendingPathExtension(selectedFormat)
                                    }
                                    
                                    let savedURL = try await self.saveContent(
                                        contentCopy,
                                        format: selectedFormat,
                                        destination: finalURL,
                                        compress: compress
                                    )
                                    continuation.resume(returning: savedURL)
                                } catch {
                                    continuation.resume(throwing: error)
                                }
                            }
                        } else {
                            continuation.resume(throwing: FileSavingError.userCancelled)
                        }
                    }
                }
            }
        }
        
    func saveDirectly(_ content: ClipboardContent, format: String) async throws -> URL {
        print("Attempting to save directly with format: \(format)")
        
        // Check if default save location exists
        guard let defaultSaveLocationData = defaults.data(forKey: UserDefaultsKeys.customSaveLocation) else {
            print("No default save location found in UserDefaults")
            // Attempt to select save location if not set
            try await selectSaveLocation()
            throw FileSavingError.accessDenied
        }
        
        do {
            // Use URL bookmark resolution instead of NSKeyedUnarchiver
            var isStale = false
            let savedLocation = try URL(
                resolvingBookmarkData: defaultSaveLocationData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            
            // Start accessing security-scoped resource
            guard savedLocation.startAccessingSecurityScopedResource() else {
                print("Failed to access security-scoped resource")
                throw FileSavingError.accessDenied
            }
            
            // Ensure we stop accessing the resource
            defer {
                savedLocation.stopAccessingSecurityScopedResource()
            }
            
            // Verify save location is accessible
            let fileManager = FileManager.default
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: savedLocation.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                print("Save location does not exist or is not a directory")
                throw FileSavingError.accessDenied
            }
            
            // Check write permissions
            guard fileManager.isWritableFile(atPath: savedLocation.path) else {
                print("No write permissions for save location")
                throw FileSavingError.accessDenied
            }
            
            // Recreate bookmark if stale
            if isStale {
                print("Bookmark is stale, recreating...")
                let newBookmarkData = try savedLocation.bookmarkData(options: .withSecurityScope)
                defaults.set(newBookmarkData, forKey: UserDefaultsKeys.customSaveLocation)
            }
            
            // Generate filename with proper extension
            let filename = generateDefaultName(for: content, format: format.lowercased())
            let destination = savedLocation.appendingPathComponent(filename)
            
            // Get compression preference
            let compress = defaults.bool(forKey: UserDefaultsKeys.compressFiles)
            
            // Attempt to save content
            return try await saveContent(
                content,
                format: format.lowercased(),
                destination: destination,
                compress: compress
            )
        } catch {
            print("Save directly failed: \(error.localizedDescription)")
            
            // Detailed error logging
            if let nsError = error as NSError? {
                print("Detailed error - Domain: \(nsError.domain), Code: \(nsError.code)")
            }
            
            // Attempt to select save location if access is denied
            try await selectSaveLocation()
            throw FileSavingError.accessDenied
        }
    }

    // Add this method to your class
    private func selectSaveLocation() async throws {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.title = "Select Save Location"
        openPanel.message = "Choose a folder to save your files"
        
        let response = openPanel.runModal()
        
        guard response == .OK, let selectedURL = openPanel.url else {
            throw FileSavingError.accessDenied
        }
        
        do {
            // Create a security-scoped bookmark
            let bookmarkData = try selectedURL.bookmarkData(options: .withSecurityScope)
            defaults.set(bookmarkData, forKey: UserDefaultsKeys.customSaveLocation)
        } catch {
            print("Failed to create bookmark: \(error.localizedDescription)")
            throw FileSavingError.accessDenied
        }
    }
    
    
    
    // MARK: - Private Methods
    
    struct SavePreferences {
        let format: String
        let location: URL
        let compress: Bool
    }
    
    private func getActiveFinderWindowPath() -> URL? {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else {
            print("Finder is not frontmost application")
            return nil
        }

        let script = """
        tell application "Finder"
            if (count of windows) > 0 then
                try
                    get POSIX path of (target of front window as alias)
                on error
                    get POSIX path of (desktop as alias)
                end try
            end if
        end tell
        """
        
        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        
        if let pathString = appleScript?.executeAndReturnError(&error).stringValue {
            print("Found Finder path: \(pathString)")
            return URL(fileURLWithPath: pathString, isDirectory: true)
        } else if let error = error {
            print("AppleScript error: \(error)")
        }
        
        return nil
    }
    
    
    private func generateDefaultName(base: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        return "\(base)_\(dateFormatter.string(from: Date()))"
    }
    
    private func getDefaultFormat(for content: ClipboardContent) -> String {
        switch content {
        case .image:
            return defaults.string(forKey: "defaultImageFormat")?.lowercased() ?? "png"
        case .text, .rtf:
            return defaults.string(forKey: "defaultTextFormat")?.lowercased() ?? "txt"
        case .pdf:
            return "pdf"
        case .file, .multiple:
            return "zip"
        case .empty:
            return ""
        }
    }

    private func generateDefaultName(for content: ClipboardContent, format: String?) -> String {
        let base: String
        switch content {
        case .image:
            base = DefaultNames.image
        case .text, .rtf:
            base = DefaultNames.text
        case .pdf:
            base = DefaultNames.pdf
        case .file, .multiple:
            base = DefaultNames.file
        case .empty:
            base = "Empty"
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let ext = format?.lowercased() ?? getDefaultFormat(for: content)
        
        return "\(base)_\(timestamp).\(ext)"
    }
    
    private func saveContent(_ content: ClipboardContent, format: String, destination: URL, compress: Bool) async throws -> URL {
        let finalURL = compress ? destination.deletingPathExtension().appendingPathExtension("zip") : destination
        
        switch content {
        case .image(let image):
            guard let imageFormat = ImageFormat(rawValue: format.lowercased()) else {
                throw FileSavingError.invalidFileFormat
            }
            return try await saveImage(image, format: imageFormat, to: finalURL)
            
        case .text(let text):
            guard let textFormat = TextFormat(rawValue: format.lowercased()) else {
                throw FileSavingError.invalidFileFormat
            }
            return try await saveText(text, format: textFormat, to: finalURL)
            
        case .rtf(let data):
            if let attrString = try? NSAttributedString(data: data,
                                                      options: [.documentType: NSAttributedString.DocumentType.rtf],
                                                      documentAttributes: nil) {
                guard let textFormat = TextFormat(rawValue: format.lowercased()) else {
                    throw FileSavingError.invalidFileFormat
                }
                return try await saveText(attrString.string, format: textFormat, to: finalURL)
            }
            throw FileSavingError.conversionFailed
            
        case .pdf(let data):
            try data.write(to: finalURL)
            return finalURL
            
        case .file(let singleURL):
            return try await compressFiles([singleURL], to: finalURL, compress: compress)
            
        case .multiple(let urls):
            return try await compressFiles(urls, to: finalURL, compress: compress)
            
        case .empty:
            throw FileSavingError.invalidData
        }
    }
    
    private func saveImage(_ image: NSImage, format: ImageFormat, to destination: URL) async throws -> URL {
        guard let data = try await convertImage(image, to: format) else {
            throw FileSavingError.conversionFailed
        }
        try data.write(to: destination)
        return destination
    }
    
    private func saveText(_ text: String, format: TextFormat, to destination: URL) async throws -> URL {
        let data = try await convertText(text, to: format)
        try data.write(to: destination)
        return destination
    }
    
    private func compressFiles(_ urls: [URL], to destination: URL, compress: Bool) async throws -> URL {
        guard !urls.isEmpty else { throw FileSavingError.invalidData }
        
        if compress {
            try fileManager.zipItem(at: urls[0], to: destination)
            return destination
        } else if urls.count == 1 {
            try fileManager.copyItem(at: urls[0], to: destination)
            return destination
        } else {
            // If multiple files and no compression, create a folder
            let folderURL = destination.deletingPathExtension()
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
            
            for url in urls {
                let destinationFile = folderURL.appendingPathComponent(url.lastPathComponent)
                try fileManager.copyItem(at: url, to: destinationFile)
            }
            return folderURL
        }
    }

    private func convertImage(_ image: NSImage, to format: ImageFormat) async throws -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw FileSavingError.conversionFailed
        }
        
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        
        switch format {
        case .png:
            return bitmapRep.representation(using: .png, properties: [:])
        case .jpeg:
            return bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
        case .tiff:
            return bitmapRep.representation(using: .tiff, properties: [:])
        case .gif:
            return bitmapRep.representation(using: .gif, properties: [:])
        case .heic:
            if #available(macOS 11.0, *) {
                let bitmapData = NSMutableData()
                let destination = CGImageDestinationCreateWithData(
                    bitmapData as CFMutableData,
                    UTType.heic.identifier as CFString,
                    1,
                    nil
                )
                
                guard let destination = destination else {
                    throw FileSavingError.conversionFailed
                }
                
                let options: [CFString: Any] = [
                    kCGImageDestinationLossyCompressionQuality: 0.8,
                    kCGImageDestinationOptimizeColorForSharing: true
                ]
                
                CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
                guard CGImageDestinationFinalize(destination) else {
                    throw FileSavingError.conversionFailed
                }
                
                return bitmapData as Data
            } else {
                throw FileSavingError.invalidFileFormat
            }
        }
    }
    
    private func convertText(_ text: String, to format: TextFormat) async throws -> Data {
        switch format {
        case .txt:
            guard let data = text.data(using: .utf8) else {
                throw FileSavingError.conversionFailed
            }
            return data
            
        case .rtf:
            let attrs = [NSAttributedString.DocumentAttributeKey.documentType: NSAttributedString.DocumentType.rtf]
            return try NSAttributedString(string: text).data(
                from: NSRange(location: 0, length: text.count),
                documentAttributes: attrs
            )
            
        case .html:
            let attrs = [NSAttributedString.DocumentAttributeKey.documentType: NSAttributedString.DocumentType.html]
            return try NSAttributedString(string: text).data(
                from: NSRange(location: 0, length: text.count),
                documentAttributes: attrs
            )
            
        case .markdown:
            guard let data = text.data(using: .utf8) else {
                throw FileSavingError.conversionFailed
            }
            return data
        }
    }
}
