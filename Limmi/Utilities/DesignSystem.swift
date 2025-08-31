import SwiftUI

// MARK: - Limmi Design System
// A comprehensive design system for consistent UI across the Limmi app

public struct DesignSystem {
    
    // MARK: - Colors
    
    /// Primary brand color - muted, warm gold for main actions and highlights
    public static let primaryYellow = Color(hex: "E6B800")
    
    /// Secondary brand color - muted, professional blue for backgrounds and borders
    public static let secondaryBlue = Color(hex: "2E4A6B")
    
    /// Pure white for card backgrounds and light text on dark surfaces
    public static let pureWhite = Color.white
    
    /// Pure black for primary text and strong emphasis
    public static let pureBlack = Color.black
    
    /// Off-white light yellow for main app background - warm and inviting
    public static let backgroundYellow = Color(hex: "F5F0D6")
    
    /// Unified neutral background for homepage
    public static let neutralBackground = Color(hex: "FAFAFA")
    
    /// Subtle yellow off-white background for homepage
    public static let subtleYellowBackground = Color(hex: "FEFCF5")
    
    /// Muted red for blocked/restricted actions
    public static let mutedRed = Color(hex: "C44536")
    
    /// Muted green for allowed/permitted actions
    public static let mutedGreen = Color(hex: "4A7C59")
    
    /// Homepage accent colors for consistent styling
    public static let homepageRed = mutedRed
    public static let homepageGreen = mutedGreen
    public static let homepageBlue = secondaryBlue
    public static let homepageBackground = subtleYellowBackground
    public static let homepageCardBackground = pureWhite
    public static let homepageCardBorder = secondaryBlue.opacity(0.3)
    
    // MARK: - Typography
    
    /// Large heading - 24pt, bold weight
    public static let headingLarge = Font.system(size: 24, weight: .bold, design: .default)
    
    /// Medium heading - 20pt, semibold weight
    public static let headingMedium = Font.system(size: 20, weight: .semibold, design: .default)
    
    /// Small heading - 18pt, semibold weight
    public static let headingSmall = Font.system(size: 18, weight: .semibold, design: .default)
    
    /// Body text - 16pt, regular weight
    public static let bodyText = Font.system(size: 16, weight: .regular, design: .default)
    
    /// Small body text - 14pt, regular weight
    public static let bodyTextSmall = Font.system(size: 14, weight: .regular, design: .default)
    
    /// Caption text - 12pt, regular weight
    public static let captionText = Font.system(size: 12, weight: .regular, design: .default)
    
    // MARK: - Spacing
    
    /// Small spacing - 4pt
    public static let spacingXS: CGFloat = 4
    
    /// Extra small spacing - 8pt
    public static let spacingS: CGFloat = 8
    
    /// Medium spacing - 12pt
    public static let spacingM: CGFloat = 12
    
    /// Large spacing - 16pt
    public static let spacingL: CGFloat = 16
    
    /// Extra large spacing - 24pt
    public static let spacingXL: CGFloat = 24
    
    /// Double extra large spacing - 32pt
    public static let spacingXXL: CGFloat = 32
    
    // MARK: - Component Styles
    
    /// Standard corner radius for cards and buttons
    public static let cornerRadius: CGFloat = 16
    
    /// Corner radius for status chips/badges
    public static let chipCornerRadius: CGFloat = 12
    
    /// Standard shadow for cards
    public static let cardShadow = Shadow(
        color: .black.opacity(0.1),
        radius: 8,
        x: 0,
        y: 2
    )
    
    /// Subtle shadow for buttons and cards
    public static let subtleShadow = Shadow(
        color: .black.opacity(0.08),
        radius: 6,
        x: 0,
        y: 1
    )
    
    /// Standard border width
    public static let borderWidth: CGFloat = 1
    
    /// Button height for primary and secondary buttons
    public static let buttonHeight: CGFloat = 48
    
    /// Input field height
    public static let inputHeight: CGFloat = 44
    
    /// Card padding
    public static let cardPadding: CGFloat = 16
    
    // MARK: - Button Styles
    
    /// Primary button style - golden yellow background with black text
    public static let primaryButtonStyle = ButtonStyle(
        backgroundColor: primaryYellow,
        textColor: pureBlack,
        borderColor: secondaryBlue,
        borderWidth: borderWidth
    )
    
    /// Secondary button style - dark blue background with white text
    public static let secondaryButtonStyle = ButtonStyle(
        backgroundColor: secondaryBlue,
        textColor: pureWhite,
        borderColor: secondaryBlue,
        borderWidth: borderWidth
    )
    
    /// Outline button style - transparent background with dark blue border
    public static let outlineButtonStyle = ButtonStyle(
        backgroundColor: .clear,
        textColor: secondaryBlue,
        borderColor: secondaryBlue,
        borderWidth: borderWidth
    )
}

// MARK: - Supporting Types

/// Shadow configuration for consistent shadows across the app
public struct Shadow {
    public let color: Color
    public let radius: CGFloat
    public let x: CGFloat
    public let y: CGFloat
    
    public init(color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) {
        self.color = color
        self.radius = radius
        self.x = x
        self.y = y
    }
}

/// Button style configuration for consistent button appearance
public struct ButtonStyle {
    public let backgroundColor: Color
    public let textColor: Color
    public let borderColor: Color
    public let borderWidth: CGFloat
    
    public init(backgroundColor: Color, textColor: Color, borderColor: Color, borderWidth: CGFloat) {
        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.borderColor = borderColor
        self.borderWidth = borderWidth
    }
}

// MARK: - Color Extensions

extension Color {
    /// Initialize color from hex string
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - View Modifiers

extension View {
    /// Apply standard card styling
    func limmiCard() -> some View {
        self
            .background(DesignSystem.pureWhite)
            .cornerRadius(DesignSystem.cornerRadius)
            .shadow(
                color: DesignSystem.cardShadow.color,
                radius: DesignSystem.cardShadow.radius,
                x: DesignSystem.cardShadow.x,
                y: DesignSystem.cardShadow.y
            )
            .padding(DesignSystem.cardPadding)
    }
    
    /// Apply standard button styling
    func limmiButton(_ style: ButtonStyle) -> some View {
        self
            .frame(height: DesignSystem.buttonHeight)
            .background(style.backgroundColor)
            .foregroundColor(style.textColor)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                    .stroke(style.borderColor, lineWidth: style.borderWidth)
            )
            .cornerRadius(DesignSystem.cornerRadius)
    }
    
    /// Apply standard input field styling
    func limmiInput() -> some View {
        self
            .frame(height: DesignSystem.inputHeight)
            .background(DesignSystem.pureWhite)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                    .stroke(DesignSystem.secondaryBlue, lineWidth: DesignSystem.borderWidth)
            )
            .cornerRadius(DesignSystem.cornerRadius)
    }
}
