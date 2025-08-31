import SwiftUI

// MARK: - Limmi Card Component
// A reusable card component with consistent styling using DesignSystem

public struct LimmiCard<Content: View>: View {
    
    // MARK: - Properties
    
    public let content: Content
    public let padding: CGFloat
    public let backgroundColor: Color
    public let borderColor: Color
    public let shadow: Shadow
    
    // MARK: - Initializer
    
    public init(
        padding: CGFloat = DesignSystem.cardPadding,
        backgroundColor: Color = DesignSystem.pureWhite,
        borderColor: Color = DesignSystem.secondaryBlue,
        shadow: Shadow = DesignSystem.cardShadow,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
        self.shadow = shadow
        self.content = content()
    }
    
    // MARK: - Body
    
    public var body: some View {
        content
            .padding(padding)
            .background(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                    .stroke(borderColor, lineWidth: DesignSystem.borderWidth)
            )
            .cornerRadius(DesignSystem.cornerRadius)
            .shadow(
                color: shadow.color,
                radius: shadow.radius,
                x: shadow.x,
                y: shadow.y
            )
    }
}

// MARK: - Card Variants

public struct LimmiCardVariants {
    
    /// Standard card with default styling
    public static func standard<Content: View>(
        padding: CGFloat = DesignSystem.cardPadding,
        @ViewBuilder content: () -> Content
    ) -> LimmiCard<Content> {
        LimmiCard(padding: padding, content: content)
    }
    
    /// Elevated card with stronger shadow
    public static func elevated<Content: View>(
        padding: CGFloat = DesignSystem.cardPadding,
        @ViewBuilder content: () -> Content
    ) -> LimmiCard<Content> {
        let elevatedShadow = Shadow(
            color: .black.opacity(0.15),
            radius: 12,
            x: 0,
            y: 4
        )
        return LimmiCard(
            padding: padding,
            shadow: elevatedShadow,
            content: content
        )
    }
    
    /// Subtle card with minimal styling
    public static func subtle<Content: View>(
        padding: CGFloat = DesignSystem.cardPadding,
        @ViewBuilder content: () -> Content
    ) -> LimmiCard<Content> {
        let subtleShadow = Shadow(
            color: .black.opacity(0.05),
            radius: 4,
            x: 0,
            y: 1
        )
        return LimmiCard(
            padding: padding,
            shadow: subtleShadow,
            content: content
        )
    }
    
    /// Accent card with golden yellow border
    public static func accent<Content: View>(
        padding: CGFloat = DesignSystem.cardPadding,
        @ViewBuilder content: () -> Content
    ) -> LimmiCard<Content> {
        LimmiCard(
            padding: padding,
            borderColor: DesignSystem.primaryYellow,
            content: content
        )
    }
}

// MARK: - Preview

struct LimmiCard_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: DesignSystem.spacingL) {
            LimmiCardVariants.standard {
                VStack(alignment: .leading, spacing: DesignSystem.spacingM) {
                    Text("Standard Card")
                        .font(DesignSystem.headingSmall)
                        .foregroundColor(DesignSystem.pureBlack)
                    Text("This is a standard card with default styling.")
                        .font(DesignSystem.bodyText)
                        .foregroundColor(DesignSystem.pureBlack)
                }
            }
            
            LimmiCardVariants.elevated {
                VStack(alignment: .leading, spacing: DesignSystem.spacingM) {
                    Text("Elevated Card")
                        .font(DesignSystem.headingSmall)
                        .foregroundColor(DesignSystem.pureBlack)
                    Text("This card has a stronger shadow for emphasis.")
                        .font(DesignSystem.bodyText)
                        .foregroundColor(DesignSystem.pureBlack)
                }
            }
            
            LimmiCardVariants.accent {
                VStack(alignment: .leading, spacing: DesignSystem.spacingM) {
                    Text("Accent Card")
                        .font(DesignSystem.headingSmall)
                        .foregroundColor(DesignSystem.pureBlack)
                    Text("This card has a golden yellow border.")
                        .font(DesignSystem.bodyText)
                        .foregroundColor(DesignSystem.pureBlack)
                }
            }
        }
        .padding(DesignSystem.spacingL)
        .background(DesignSystem.backgroundYellow)
        .previewLayout(.sizeThatFits)
    }
}
