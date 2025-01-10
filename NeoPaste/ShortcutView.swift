import SwiftUI
import HotKey
import Carbon

struct ShortcutView: View {
    let title: String
    @Binding var keyCombo: KeyCombo?
    let onChange: ((KeyCombo?) -> Void)?
    @State private var isRecording = false
    @State private var currentText = ""
    
    init(
        title: String,
        keyCombo: Binding<KeyCombo?>,
        onChange: ((KeyCombo?) -> Void)? = nil
    ) {
        self.title = title
        self._keyCombo = keyCombo
        self.onChange = onChange
        self._currentText = State(initialValue: keyCombo.wrappedValue?.description ?? "Click to Record")
    }
    
    var body: some View {
        HStack {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            ShortcutRecorderButton(
                isRecording: $isRecording,
                currentText: $currentText,
                keyCombo: $keyCombo,
                onChange: onChange
            )
            .frame(width: 120)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Shortcut Recorder Button
struct ShortcutRecorderButton: View {
    @Binding var isRecording: Bool
    @Binding var currentText: String
    @Binding var keyCombo: KeyCombo?
    let onChange: ((KeyCombo?) -> Void)?
    
    var body: some View {
        Button(action: {
            isRecording.toggle()
        }) {
            Text(isRecording ? "Recording..." : currentText)
                .frame(minWidth: 100)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .background(ShortcutRecorder(isRecording: $isRecording, onChange: { newCombo in
            keyCombo = newCombo
            currentText = newCombo?.description ?? "Click to Record"
            onChange?(newCombo)
            isRecording = false
        }))
    }
}

// MARK: - Shortcut Recorder
struct ShortcutRecorder: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onChange: (KeyCombo?) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = RecorderView()
        view.delegate = context.coordinator
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? RecorderView {
            view.isRecording = isRecording
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(isRecording: $isRecording, onChange: onChange)
    }
    
    class Coordinator: NSObject {
        var isRecording: Binding<Bool>
        let onChange: (KeyCombo?) -> Void
        
        init(isRecording: Binding<Bool>, onChange: @escaping (KeyCombo?) -> Void) {
            self.isRecording = isRecording
            self.onChange = onChange
        }
    }
}

// MARK: - Recorder View
class RecorderView: NSView {
    weak var delegate: ShortcutRecorder.Coordinator?
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
        
        if isValidKeyCombination(keyCode: keyCode, carbonFlags: modifiers) {
            let combo = KeyCombo(carbonKeyCode: keyCode, carbonModifiers: modifiers)
            delegate?.onChange(combo)
        }
    }
    
    private func isValidKeyCombination(keyCode: UInt32, carbonFlags: UInt32) -> Bool {
        // At least one modifier key should be pressed
        let hasModifier = carbonFlags & (UInt32(cmdKey) | UInt32(optionKey) | UInt32(controlKey) | UInt32(shiftKey)) != 0
        
        // Exclude standalone modifier keys
        let isModifierKey = (keyCode == 54 || // Command
                           keyCode == 55 || // Command
                           keyCode == 56 || // Shift
                           keyCode == 57 || // Caps Lock
                           keyCode == 58 || // Option
                           keyCode == 59 || // Control
                           keyCode == 63)   // Function
        
        return hasModifier && !isModifierKey
    }
}

// MARK: - Extensions
extension KeyCombo {
    var description: String {
        var components: [String] = []
        
        if carbonModifiers & UInt32(cmdKey) != 0 { components.append("⌘") }
        if carbonModifiers & UInt32(optionKey) != 0 { components.append("⌥") }
        if carbonModifiers & UInt32(controlKey) != 0 { components.append("⌃") }
        if carbonModifiers & UInt32(shiftKey) != 0 { components.append("⇧") }
        
        if let keyEquivalent = keyEquivalent {
            components.append(keyEquivalent.uppercased())
        }
        
        return components.joined()
    }
    
    private var keyEquivalent: String? {
        let chars: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 32: "U", 31: "O", 35: "P", 37: "L", 38: "J",
            40: "K", 41: ";", 39: "N", 42: "'", 43: ",", 47: ".", 44: "/",
            50: "`"
        ]
        return chars[carbonKeyCode]
    }
}

// MARK: - NSEvent.ModifierFlags Extension
extension NSEvent.ModifierFlags {
    var carbonFlags: UInt32 {
        var carbon: UInt32 = 0
        if contains(.command) { carbon |= UInt32(cmdKey) }
        if contains(.option) { carbon |= UInt32(optionKey) }
        if contains(.control) { carbon |= UInt32(controlKey) }
        if contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }
}

// MARK: - Preview Provider
struct ShortcutView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            ShortcutView(
                title: "Save Clipboard",
                keyCombo: .constant(KeyCombo(carbonKeyCode: 0, carbonModifiers: UInt32(cmdKey)))
            )
            
            ShortcutView(
                title: "Quick Save",
                keyCombo: .constant(nil)
            )
        }
        .padding()
        .frame(width: 300)
    }
}
