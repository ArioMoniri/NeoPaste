import SwiftUI
import HotKey
import UniformTypeIdentifiers
import Carbon
import AppKit
import ServiceManagement
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
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            ShortcutsTab()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
            
            FormatsTabView()
                .tabItem {
                    Label("Formats", systemImage: "doc.text")
                }
            
            AdvancedTabView()
                .tabItem {
                    Label("Advanced", systemImage: "slider.horizontal.3")
                }
        }
        .frame(width: AppConstants.preferencesWindowSize.width,
               height: AppConstants.preferencesWindowSize.height)
        .padding()
    }
}

// MARK: - General Settings Tab
struct GeneralSettingsTab: View {
    @AppStorage(UserDefaultsKeys.customSaveLocation) private var customSaveLocation: String?
    @AppStorage(UserDefaultsKeys.showNotifications) private var showNotifications = true
    @AppStorage(UserDefaultsKeys.autoStartEnabled) private var autoStartEnabled = false
    @AppStorage(UserDefaultsKeys.darkModeEnabled) private var darkModeEnabled = false
    
    var body: some View {
        Form {
            Section("Save Location") {
                if let location = customSaveLocation {
                    Text("Current: \(location)")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                
                Button("Choose Location...") {
                    selectSaveLocation()
                }
                .buttonStyle(.bordered)
            }
            
            Section("Application") {
                Toggle("Launch at Login", isOn: $autoStartEnabled)
                    .onChange(of: autoStartEnabled) { oldValue, newValue in
                        updateLaunchAtLogin(enabled: newValue)
                    }

            }
        }
        .padding()
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
        guard #available(macOS 13.0, *) else {
            print("Launch at login requires macOS 13.0 or later")
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
            .padding()
        }
    }
}

// MARK: - ShortcutRecorderView
struct ShortcutRecorderView: View {
    let title: String
    let shortcutKey: ShortcutManager.ShortcutKey
    @StateObject private var shortcutManager = ShortcutManager.shared
    @State private var isRecording = false
    
    var body: some View {
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
                window?.makeFirstResponder(self)
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
            let combo = KeyCombo(carbonKeyCode: keyCode, carbonModifiers: modifiers)
            delegate?.onKeyCombo(combo)
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
    
    var body: some View {
        Form {
            Section("Default Formats") {
                Picker("Image Format", selection: $defaultImageFormat) {
                    ForEach(SupportedFileTypes.imageExtensions, id: \.self) { format in
                        Text(format.uppercased())
                    }
                }
                .pickerStyle(.menu)
                
                Picker("Text Format", selection: $defaultTextFormat) {
                    ForEach(SupportedFileTypes.textExtensions, id: \.self) { format in
                        Text(format.uppercased())
                    }
                }
                .pickerStyle(.menu)
            }
            
            //Section("Compression") {
                //Toggle("Enable Compression", isOn: $compressionEnabled)
                
                //if compressionEnabled {
                    //Picker("Compression Format", selection: $compressionFormat) {
                        //ForEach(SupportedFileTypes.compressionExtensions, id: \.self) { format in
                            //Text(format.uppercased())
                        //}
                    //}
                    //.pickerStyle(.menu)
                //}
            //}
        }
        .padding()
    }
}

// MARK: - Advanced Tab
struct AdvancedTabView: View {
    @StateObject private var shortcutManager = ShortcutManager.shared
    @EnvironmentObject private var clipboardMonitor: ClipboardMonitor
    @State private var isResettingPreferences = false
    @State private var errorMessage: String?
    @State private var showError = false
    
    var body: some View {
        Form {
            Section("Monitoring") {
                Button("Reset Clipboard Monitor") {
                    Task {
                        await resetClipboardMonitor()
                    }
                }
                .buttonStyle(.bordered)
                
                Button("Clear Recent Files") {
                    clearRecentFiles()
                }
                .buttonStyle(.bordered)
            }
            
            Section("Preferences") {
                Button("Reset All Preferences") {
                    isResettingPreferences = true
                }
                .buttonStyle(.bordered)
                .alert("Reset Preferences", isPresented: $isResettingPreferences) {
                    Button("Cancel", role: .cancel) {}
                    Button("Reset", role: .destructive) {
                        Task {
                            await resetAllPreferences()
                        }
                    }
                } message: {
                    Text("Are you sure you want to reset all preferences to default values? This cannot be undone.")
                }
            }
            
            Section("About") {
                Text("Version: \(AppConstants.appVersion) (\(AppConstants.appBuild))")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .alert("Error", isPresented: $showError, presenting: errorMessage) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }
    
    private func resetClipboardMonitor() async {
        do {
            clipboardMonitor.stopMonitoring()
            try await clipboardMonitor.startMonitoring()
        } catch {
            errorMessage = "Failed to reset clipboard monitor: \(error.localizedDescription)"
            showError = true
        }
    }
    
    private func clearRecentFiles() {
        UserDefaults.standard.removeObject(forKey: "RecentFiles")
        UserDefaults.standard.synchronize()
    }
    
    private func resetAllPreferences() async {
        do {
            // Stop monitoring first
            clipboardMonitor.stopMonitoring()
            
            // Clear user defaults
            if let bundleID = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: bundleID)
                UserDefaults.standard.synchronize()
            }
            
            // Reset all shortcuts
            for key in ShortcutManager.ShortcutKey.allCases {
                shortcutManager.setShortcut(nil, forKey: key)
            }
            
            // Restart monitoring
            try await clipboardMonitor.startMonitoring()
        } catch {
            errorMessage = "Failed to reset preferences: \(error.localizedDescription)"
            showError = true
        }
    }
}

#Preview {
    AdvancedTabView()
        .environmentObject(ClipboardMonitor.shared)
}

// MARK: - Preview Provider
#Preview {
    PreferencesView()
        .environmentObject(ClipboardMonitor.shared)
}
