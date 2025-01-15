import SwiftUI

enum ModernButtonStyle {
    case normal, destructive
}

struct ModernButton: View {
    let title: String
    let icon: String
    let color: Color
    let style: ModernButtonStyle
    let action: () -> Void
    
    init(
        title: String,
        icon: String,
        color: Color,
        style: ModernButtonStyle = .normal,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.color = color
        self.style = style
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                Text(title)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(buttonBackground)
            .foregroundColor(buttonColor)
            .cornerRadius(8)
            .overlay(buttonBorder)
        }
        .buttonStyle(.plain)
    }
    
    private var buttonBackground: Color {
        style == .normal ? color.opacity(0.2) : Color.red.opacity(0.15)
    }
    
    private var buttonColor: Color {
        style == .normal ? color : .red
    }
    
    private var buttonBorder: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(
                style == .normal ? color.opacity(0.3) : Color.red.opacity(0.3),
                lineWidth: 1
            )
    }
}

struct ModernCards<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    let content: Content
    
    init(
        title: String,
        icon: String,
        iconColor: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.headline)
            }
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.windowBackgroundColor).opacity(0.3))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

struct SuccessToast: View {
    let message: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
            Text(message)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.green.opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.green.opacity(0.3), lineWidth: 1)
                )
        )
        .foregroundColor(.green)
    }
}
