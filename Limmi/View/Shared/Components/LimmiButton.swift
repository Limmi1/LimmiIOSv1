import SwiftUI

// MARK: - Limmi Button Component
// A reusable button component with consistent styling using DesignSystem

public struct LimmiButton: View {
    
    // MARK: - Properties
    
    public let title: String
    public let style: ButtonStyle
    public let action: () -> Void
    
    // MARK: - Initializer
    
    public init(
        title: String,
        style: ButtonStyle = DesignSystem.primaryButtonStyle,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.style = style
        self.action = action
    }
    
    // MARK: - Body
    
    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(DesignSystem.bodyText)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .frame(height: DesignSystem.buttonHeight)
                .background(style.backgroundColor)
                .foregroundColor(style.textColor)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                        .stroke(style.borderColor, lineWidth: style.borderWidth)
                )
                .cornerRadius(DesignSystem.cornerRadius)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Button Variants

public struct LimmiButtonVariants {
    
    /// Primary button - golden yellow background with black text
    public static func primary(title: String, action: @escaping () -> Void) -> LimmiButton {
        LimmiButton(title: title, style: DesignSystem.primaryButtonStyle, action: action)
    }
    
    /// Secondary button - dark blue background with white text
    public static func secondary(title: String, action: @escaping () -> Void) -> LimmiButton {
        LimmiButton(title: title, style: DesignSystem.secondaryButtonStyle, action: action)
    }
    
    /// Outline button - transparent background with dark blue border and text
    public static func outline(title: String, action: @escaping () -> Void) -> LimmiButton {
        LimmiButton(title: title, style: DesignSystem.outlineButtonStyle, action: action)
    }
    
    /// Danger button - red background with white text
    public static func danger(title: String, action: @escaping () -> Void) -> LimmiButton {
        let dangerStyle = ButtonStyle(
            backgroundColor: .red,
            textColor: .white,
            borderColor: .red,
            borderWidth: DesignSystem.borderWidth
        )
        return LimmiButton(title: title, style: dangerStyle, action: action)
    }
}

// MARK: - Preview

struct LimmiButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: DesignSystem.spacingL) {
            LimmiButtonVariants.primary(title: "Primary Button") {
                print("Primary tapped")
            }
            
            LimmiButtonVariants.secondary(title: "Secondary Button") {
                print("Secondary tapped")
            }
            
            LimmiButtonVariants.outline(title: "Outline Button") {
                print("Outline tapped")
            }
            
            LimmiButtonVariants.danger(title: "Danger Button") {
                print("Danger tapped")
            }
        }
        .padding(DesignSystem.spacingL)
        .background(DesignSystem.backgroundYellow)
        .previewLayout(.sizeThatFits)
    }
}
