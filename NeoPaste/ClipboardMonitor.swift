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
import Combine
import os.log

// MARK: - ClipboardError
enum ClipboardError: LocalizedError {
    case invalidContent
    case emptyClipboard
    case saveFailed
    case unsupportedFormat
    case conversionFailed
    case monitoringFailed
    case permissionDenied
    
    var errorDescription: String? {
        switch self {
        case .invalidContent:
            return "The clipboard contains invalid or unsupported content"
        case .emptyClipboard:
            return "The clipboard is empty"
        case .saveFailed:
            return "Failed to save clipboard content"
        case .unsupportedFormat:
            return "The content format is not supported"
        case .conversionFailed:
            return "Failed to convert content to the requested format"
        case .monitoringFailed:
            return "Failed to monitor clipboard changes"
        case .permissionDenied:
            return "Permission denied to access clipboard"
        }
    }
}

// MARK: - ClipboardContent
enum ClipboardContent: Equatable {
    case image(NSImage)
    case text(String)
    case pdf(Data)
    case rtf(Data)
    case file(URL)
    case multiple([URL])
    case empty
    
    var typeDescription: String {
        switch self {
        case .image: return "Image"
        case .text: return "Text"
        case .pdf: return "PDF"
        case .rtf: return "RTF"
        case .file: return "File"
        case .multiple: return "Multiple Files"
        case .empty: return "Empty"
        }
    }
    
    var availableFormats: [String] {
        switch self {
        case .image:
            return SupportedFileTypes.imageExtensions
        case .text, .rtf:
            return SupportedFileTypes.textExtensions
        case .pdf:
            return ["PDF"]
        case .file, .multiple:
            return SupportedFileTypes.compressionExtensions
        case .empty:
            return []
        }
    }
    
    var defaultFormat: String {
        switch self {
        case .image:
            return UserDefaults.standard.string(forKey: UserDefaultsKeys.defaultImageFormat) ?? "png"
        case .text, .rtf:
            return UserDefaults.standard.string(forKey: UserDefaultsKeys.defaultTextFormat) ?? "txt"
        case .pdf:
            return "pdf"
        case .file, .multiple:
            return "zip"
        case .empty:
            return ""
        }
    }
}

@MainActor
class ClipboardMonitor: ObservableObject {
    private static var sharedInstance: ClipboardMonitor?
    private let logger: Logger
    
    static var shared: ClipboardMonitor {
        if let existing = sharedInstance {
            return existing
        }
        let new = ClipboardMonitor()
        sharedInstance = new
        return new
    }
    
    // MARK: - Published Properties
    //@Published private(set) var currentContent: ClipboardContent = .empty
    @Published private(set) var currentContent: ClipboardContent = .text(AppConstants.welcomeMessage)
    private var hasShownWelcomeMessage = false
    @Published private(set) var lastChangeDate: Date?
    @Published private(set) var isMonitoring: Bool = false
    @Published var error: Error?
    
    // MARK: - Private Properties
    private var timer: Timer?
    //private var lastChangeCount: Int = 0
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private let pasteboard = NSPasteboard.general
    private var subscribers = Set<AnyCancellable>()
    private let fileSaver = FileSaver.shared
    
    // MARK: - Initialization

    private init() {
        let subsystem = Bundle.main.bundleIdentifier ?? "com.Falcon.logger"
        self.logger = Logger(subsystem: subsystem, category: "ClipboardMonitor")
        setupNotifications()
        
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
            await performReset()
        }
        handleInitialClipboardContent()
    }
    
    // MARK: - Public Methods
    func startMonitoring() async throws {
            guard !isMonitoring else { return }
            logger.info("Starting clipboard monitoring")
            
            timer = Timer.scheduledTimer(withTimeInterval: AppConstants.clipboardCheckInterval,
                                       repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.checkForChanges()
                }
            }
            
            // Verify that timer was created successfully
            guard timer != nil else {
                let error = NSError(domain: "ClipboardMonitor",
                                  code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "Failed to create monitoring timer"])
                logger.error("Failed to start monitoring: \(error.localizedDescription)")
                throw error
            }
            
            isMonitoring = true
            NotificationCenter.default.post(name: .clipboardMonitoringStarted, object: nil)
        }
    
    func stopMonitoring() {
        logger.info("Stopping clipboard monitoring")
        timer?.invalidate()
        timer = nil
        isMonitoring = false
        NotificationCenter.default.post(name: .clipboardMonitoringStopped, object: nil)
    }
    
    func saveCurrentContent() async throws {
        print("Attempting to save current content: \(self.currentContent)")
        
        switch self.currentContent {
        case .image(let image):
            logger.debug("Saving image...")
            _ = try await fileSaver.saveWithDialog(.image(image))
            
        case .text(let text):
            logger.debug("Saving text...")
            _ = try await fileSaver.saveWithDialog(.text(text))
            
        case .rtf(let data):
            logger.debug("Converting RTF to text...")
            if let attrString = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
                _ = try await fileSaver.saveWithDialog(.text(attrString.string))
            } else {
                throw ClipboardError.conversionFailed
            }
            
        case .pdf(let data):
            logger.debug("Saving PDF...")
            _ = try await fileSaver.saveWithDialog(.pdf(data))
            
        case .file(let url):
            logger.debug("Saving file...")
            _ = try await fileSaver.saveWithDialog(.file(url))
            
        case .multiple(let urls):
            logger.debug("Saving multiple files...")
            _ = try await fileSaver.saveWithDialog(.multiple(urls))
            
        case .empty:
            logger.error("Error: Clipboard is empty")
            throw ClipboardError.emptyClipboard
        }
        
        logger.info("Save completed successfully")
        NotificationCenter.default.post(name: .saveCompleted, object: nil)
    }
    
    // MARK: - Private Methods
    private func handleInitialClipboardContent() {
        Task { [weak self] in
            await self?.updateCurrentContent()
        }
    }
    
    private func checkForChanges() async {
        let currentCount = pasteboard.changeCount
        guard currentCount != lastChangeCount else { return }
        
        logger.debug("Detected clipboard change. Old count: \(self.lastChangeCount), New count: \(currentCount)")
        self.lastChangeCount = currentCount
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second delay
        hasShownWelcomeMessage = true
        await updateCurrentContent()
    }


    
    private func updateCurrentContent() async {
        logger.debug("Updating current content...")
        
        // Show welcome message only once
        if !hasShownWelcomeMessage {
            self.currentContent = .text(AppConstants.welcomeMessage)
            await notifyContentChanged()
            return
        }
        
        // Check for images first
        if let image = NSImage(pasteboard: pasteboard),
           !image.representations.isEmpty {
            logger.debug("Found image in clipboard")
            self.currentContent = .image(image)
            await notifyContentChanged()
            return
        }
        
        // Check for PDF data
        if let pdfData = pasteboard.data(forType: .pdf) {
            logger.debug("Found PDF in clipboard")
            self.currentContent = .pdf(pdfData)
            await notifyContentChanged()
            return
        }
        
        // Check for RTF data
        if let rtfData = pasteboard.data(forType: .rtf) {
            logger.debug("Found RTF in clipboard")
            self.currentContent = .rtf(rtfData)
            await notifyContentChanged()
            return
        }
        
        // Check for plain text
        if let text = pasteboard.string(forType: .string) {
            // Truncate long text in log
            let truncatedText = text.prefix(50)
            logger.debug("Found text in clipboard: \(truncatedText)...")
            self.currentContent = .text(text)
            await notifyContentChanged()
            return
        }
        
        // Check for files
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            logger.debug("Found \(urls.count) files in clipboard")
            self.currentContent = urls.count == 1 ? .file(urls[0]) : .multiple(urls)
            await notifyContentChanged()
            return
        }
        
        logger.debug("No content found in clipboard")
        self.currentContent = .empty
        await notifyContentChanged()
    }
    
    private func notifyContentChanged() async {
        self.lastChangeDate = Date()
        logger.info("Content changed to: \(self.currentContent.typeDescription)")
        
        NotificationCenter.default.post(
            name: .clipboardContentChanged,
            object: nil,
            userInfo: [
                "content": self.currentContent,
                "timestamp": self.lastChangeDate as Any
            ]
        )
    }
    
    private func setupNotifications() {
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                self?.stopMonitoring()
            }
            .store(in: &subscribers)
        
        // Monitor save operations
        NotificationCenter.default.publisher(for: .saveCompleted)
            .sink { [weak self] _ in
                self?.logger.info("Save operation completed successfully")
            }
            .store(in: &subscribers)
        
        NotificationCenter.default.publisher(for: .saveError)
            .sink { [weak self] notification in
                if let error = notification.object as? Error {
                    self?.logger.error("Save operation failed: \(error.localizedDescription)")
                }
            }
            .store(in: &subscribers)
    }
    func resetMonitoring() async throws {
        await performReset()
    }

    private func performReset() async {
        stopMonitoring()
        pasteboard.declareTypes([], owner: nil)
        lastChangeCount = pasteboard.changeCount
        
        do {
            try await startMonitoring()
            handleInitialClipboardContent()
            logger.info("Clipboard monitor reset successfully")
        } catch {
            logger.error("Failed to reset clipboard monitor: \(error.localizedDescription)")
            self.error = error
        }
    }
}

// MARK: - Notification Names Extension
extension Notification.Name {
    static let clipboardMonitoringStarted = Notification.Name("clipboardMonitoringStarted")
    static let clipboardMonitoringStopped = Notification.Name("clipboardMonitoringStopped")
}

// MARK: - Preview Support
#if DEBUG
extension ClipboardMonitor {
    static var preview: ClipboardMonitor {
        let monitor = ClipboardMonitor()
        return monitor
    }
    
    func injectTestContent(_ content: ClipboardContent) {
        self.currentContent = content
        Task {
            await notifyContentChanged()
        }
    }
}
#endif
