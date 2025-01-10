import AppKit
import SwiftUI
import UserNotifications
import os.log

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Singleton
    static let shared: AppDelegate = {
        let instance = AppDelegate()
        instance.setupLogging()
        return instance
    }()
    
    // MARK: - Properties
    private var statusItem: NSStatusItem!
    private var preferencesWindow: NSWindow?
    private let menuBarManager: MenuBarManager
    private let clipboardMonitor: ClipboardMonitor
    private let shortcutManager: ShortcutManager
    private let notificationCenter = UNUserNotificationCenter.current()
    private let permissionManager = PermissionManager.shared
    private let logger: Logger
    
    // MARK: - Initialization
    private override init() {
        let subsystem = Bundle.main.bundleIdentifier ?? "com.yourapp.logger"
        self.logger = Logger(subsystem: subsystem, category: "AppDelegate")
        self.menuBarManager = MenuBarManager.shared
        self.clipboardMonitor = ClipboardMonitor.shared
        self.shortcutManager = ShortcutManager.shared
        super.init()
    }
    
    // MARK: - Application Lifecycle
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do {
                // Initialize system settings
                suppressSystemLogs()
                
                // Request permissions first
                logger.info("Requesting permissions...")
                try await permissionManager.requestPermissions()
                
                // Continue with app setup
                logger.info("Setting up notifications...")
                try await setupNotifications()
                
                logger.info("Setting up UI...")
                try await initializeUI()
                
                logger.info("Starting clipboard monitoring...")
                try await clipboardMonitor.startMonitoring()
                
                logger.info("App initialization completed successfully")
            } catch {
                logger.error("Failed to initialize app: \(error.localizedDescription)")
                
                // Determine which specific permission caused the error
                if let permissionError = error as? PermissionError {
                    handlePermissionError(permissionError)
                } else {
                    // Generic initialization error
                    showGenericInitializationErrorAlert(error)
                }
            }
        }
    }

    private func handlePermissionError(_ error: PermissionError) {
        let alert = NSAlert()
        alert.messageText = "Permission Required"
        
        switch error {
        case .notificationsDenied:
            alert.informativeText = "NeoPaste requires notification permissions to function properly. Would you like to open System Settings?"
        case .accessibilityDenied:
            alert.informativeText = "NeoPaste needs accessibility permissions for keyboard shortcuts. Would you like to open System Settings?"
        case .fileSaveAccessDenied:
            alert.informativeText = "NeoPaste requires file save location permission. Would you like to choose a save location?"
        case .automationDenied:
            alert.informativeText = "NeoPaste needs automation permissions. Would you like to open System Settings?"
        case .shortcutsDenied:
            alert.informativeText = "NeoPaste requires shortcuts permissions. Would you like to open System Settings?"
        }
        
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            switch error {
            case .notificationsDenied:
                permissionManager.showPermissionAlert(for: .notifications)
            case .accessibilityDenied:
                permissionManager.showPermissionAlert(for: .accessibility)
            case .fileSaveAccessDenied:
                Task { @MainActor in
                    do {
                        try await permissionManager.requestFileSaveLocationPermission()
                    } catch {
                        logger.error("Failed to request file save location: \(error.localizedDescription)")
                    }
                }
            case .automationDenied:
                permissionManager.showPermissionAlert(for: .automation)
            case .shortcutsDenied:
                permissionManager.showPermissionAlert(for: .shortcuts)
            }
        }
    }

    private func showGenericInitializationErrorAlert(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Initialization Error"
        alert.informativeText = "Failed to initialize app: \(error.localizedDescription)\n\nThe app may not function correctly."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
        
        private func initializeUI() async throws {
            // Set app as accessory to hide from dock and cmd+tab
            NSApp.setActivationPolicy(.prohibited)
            
            // Setup status item
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = statusItem.button {
                button.image = NSImage(systemSymbolName: "doc.on.clipboard",
                                     accessibilityDescription: "NeoPaste")
            }
            
            // Initial setup
            updateStatusIcon(for: clipboardMonitor.currentContent)
            setupStatusMenu()
        }
        
        private func startMonitoring() async throws {
            guard !clipboardMonitor.isMonitoring else { return }
            try await clipboardMonitor.startMonitoring()
        }
    
    private func setupNotifications() async throws {
        // Request notification authorization
        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .sound])
        
        if !granted {
            throw NSError(domain: "AppInitialization",
                         code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "Notification permission denied"])
        }
        
        // Register observers
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleClipboardChange(_:)),
            name: .clipboardContentChanged,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            forName: .saveCompleted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.logger.info("Save operation completed successfully")
        }
        
        NotificationCenter.default.addObserver(
            forName: .saveError,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let error = notification.object as? Error {
                self?.logger.error("Save operation failed: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Setup Methods
    private func setupLogging() {
        if let logFileURL = getLogFileURL() {
            freopen(logFileURL.path, "a+", stdout)
            freopen(logFileURL.path, "a+", stderr)
        }
    }
    
    private func suppressSystemLogs() {
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            UserDefaults.standard.setValue(false, forKey: "NSConstraintBasedLayoutVisualizeMutuallyExclusiveConstraints")
            UserDefaults.standard.setValue(false, forKey: "\(bundleIdentifier).debugPrintingEnabled")
        }
    }
    
    private func getLogFileURL() -> URL? {
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        let bundleID = Bundle.main.bundleIdentifier ?? "com.yourapp"
        let appLogDirectory = appSupportURL.appendingPathComponent(bundleID).appendingPathComponent("Logs")
        
        do {
            try FileManager.default.createDirectory(at: appLogDirectory, withIntermediateDirectories: true)
            return appLogDirectory.appendingPathComponent("app.log")
        } catch {
            print("Failed to create log directory: \(error)")
            return nil
        }
    }
    
    private func setupNotifications() {
        // Register for clipboard change notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleClipboardChange(_:)),
            name: .clipboardContentChanged,
            object: nil
        )
        
        // Register for save notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSaveCompleted),
            name: .saveCompleted,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSaveError(_:)),
            name: .saveError,
            object: nil
        )
    }
    
    private func setupUI() {
        // Set app as accessory to hide from dock and cmd+tab
        NSApp.setActivationPolicy(.prohibited)
        
        // Setup status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "NeoPaste")
        }
        
        // Initial setup
        Task { @MainActor in
            updateStatusIcon(for: clipboardMonitor.currentContent)
            setupStatusMenu()
        }
    }
    
    private func setupStatusMenu() {
        let menu = NSMenu()
        
        // Add Content Info
        let contentInfo = NSMenuItem(title: "Content: \(clipboardMonitor.currentContent.typeDescription)", action: nil, keyEquivalent: "")
        contentInfo.isEnabled = false
        menu.addItem(contentInfo)
        menu.addItem(NSMenuItem.separator())
        
        // Add Save Options based on content type
        setupSaveOptions(in: menu)
        
        menu.addItem(NSMenuItem.separator())
        
        // Add standard menu items
        menu.addItem(withTitle: "Preferences...", action: #selector(showPreferences(_:)), keyEquivalent: ",")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        
        statusItem.menu = menu
    }
    
    private func setupSaveOptions(in menu: NSMenu) {
        let content = clipboardMonitor.currentContent
        
        // Quick Save submenu
        let saveMenu = NSMenu()
        
        switch content {
        case .image:
            for format in ["PNG", "JPEG", "TIFF", "GIF", "HEIC"] {
                saveMenu.addItem(withTitle: "Save as \(format)", action: #selector(saveWithFormat(_:)), keyEquivalent: "")
            }
            
        case .text, .rtf:
            for format in ["TXT", "RTF", "HTML", "MD"] {
                saveMenu.addItem(withTitle: "Save as \(format)", action: #selector(saveWithFormat(_:)), keyEquivalent: "")
            }
            
        case .pdf:
            saveMenu.addItem(withTitle: "Save PDF", action: #selector(saveWithFormat(_:)), keyEquivalent: "")
            
        case .file, .multiple:
            saveMenu.addItem(withTitle: "Save as ZIP", action: #selector(saveWithFormat(_:)), keyEquivalent: "")
            
        case .empty:
            let emptyItem = NSMenuItem(title: "No Content", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            saveMenu.addItem(emptyItem)
        }
        
        let saveMenuItem = NSMenuItem(title: "Save As", action: nil, keyEquivalent: "")
        saveMenuItem.submenu = saveMenu
        menu.addItem(saveMenuItem)
        
        // Add quick save option
        menu.addItem(withTitle: "Quick Save", action: #selector(saveClipboard(_:)), keyEquivalent: "s")
    }
    
    // MARK: - Action Methods
    @objc private func handleClipboardChange(_ notification: Notification) {
        Task { @MainActor in
            updateStatusIcon(for: clipboardMonitor.currentContent)
            setupStatusMenu()
        }
    }
    
    @objc private func handleSaveCompleted() {
        logger.info("Save operation completed successfully")
    }
    
    @objc private func handleSaveError(_ notification: Notification) {
        if let error = notification.object as? Error {
            logger.error("Save operation failed: \(error.localizedDescription)")
        }
    }
    
    @objc func showPreferences(_ sender: Any?) {
        if let preferencesWindow = preferencesWindow {
            preferencesWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let preferencesView = PreferencesView()
            .environmentObject(clipboardMonitor)
            .environmentObject(shortcutManager)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0,
                              width: AppConstants.preferencesWindowSize.width,
                              height: AppConstants.preferencesWindowSize.height),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Preferences"
        window.center()
        window.contentView = NSHostingView(rootView: preferencesView)
        window.isReleasedWhenClosed = false
        window.level = .floating
        preferencesWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func requestFileAccessPermissions() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Files")!)
    }

    func showFileAccessPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "File Access Permission Required"
        alert.informativeText = "This app needs permission to save files. Please go to System Preferences > Security & Privacy > Files and allow access for this application."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Open System Preferences")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            requestFileAccessPermissions()
        }
    }
    
    @objc private func saveWithFormat(_ sender: NSMenuItem) {
        Task {
            do {
                let content = clipboardMonitor.currentContent
                let format = sender.title.replacingOccurrences(of: "Save as ", with: "").lowercased()
                let url = try await FileSaver.shared.saveDirectly(content, format: format)
                logger.info("Content saved successfully at: \(url.path)")
                NotificationCenter.default.post(name: .saveCompleted, object: nil)
            } catch {
                // Check for file access permission errors
                if let nsError = error as NSError?,
                   nsError.domain == NSCocoaErrorDomain,
                   nsError.code == NSFileWriteNoPermissionError {
                    logger.error("File access permission denied")
                    showFileAccessPermissionAlert()
                } else {
                    logger.error("Failed to save with format: \(error.localizedDescription)")
                    NotificationCenter.default.post(name: .saveError, object: error)
                }
            }
        }
    }

    @objc private func saveClipboard(_ sender: Any?) {
        Task {
            do {
                let content = clipboardMonitor.currentContent
                let defaultFormat = content.defaultFormat
                let url = try await FileSaver.shared.saveDirectly(content, format: defaultFormat)
                logger.info("Content saved successfully at: \(url.path)")
                NotificationCenter.default.post(name: .saveCompleted, object: nil)
            } catch {
                // Check for file access permission errors
                if let nsError = error as NSError?,
                   nsError.domain == NSCocoaErrorDomain,
                   nsError.code == NSFileWriteNoPermissionError {
                    logger.error("File access permission denied")
                    showFileAccessPermissionAlert()
                } else {
                    logger.error("Failed to save clipboard: \(error.localizedDescription)")
                    NotificationCenter.default.post(name: .saveError, object: error)
                }
            }
        }
    }
    
    // MARK: - UI Update Methods
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
        
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
    }
}
