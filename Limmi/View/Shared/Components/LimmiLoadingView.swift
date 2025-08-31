import SwiftUI

// MARK: - Limmi Loading View Component
// A reusable loading component with spinner and skeleton loading using DesignSystem

public struct LimmiLoadingView: View {
    
    // MARK: - Properties
    
    public let type: LoadingType
    public let message: String?
    public let size: CGFloat
    
    // MARK: - Initializer
    
    public init(
        type: LoadingType = .spinner,
        message: String? = nil,
        size: CGFloat = 40
    ) {
        self.type = type
        self.message = message
        self.size = size
    }
    
    // MARK: - Body
    
    public var body: some View {
        VStack(spacing: DesignSystem.spacingM) {
            switch type {
            case .spinner:
                spinnerView
            case .skeleton:
                skeletonView
            case .dots:
                dotsView
            case .pulse:
                pulseView
            }
            
            if let message = message {
                Text(message)
                    .font(DesignSystem.bodyTextSmall)
                    .foregroundColor(DesignSystem.secondaryBlue)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    // MARK: - Loading Views
    
    private var spinnerView: some View {
        ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: DesignSystem.primaryYellow))
            .scaleEffect(size / 20)
    }
    
    private var skeletonView: some View {
        RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
            .fill(DesignSystem.secondaryBlue.opacity(0.1))
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                    .stroke(DesignSystem.secondaryBlue.opacity(0.3), lineWidth: 1)
            )
    }
    
    private var dotsView: some View {
        HStack(spacing: DesignSystem.spacingS) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(DesignSystem.primaryYellow)
                    .frame(width: size / 4, height: size / 4)
                    .scaleEffect(dotScale(for: index))
                    .animation(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                        value: UUID()
                    )
            }
        }
    }
    
    private var pulseView: some View {
        Circle()
            .fill(DesignSystem.primaryYellow)
            .frame(width: size, height: size)
            .scaleEffect(pulseScale)
            .opacity(pulseOpacity)
            .animation(
                Animation.easeInOut(duration: 1.0)
                    .repeatForever(autoreverses: false),
                value: UUID()
            )
    }
    
    // MARK: - Animation States
    
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 1.0
    
    private func dotScale(for index: Int) -> CGFloat {
        // This will be animated by the animation modifier
        return 1.0
    }
    
    // MARK: - Lifecycle
    
    public func onAppear() {
        // Start pulse animation
        withAnimation(Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: false)) {
            pulseScale = 1.5
            pulseOpacity = 0.0
        }
    }
}

// MARK: - Loading Types

public enum LoadingType {
    case spinner      // Circular progress indicator
    case skeleton     // Placeholder shape
    case dots         // Animated dots
    case pulse        // Pulsing circle
}

// MARK: - Loading View Variants

public struct LimmiLoadingViewVariants {
    
    /// Standard spinner loading
    public static func spinner(
        message: String? = nil,
        size: CGFloat = 40
    ) -> LimmiLoadingView {
        LimmiLoadingView(type: .spinner, message: message, size: size)
    }
    
    /// Skeleton loading for content placeholders
    public static func skeleton(
        message: String? = nil,
        size: CGFloat = 40
    ) -> LimmiLoadingView {
        LimmiLoadingView(type: .skeleton, message: message, size: size)
    }
    
    /// Animated dots loading
    public static func dots(
        message: String? = nil,
        size: CGFloat = 40
    ) -> LimmiLoadingView {
        LimmiLoadingView(type: .dots, message: message, size: size)
    }
    
    /// Pulsing circle loading
    public static func pulse(
        message: String? = nil,
        size: CGFloat = 40
    ) -> LimmiLoadingView {
        LimmiLoadingView(type: .pulse, message: message, size: size)
    }
}

// MARK: - Skeleton Content Views

public struct LimmiSkeletonContent {
    
    /// Skeleton text line
    public static func textLine(width: CGFloat, height: CGFloat = 16) -> some View {
        RoundedRectangle(cornerRadius: DesignSystem.cornerRadius / 2)
            .fill(DesignSystem.secondaryBlue.opacity(0.1))
            .frame(width: width, height: height)
    }
    
    /// Skeleton card
    public static func card(width: CGFloat, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingM) {
            textLine(width: width * 0.7, height: 20)
            textLine(width: width * 0.9, height: 16)
            textLine(width: width * 0.6, height: 16)
        }
        .padding(DesignSystem.spacingM)
        .background(DesignSystem.pureWhite)
        .cornerRadius(DesignSystem.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                .stroke(DesignSystem.secondaryBlue.opacity(0.3), lineWidth: 1)
        )
    }
    
    /// Skeleton button
    public static func button(width: CGFloat, height: CGFloat = 48) -> some View {
        RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
            .fill(DesignSystem.secondaryBlue.opacity(0.1))
            .frame(width: width, height: height)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                    .stroke(DesignSystem.secondaryBlue.opacity(0.3), lineWidth: 1)
            )
    }
}

// MARK: - Preview

struct LimmiLoadingView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: DesignSystem.spacingXL) {
            LimmiLoadingViewVariants.spinner(message: "Loading...")
            
            LimmiLoadingViewVariants.skeleton(message: "Loading content...")
            
            LimmiLoadingViewVariants.dots(message: "Processing...")
            
            LimmiLoadingViewVariants.pulse(message: "Please wait...")
            
            // Skeleton content examples
            VStack(spacing: DesignSystem.spacingM) {
                LimmiSkeletonContent.textLine(width: 200)
                LimmiSkeletonContent.textLine(width: 150)
                LimmiSkeletonContent.button(width: 120)
            }
        }
        .padding(DesignSystem.spacingL)
        .background(DesignSystem.backgroundYellow)
        .previewLayout(.sizeThatFits)
    }
}
