import SwiftUI
import HotKey
import UniformTypeIdentifiers
import Carbon
import AppKit
import ServiceManagement
import UserNotifications

// MARK: - ShortcutManager.ShortcutKey Extension
extension ShortcutManager.ShortcutKey {
    var displayName: String {
        switch self {
        case .saveClipboard: return "Save Clipboard"
        }
    }
}

struct PreferencesView: View {
    @StateObject private var shortcutManager = ShortcutManager.shared
    @EnvironmentObject private var clipboardMonitor: ClipboardMonitor
    @State private var selectedTab: SettingsTab = .general
    @Namespace private var animation
    @FocusState private var focusedField: String?
    
    // User preferences
    @AppStorage(UserDefaultsKeys.defaultImageFormat) private var defaultImageFormat = "png"
    @AppStorage(UserDefaultsKeys.defaultTextFormat) private var defaultTextFormat = "txt"
    @AppStorage(UserDefaultsKeys.compressionEnabled) private var compressionEnabled = false
    @AppStorage(UserDefaultsKeys.compressionFormat) private var compressionFormat = "zip"
    @AppStorage(UserDefaultsKeys.showNotifications) private var showNotifications = true
    @AppStorage(UserDefaultsKeys.customSaveLocation) private var customSaveLocation: String?
    @AppStorage(UserDefaultsKeys.darkModeEnabled) private var darkModeEnabled = false
    @AppStorage(UserDefaultsKeys.autoStartEnabled) private var autoStartEnabled = false
    
    var body: some View {
        VStack {
            Spacer(minLength: 20) // Add space between the top of the window and the tab bar
            
            // Custom Tab Bar
            HStack(spacing: 0) { // No spacing between tabs
                ForEach(SettingsTab.allCases.indices, id: \.self) { index in
                    let tab = SettingsTab.allCases[index]
                    
                    Button(action: {
                        focusedField = nil
                        withAnimation {
                            selectedTab = tab
                        }
                    }) {
                        VStack(spacing: 5) {
                            Image(systemName: tab.iconName)
                                .font(.system(size: 20)) // Icon size
                                .foregroundColor(selectedTab == tab ? .blue : .primary)
                            Text(tab.displayName)
                                .font(.system(size: 12, weight: selectedTab == tab ? .bold : .regular))
                                .minimumScaleFactor(0.8) // Dynamically adjust font size
                                .lineLimit(1) // Prevent wrapping
                                .multilineTextAlignment(.center) // Center-align text
                                .foregroundColor(selectedTab == tab ? .blue : .primary)
                        }
                        .padding(.vertical, 10) // Padding for click area
                        .frame(maxWidth: .infinity) // Expand each button to fill available space
                        .contentShape(Rectangle()) // Make the entire frame clickable
                        .background(
                            RoundedRectangle(cornerRadius: 15) // Adjust rounded corners
                                .fill(selectedTab == tab ? Color.gray.opacity(0.2) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .accessibilityElement(children: .contain)
                }
            }
            .padding(.horizontal, 7) // Add internal padding inside the island
            .frame(maxWidth: AppConstants.preferencesWindowSize.width - 50) // Create the "island" effect by limiting width
            .padding(.vertical, 15) // Add vertical padding to emphasize floating effect
            .background(
                RoundedRectangle(cornerRadius: 20) // Background of the tab section with floating effect
                    .fill(Color.gray.opacity(0.1))
            )
            .clipShape(RoundedRectangle(cornerRadius: 20)) // Apply rounded corners to the island
            .padding(.bottom, 2) // Add spacing below the tab section
            
            // Tab Content
            Group {
                switch selectedTab {
                case .general:
                    GeneralSettingsTab()
                        .id(selectedTab)
                        .transition(.opacity)
                case .shortcuts:
                    ShortcutsTab()
                        .id(selectedTab)
                        .transition(.opacity)
                case .formats:
                    FormatsTabView()
                        .id(selectedTab)
                        .transition(.opacity)
                case .advanced:
                    AdvancedTabView()
                        .id(selectedTab)
                        .transition(.opacity)
                case .help:
                    HelpAndSupportTab()
                        .id(selectedTab)
                        .transition(.opacity)
                case .permissions:
                    PermissionsTab()
                        .id(selectedTab)
                        .transition(.opacity)
                case .updates:
                    UpdatesTab()
                        .id(selectedTab)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .onChange(of: selectedTab) { oldValue, newValue in
                focusedField = nil
            }
        }
        .frame(width: AppConstants.preferencesWindowSize.width,
               height: AppConstants.preferencesWindowSize.height)
        .onChange(of: selectedTab) { oldValue, newValue in
            NSApp.keyWindow?.makeFirstResponder(nil)  // Force clear focus
            focusedField = nil
        }
    }
}

// Enum for Settings Tabs
enum SettingsTab: String, CaseIterable {
    case general, shortcuts, formats, advanced, help, permissions, updates

    var displayName: String {
        switch self {
        case .general: return "General"
        case .shortcuts: return "Shortcuts"
        case .formats: return "Formats"
        case .advanced: return "Advanced"
        case .help: return "Help"
        case .permissions: return "Permissions"
        case .updates: return "Updates"
        }
    }

    var iconName: String {
        switch self {
        case .general: return "gear"
        case .shortcuts: return "keyboard"
        case .formats: return "doc.text"
        case .advanced: return "slider.horizontal.3"
        case .help: return "questionmark.circle"
        case .permissions: return "lock.shield"
        case .updates: return "arrow.clockwise.circle"
        }
    }
}


// MARK: - General Settings Tab
struct GeneralSettingsTab: View {
    @AppStorage(UserDefaultsKeys.customSaveLocation) private var customSaveLocation: String?
    @AppStorage(UserDefaultsKeys.showNotifications) private var showNotifications = true
    @AppStorage(UserDefaultsKeys.autoStartEnabled) private var autoStartEnabled = false
    @AppStorage(UserDefaultsKeys.darkModeEnabled) private var darkModeEnabled = false
    @AppStorage(UserDefaultsKeys.useFinderWindow) private var useFinderWindow = false
    @AppStorage(UserDefaultsKeys.previewBeforeSave) private var previewBeforeSave = false
    @AppStorage(UserDefaultsKeys.tempFileLocation) private var tempFileLocation: String?
    @AppStorage(UserDefaultsKeys.menuBarSaveStyle) private var menuBarSaveStyle = "direct"
    @AppStorage(UserDefaultsKeys.shortcutSaveStyle) private var shortcutSaveStyle = "dialog"
    
    var body: some View {
        Form {
            Section {
                Text("**Save Location**") // Bold section title
                    .padding(.bottom, 3)
                if let location = customSaveLocation {
                    Text("Current: \(location)")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                
                Button("Choose Location...") {
                    selectSaveLocation()
                }
                .buttonStyle(.bordered)
                .focusable(false)
            }
            
            Spacer()
                .frame(height: 20)
            
            Section {
                Text("**Save Behavior**") // Bold section title
                    .padding(.bottom, 3)
                Toggle("Use Active Finder Window Path to Save", isOn: $useFinderWindow)
                    .focusable(false)
                    .help("When enabled, shortcuts will save to the active Finder window instead of the default location")
                
                Toggle("Preview Before Save", isOn: $previewBeforeSave)
                    .focusable(false)
                    .help("Preview files in their selected format before saving")
                
                if previewBeforeSave {
                    if let location = tempFileLocation {
                        Text("Temp Files: \(location)")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    
                    Button("Choose Temp Location...") {
                        selectTempLocation()
                    }
                    .buttonStyle(.bordered)
                    .focusable(false)
                }
            }
            
            Spacer()
                .frame(height: 20)
            
            Section {
                Text("**Application**") // Bold section title
                    .padding(.bottom, 3)
                Toggle("Launch at Login", isOn: $autoStartEnabled)
                    .focusable(false)
                    .onChange(of: autoStartEnabled) { oldValue, newValue in
                        updateLaunchAtLogin(enabled: newValue)
                    }
            }
            
            Spacer()
                .frame(height: 25)
        }
        .padding(3)
    }

    
    private func selectSaveLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        
        panel.begin { response in
            if response == .OK, let selectedURL = panel.url {
                customSaveLocation = selectedURL.absoluteString
            }
        }
    }
    
    private func getSaveLocation() -> URL {
            if let customLocationPath = UserDefaults.standard.string(forKey: UserDefaultsKeys.customSaveLocation),
               let customLocation = URL(string: customLocationPath) {
                return customLocation
            } else {
                return DefaultSaveLocation.fallbackSaveLocation
            }
        }
    }
    


    private func updateLaunchAtLogin(enabled: Bool) {
        guard #available(macOS 14.0, *) else {
            print("Launch at login requires macOS 14.0 or later")
            return
        }
        
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            print("Successfully \(enabled ? "enabled" : "disabled") launch at login")
        } catch {
            print("Failed to \(enabled ? "enable" : "disable") launch at login: \(error.localizedDescription)")
        }
    }

    private func selectTempLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose temporary files location for previewing files before saving"
        
        panel.begin { response in
            if response == .OK, let selectedURL = panel.url {
                UserDefaults.standard.set(selectedURL.path, forKey: UserDefaultsKeys.tempFileLocation)
            }
        }

    }




    



// MARK: - Shortcuts Tab
struct ShortcutsTab: View {
    @StateObject private var shortcutManager = ShortcutManager.shared
    
    var body: some View {
        Form {
            Section("Global Shortcuts") {
                ForEach(ShortcutManager.ShortcutKey.allCases, id: \.self) { shortcutKey in
                    ShortcutRecorderView(
                        title: shortcutKey.displayName,
                        shortcutKey: shortcutKey
                    )
                }
            }
        }
        .formStyle(.grouped)  // This helps with spacing
        .padding(.top, -15)   // Reduce top padding
    }
}

// MARK: - ShortcutRecorderView
struct ShortcutRecorderView: View {
    let title: String
    let shortcutKey: ShortcutManager.ShortcutKey
    @StateObject private var shortcutManager = ShortcutManager.shared
    @State private var isRecording = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Button(action: {
                    isRecording.toggle()
                }) {
                    Text(shortcutDisplayText)
                        .frame(width: 120)
                }
                .buttonStyle(.bordered)
                .background(KeyRecorder(isRecording: $isRecording, onKeyCombo: { keyCombo in
                    shortcutManager.setShortcut(keyCombo, forKey: shortcutKey)
                    isRecording = false
                }))
            }
            
            // Add the keyboard language note
            Text("Note: Key symbols shown are based on US keyboard layout. Your shortcuts will work correctly regardless of your keyboard layout.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 4)
        }
        .padding(.vertical, 4)
    }
    
    private var shortcutDisplayText: String {
        if isRecording {
            return "Recording..."
        } else if let keyCombo = shortcutManager.shortcuts[shortcutKey] {
            return keyCombo.description
        } else {
            return "Click to Record"
        }
    }
}

// MARK: - KeyRecorder
struct KeyRecorder: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onKeyCombo: (KeyCombo?) -> Void
    
    func makeNSView(context: Context) -> KeyRecorderView {
        let view = KeyRecorderView()
        view.delegate = context.coordinator
        return view
    }
    
    func updateNSView(_ nsView: KeyRecorderView, context: Context) {
        nsView.isRecording = isRecording
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(isRecording: $isRecording, onKeyCombo: onKeyCombo)
    }
    
    class Coordinator: NSObject {
        var isRecording: Binding<Bool>
        let onKeyCombo: (KeyCombo?) -> Void
        
        init(isRecording: Binding<Bool>, onKeyCombo: @escaping (KeyCombo?) -> Void) {
            self.isRecording = isRecording
            self.onKeyCombo = onKeyCombo
        }
    }
}

// MARK: - KeyRecorderView
class KeyRecorderView: NSView {
    weak var delegate: KeyRecorder.Coordinator?
    var isRecording = false {
        didSet {
            if isRecording {
                self.window?.makeFirstResponder(self)
            } else {
                self.window?.makeFirstResponder(nil)
            }
        }
    }
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        
        let keyCode = UInt32(event.keyCode)
        let modifiers = event.modifierFlags.carbonFlags
        
        if isValidKeyCombination(keyCode: keyCode, carbonModifiers: modifiers) {
            DispatchQueue.main.async {
                let combo = KeyCombo(carbonKeyCode: keyCode, carbonModifiers: modifiers)
                self.delegate?.onKeyCombo(combo)
            }
        }
    }
    override func flagsChanged(with event: NSEvent) {
        // Handle modifier key changes
        if isRecording {
            let keyCode = UInt32(event.keyCode)
            let modifiers = event.modifierFlags.carbonFlags
            
            if isValidKeyCombination(keyCode: keyCode, carbonModifiers: modifiers) {
                DispatchQueue.main.async {
                    let combo = KeyCombo(carbonKeyCode: keyCode, carbonModifiers: modifiers)
                    self.delegate?.onKeyCombo(combo)
                }
            }
        }
    }
    
    func isValidKeyCombination(keyCode: UInt32, carbonModifiers: UInt32) -> Bool {
        let hasModifier = (carbonModifiers & (UInt32(cmdKey) |
                                            UInt32(optionKey) |
                                            UInt32(controlKey) |
                                            UInt32(shiftKey))) != 0
        
        let modifierKeyCodes: Set<UInt32> = [54, 55, 56, 57, 58, 59, 63]
        
        return hasModifier && !modifierKeyCodes.contains(keyCode)
    }
}

// MARK: - Formats Tab
struct FormatsTabView: View {
    @AppStorage(UserDefaultsKeys.defaultImageFormat) private var defaultImageFormat = "png"
    @AppStorage(UserDefaultsKeys.defaultTextFormat) private var defaultTextFormat = "txt"
    @AppStorage(UserDefaultsKeys.compressionEnabled) private var compressionEnabled = false
    @AppStorage(UserDefaultsKeys.compressionFormat) private var compressionFormat = "zip"
    @AppStorage(UserDefaultsKeys.menuBarSaveStyle) private var menuBarSaveStyle = "direct"
    @AppStorage(UserDefaultsKeys.shortcutSaveStyle) private var shortcutSaveStyle = "dialog"
    
    var body: some View {
        VStack(spacing: 8) {
            // Default Formats Section
            VStack(alignment: .leading, spacing: 14) {
                Label("Default Formats", systemImage: "doc.text.magnifyingglass")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center) // Center-align text
                
                // Arrange format options side-by-side
                HStack(spacing: 12) {
                    FormatOption(
                        title: "Image Format",
                        icon: "photo",
                        selection: $defaultImageFormat,
                        options: SupportedFileTypes.imageExtensions
                            
                    )
        
                
                    FormatOption(
                        title: "Text Format",
                        icon: "doc.text",
                        selection: $defaultTextFormat,
                        options: SupportedFileTypes.textExtensions
                            
                    )
                   
                }
            }
            .padding(.horizontal)
            Spacer()
                .frame(height: 15)
            
            // Save Function Section
            VStack(alignment: .leading, spacing: 14) {
                Label("Save Function Preferences", systemImage: "square.and.arrow.down")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                
                SaveStyleOption(
                    title: "MenuBar Save Style",
                    icon: "menubar.dock.rectangle",
                    selection: $menuBarSaveStyle
                        
                )
               
                
                SaveStyleOption(
                    title: "Shortcut Save Style",
                    icon: "command",
                    selection: $shortcutSaveStyle
                        
                )
               
            }
            .padding(.horizontal)
            
            Spacer() // Ensures content fits well without overflow
        }
        .padding(.vertical, 8) // Add padding to top and bottom
    }
}
struct SaveStyleOption: View {
    let title: String
    let icon: String
    @Binding var selection: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(.blue)
                Text(title)
                    .font(.headline)
            }
            
            Picker("", selection: $selection) {
                Text("⚡ Save Directly")
                    .tag("direct")
                            .padding(.leading, -50) // Adjust as necessary for alignment
                    
                
                Text("📂 Save With Dialog")
                    .tag("dialog")
                            .padding(.leading, -50) // Adjust as necessary for alignment
                    
            }
            .pickerStyle(.segmented)
        }
    }
}

struct FormatOption: View {
    let title: String
    let icon: String
    @Binding var selection: String
    let options: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(.blue)
                Text(title)
                    .font(.headline)
            }
            
            Picker("", selection: $selection) {
                ForEach(options, id: \.self) { format in
                    Text(format.uppercased())
                        .tag(format.lowercased())
                }
            }
            .pickerStyle(.menu)
        }
    }
}

// MARK: - Advanced Tab
import SwiftUI

struct AdvancedTabView: View {
    @StateObject private var shortcutManager = ShortcutManager.shared
    @EnvironmentObject private var clipboardMonitor: ClipboardMonitor
    @State private var isResettingPreferences = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showSuccessMessage = false
    @State private var successMessage = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Monitoring Section
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Monitoring", icon: "gauge.with.dots.needle.50percent", color: .blue)
                HStack(spacing: 16) {
                    Button(action: {
                        Task { await resetClipboardMonitor() }
                    }) {
                        ActionButtonContent(
                            title: "Reset Clipboard Monitor",
                            icon: "arrow.clockwise",
                            color: .blue
                        )
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(width: 200, height: 80) // Enforce fixed height
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        clearRecentFiles()
                        showSuccess("Recent files cleared successfully")
                    }) {
                        ActionButtonContent(
                            title: "Clear MenuBar History",
                            icon: "trash",
                            color: .red
                        )
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(width: 200, height: 80) // Enforce fixed height
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
                }

            }
            
            // Preferences Section
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "Preferences", icon: "slider.horizontal.3", color: .purple)
                Button(action: {
                    isResettingPreferences = true
                }) {
                    ActionButtonContent(
                        title: "Reset All Preferences",
                        icon: "arrow.counterclockwise",
                        color: .red,
                        isDestructive: true
                    )
                    .multilineTextAlignment(.center)
                    .frame(width: 416, height: 60)
                }
                .buttonStyle(.plain)
            }
            
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .top) {
            if showSuccessMessage {
                SuccessToast(message: successMessage)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 20)
            }
        }
        .animation(.easeInOut, value: showSuccessMessage)
        .alert("Reset Preferences", isPresented: $isResettingPreferences) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                Task { await resetAllPreferences() }
            }
        } message: {
            Text("Are you sure you want to reset all preferences to default values? This cannot be undone.")
        }
        .alert("Error", isPresented: $showError, presenting: errorMessage) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }
    
    private func showSuccess(_ message: String) {
        successMessage = message
        withAnimation {
            showSuccessMessage = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showSuccessMessage = false
            }
        }
    }
    
    private func resetClipboardMonitor() async {
        do {
            clipboardMonitor.stopMonitoring()
            try await clipboardMonitor.startMonitoring()
            showSuccess("Clipboard monitor reset successfully")
        } catch {
            errorMessage = "Failed to reset clipboard monitor: \(error.localizedDescription)"
            showError = true
        }
    }
    
    private func clearRecentFiles() {
        UserDefaults.standard.removeObject(forKey: "RecentFiles")
        UserDefaults.standard.synchronize()
        NotificationCenter.default.post(name: AppNotification.recentFilesCleared, object: nil)
        MenuBarManager.shared.updateMenu()

    }
    
    private func resetAllPreferences() async {
        do {
            clipboardMonitor.stopMonitoring()
            
            if let bundleID = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: bundleID)
                UserDefaults.standard.synchronize()
            }
            
            for key in ShortcutManager.ShortcutKey.allCases {
                shortcutManager.setShortcut(nil, forKey: key)
            }
            
            try await clipboardMonitor.startMonitoring()
            showSuccess("All preferences reset successfully")
        } catch {
            errorMessage = "Failed to reset preferences: \(error.localizedDescription)"
            showError = true
        }
    }
}

// MARK: - Supporting Views
struct SectionHeader: View {
    let title: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(color)
            Text(title)
                .font(.headline)
        }
    }
}

struct ActionButtonContent: View {
    let title: String
    let icon: String
    let color: Color
    var isDestructive: Bool = false
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(title)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(isDestructive ? Color.red.opacity(0.15) : color.opacity(0.15))
        .foregroundColor(isDestructive ? .red : color)
        .cornerRadius(8)
        .scaleEffect(isHovering ? 1.05 : 1)
        .opacity(isHovering ? 0.9 : 1)
        .animation(.easeInOut(duration: 0.2), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}



// MARK: - Preview
#Preview {
    AdvancedTabView()
        .environmentObject(ClipboardMonitor.shared)
        .frame(width: 600, height: 400)
}

// MARK: - Help and Support Tab
import SwiftUI

struct HelpAndSupportTab: View {
    @State private var showingPopup: PopupType?
    @State private var hoveredCard: String?
    @Environment(\.colorScheme) private var colorScheme
    
    private let githubURL = URL(string: "https://github.com/ariomoniri/NeoPaste")!
    private let bugReportURL = URL(string: "https://github.com/ArioMoniri/NeoPaste/issues/new?assignees=&labels=&projects=&template=bug_report.md&title=")!
    private let featureRequestURL = URL(string: "https://github.com/ArioMoniri/NeoPaste/issues/new?assignees=&labels=&projects=&template=feature_request.md&title=")!
    private let buyMeCoffeeURL = URL(string: "buymeacoffee.com/ariomoniri")!
    
    private let cards = [
        SupportCard(
            title: "Help: Save with Preview",
            description: "Quick guide to using the Cmd + S shortcut in Preview window",
            icon: "questionmark.circle.fill",
            color: .blue,
            type: "Help"
        ),
        SupportCard(
            title: "Support NeoPaste",
            description: "Help keep the project alive with your support",
            icon: "heart.fill",
            color: .orange,
            type: "Support"
        ),
        SupportCard(
            title: "Report a Bug",
            description: "Help us improve by reporting issues",
            icon: "ladybug.fill",
            color: .green,
            type: "BugReport"
        ),
        SupportCard(
            title: "Feature Request",
            description: "Share your ideas to make NeoPaste better",
            icon: "lightbulb.fill",
            color: .purple,
            type: "FeatureRequest"
        )
    ]

    var body: some View {
        ZStack {
            VStack(spacing: 10) {
                // First row
                HStack(spacing: 10) {
                    ForEach(cards.prefix(2)) { card in
                        ModernCard(card: card, isHovered: hoveredCard == card.id.uuidString) {
                            showingPopup = PopupType(type: card.type)
                        }
                        .onHover { isHovered in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                hoveredCard = isHovered ? card.id.uuidString : nil
                            }
                        }
                    }
                }
                
                // Second row
                HStack(spacing: 10) {
                    ForEach(cards.suffix(2)) { card in
                        ModernCard(card: card, isHovered: hoveredCard == card.id.uuidString) {
                            showingPopup = PopupType(type: card.type)
                        }
                        .onHover { isHovered in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                hoveredCard = isHovered ? card.id.uuidString : nil
                            }
                        }
                    }
                }
            }
            .padding(5)

            if let popup = showingPopup {
                
                ModernPopup(type: popup.type, onClose: {
                        showingPopup = nil
                }, onAction: handlePopupAction)
                .transition(.scale.combined(with: .opacity))
            }
        }
    }
    
    private func handlePopupAction(for type: String) {
        switch type {
        case "Support":
            NSWorkspace.shared.open(buyMeCoffeeURL)
        case "BugReport":
            NSWorkspace.shared.open(bugReportURL)
        case "FeatureRequest":
            NSWorkspace.shared.open(featureRequestURL)
        default:
            break
        }
        showingPopup = nil
    }
}

struct SupportCard: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let icon: String
    let color: Color
    let type: String
}

struct ModernCard: View {
    let card: SupportCard
    let isHovered: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: card.icon)
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(card.color)
                        )
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                        .opacity(isHovered ? 1 : 0.5)
                        .offset(x: isHovered ? 8 : 0) // Enhanced hover offset
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(card.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(card.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                ZStack {
                    // Glass effect background
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Material.ultraThinMaterial)
                    
                    // Glass reflection
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.5),
                            Color.white.opacity(0.2),
                            Color.white.opacity(0.0)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .mask(RoundedRectangle(cornerRadius: 16))
                    
                    // Subtle border
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(card.color.opacity(0.3), lineWidth: 1)
                }
            )
            .shadow(color: Color.black.opacity(isHovered ? 0.15 : 0.05),
                   radius: isHovered ? 15 : 5,
                   x: 0, y: isHovered ? 8 : 2)
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isHovered ? 1.03 : 1) // Enhanced scale effect
        .rotation3DEffect(
            .degrees(isHovered ? 2 : 0),
            axis: (x: 0.0, y: 1.0, z: 0.0)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        
    }
}

struct ModernPopup: View {
    let type: String
    let onClose: () -> Void
    let onAction: (String) -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text(type)
                    .font(.title3)
                    .bold()
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.gray)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            ScrollView {
                Text(detailedInformation(for: type))
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineSpacing(4)
            }
            
            if type != "Help" {
                Button(action: { onAction(type) }) {
                    HStack {
                        Text(actionButtonTitle(for: type))
                        Image(systemName: "arrow.right")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(actionButtonColor(for: type))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(20)
        .frame(width: 450)
        .frame(height: 200)// Reduced from 400
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Material.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.2), radius: 20)
        )
    }
    
    private func actionButtonTitle(for type: String) -> String {
        switch type {
        case "Support": return "Support Now"
        case "BugReport": return "Report Bug"
        case "FeatureRequest": return "Submit Request"
        default: return ""
        }
    }
    
    private func actionButtonColor(for type: String) -> Color {
        switch type {
        case "Support": return .orange
        case "BugReport": return .green
        case "FeatureRequest": return .purple
        default: return .blue
        }
    }
    
    private func detailedInformation(for type: String) -> String {
        switch type {
        case "Help":
            return "The 'Save with Preview' feature listens for the Cmd + S shortcut in the Preview window. To automate saving the edited file in the desired format and location, press Cmd + S instead of using the editor's Save button. This ensures quick and accurate saving without additional manual steps. So even if you did not make a change hit Cmd + S to complete the saving process. Also if you have not checked the Preview toggle in preferences ( General Tab ) then this feature will not work since you have not chosen the Temporary location which appears after toggling the feature on (This location can be anywhere the app just saves a draft file there to open preview window and then moves the file to the desired save location after you hit Cmd + S shortcut in previewer app). "
            
        case "Support":
            return "Your support helps maintain and improve NeoPaste. By contributing, you enable us to dedicate more time to development, bug fixes, and new features. Every contribution, no matter the size, makes a difference!"
        case "BugReport":
            return "Found something that's not working right? Help us improve NeoPaste by submitting a detailed bug report. Include steps to reproduce the issue, expected behavior, and any relevant screenshots or error messages."
        case "FeatureRequest":
            return "Have an idea that could make NeoPaste even better? We'd love to hear it! Share your feature suggestions and help shape the future of the application."
        default:
            return ""
        }
    }
}

struct PopupType: Identifiable {
    let id = UUID()
    let type: String
}

#Preview {
    HelpAndSupportTab()
}
struct HelpAndSupportTab_Previews: PreviewProvider {
    static var previews: some View {
        HelpAndSupportTab()
    }
}




// MARK: - Permissions Tab
struct PermissionsTab: View {
    @State private var permissionStates: [String: Bool] = [
        "Notifications": false,
        "Accessibility": false,
        "Files and Folders": false,
        "Automation": false
    ]
    
    var body: some View {
        Form {
            Section("App Permissions") {
                ForEach(Array(permissionStates.keys.sorted()), id: \.self) { permission in
                    HStack {
                        Image(systemName: permissionStates[permission] ?? false ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(permissionStates[permission] ?? false ? .green : .red)
                        Text(permission)
                        Spacer()
                        Button("Open Settings") {
                            openSettings(for: permission)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, -21)
        .frame(maxHeight: .infinity, alignment: .top)
        .frame(height: 300)
        .onAppear {
            checkPermissions()
        }
    }
    
    private func checkPermissions() {
        // We'll check each permission status
        Task {
            await checkNotificationsPermission()
            checkAccessibilityPermission()
            checkFilesPermission()
            checkAutomationPermission()
        }
    }
    
    private func checkPermission(_ permission: String) -> Bool {
        switch permission {
        case "Notifications":
            return UserDefaults.standard.bool(forKey: "NotificationsPermission")
        case "Accessibility":
            return AXIsProcessTrusted()
        case "Files":
            if let saveLocation = UserDefaults.standard.string(forKey: UserDefaultsKeys.customSaveLocation) {
                return FileManager.default.isWritableFile(atPath: saveLocation)
            }
            return false
        case "Automation":
            return true  // You might want a more sophisticated check
        default:
            return false
        }
    }


    
    private func checkNotificationsPermission() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        await MainActor.run {
            permissionStates["Notifications"] = (settings.authorizationStatus == .authorized)
        }
    }
    
    private func checkAccessibilityPermission() {
        let trusted = AXIsProcessTrusted()
        permissionStates["Accessibility"] = trusted
    }
    
    private func checkFilesPermission() {
        // Check if we have access to save location
        if let saveLocation = UserDefaults.standard.string(forKey: UserDefaultsKeys.customSaveLocation) {
            let url = URL(fileURLWithPath: saveLocation)
            permissionStates["Files and Folders"] = FileManager.default.isWritableFile(atPath: url.path)
        }
    }
    
    private func checkAutomationPermission() {
        // This is a bit tricky to check directly, might need to attempt an automation
        permissionStates["Automation"] = true // You might want to implement a more robust check
    }
    
    private func openSettings(for permission: String) {
        switch permission {
        case "Notifications":
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
        case "Accessibility":
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        case "Files":
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
        case "Automation":
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
        default:
            break
        }
    }
    
}



// MARK: - Updates Tab

import SwiftUI


struct UpdatesTab: View {
    @StateObject private var updater = AppUpdater.shared
    @State private var lastChecked: Date?
    @AppStorage("automaticUpdates") private var automaticUpdates = true
    @State private var isCheckingUpdates = false
    @State private var showUpToDate = false
    @State private var showingDownloadProgress = false
    
    private var buttonText: String {  // Here it can be private
        if isCheckingUpdates {
            return "Checking..."
        } else if showUpToDate {
            return "Up to date!"
        } else {
            return "Check for Updates"
        }
    }
    
    var body: some View {
        VStack(spacing: 4) {
            // Current Version Card
            AnimatedGradientCard {
                HStack {
                    HStack(spacing: 12) {
                        Image(systemName: updater.updateAvailable != nil ? "exclamationmark.seal.fill" : "checkmark.seal.fill")
                            .font(.system(size: 24))
                            .foregroundColor(updater.updateAvailable != nil ? .red : .blue)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Current Version")
                                .font(.headline)
                            Text("Your app is on version \(AppConstants.appVersion)")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Image(systemName: updater.updateAvailable != nil ? "xmark.circle.fill" : "checkmark.circle.fill")
                            .foregroundColor(updater.updateAvailable != nil ? .red : .green)
                        Text(updater.updateAvailable != nil ? "Out of date" : "Up to date")
                            .foregroundColor(updater.updateAvailable != nil ? .red : .green)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(updater.updateAvailable != nil ?
                        Color.red.opacity(0.1) :
                        Color.blue.opacity(0.1))
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // Check for Updates Card
            UpdateCard {
                HStack {
                    // Left side with icon and text
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 24))
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Check for Updates")
                                .font(.headline)
                            if let lastChecked = lastChecked {
                                Text("Last checked: \(lastChecked, formatter: dateFormatter)")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Check for Updates Button
                    Button(action: {
                        isCheckingUpdates = true
                        Task {
                            // Ensure minimum animation time
                            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1.5 seconds minimum
                            await checkForUpdates()
                            
                            // Show "Up to date" message
                            withAnimation {
                                isCheckingUpdates = false
                                showUpToDate = true
                            }
                            
                            // Reset back to normal after delay
                            try? await Task.sleep(nanoseconds: 1_000_000_000) // 2 seconds
                            withAnimation {
                                showUpToDate = false
                            }
                        }
                    }) {
                        HStack {
                            HStack(spacing: 4) {
                                if isCheckingUpdates {
                                    Image(systemName: "arrow.clockwise")
                                        .foregroundColor(.white)
                                        .rotationEffect(.degrees(isCheckingUpdates ? 360 : 0))
                                        .animation(
                                            .linear(duration: 1)
                                            .repeatForever(autoreverses: false),
                                            value: isCheckingUpdates
                                        )
                                }
                                Text(buttonText)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            
                        }
                        .frame(width: 200) // Fixed width to prevent text jumping
                        .background(Color.blue)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(isCheckingUpdates || showUpToDate)
                }
                
            }
            
            // Automatic Updates Card
            UpdateCard {
                HStack {
                    // Left side with icon and text
                    HStack(spacing: 12) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Automatic Updates")
                                .font(.headline)
                            Text("Enable automatic checking for updates")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // Dynamic status button
                    Button(action: {
                        withAnimation(.spring()) {
                            automaticUpdates.toggle()
                        }
                    }) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(automaticUpdates ? Color.green : Color.gray)
                                .frame(width: 8, height: 8)
                            Text(automaticUpdates ? "Enabled" : "Disabled")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(automaticUpdates ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(automaticUpdates ? Color.green.opacity(0.3) : Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Spacer()
        }
        .padding()
        .onAppear {
            if automaticUpdates {
                Task {
                    await checkForUpdates()
                }
            }
        }
    }
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    private func checkForUpdates() async {
        do {
            try await updater.checkForUpdates()
            lastChecked = Date()
        } catch {
            print("Error checking for updates: \(error)")
        }
    }
}

// Animated gradient card implementation
struct AnimatedGradientCard<Content: View>: View {
    @State private var phase: CGFloat = 0
    @State private var hoverLocation: CGPoint = .zero
    @State private var isHovering = false
    
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .padding()
            .background(
                GeometryReader { geometry in
                    ZStack {
                        // Base animated gradient
                        LinearGradient(
                            colors: [
                                Color.blue.opacity(0.1),
                                Color.purple.opacity(0.1),
                                Color.blue.opacity(0.1)
                            ],
                            startPoint: UnitPoint(x: phase, y: 0),
                            endPoint: UnitPoint(x: phase + 1, y: 0)
                        )
                        .animation(.linear(duration: 5).repeatForever(autoreverses: false), value: phase)
                        
                        // Hover responsive gradient
                        RadialGradient(
                            colors: [
                                Color.blue.opacity(isHovering ? 0.2 : 0),
                                Color.clear
                            ],
                            center: UnitPoint(
                                x: hoverLocation.x / geometry.size.width,
                                y: hoverLocation.y / geometry.size.height
                            ),
                            startRadius: 0,
                            endRadius: geometry.size.width * 0.5
                        )
                        .animation(.easeOut(duration: 0.3), value: hoverLocation)
                        .animation(.easeOut(duration: 0.3), value: isHovering)
                    }
                }
            )
            .cornerRadius(12)
            .onAppear {
                phase = -1
            }
            .onHover { hovering in
                isHovering = hovering
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        hoverLocation = value.location
                    }
            )
    }
}

// Custom card view for consistent styling
struct UpdateCard<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(.windowBackgroundColor).opacity(0.3))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
    }
}

#Preview {
    UpdatesTab()
        .frame(width: 600, height: 400)
        .preferredColorScheme(.dark)
}

// MARK: - Preview Provider
#Preview {
    PreferencesView()
        .environmentObject(ClipboardMonitor.shared)
}
