import SwiftUI

public struct LoadingLogoView: View {
    // MARK: - Public Config
    public var imageName: String
    public var size: CGFloat
    public var duration: Double
    public var startAngle: Angle
    public var loop: Bool
    public var lineWidthMultiplier: CGFloat
    public var backgroundColor: Color
    public var onFinished: (() -> Void)?

    // MARK: - State
    @State private var progress: CGFloat = 0.0
    @State private var animationCycle: Int = 0

    public init(
        imageName: String = "yellowbrainblacklinedots copy",
        size: CGFloat = 220,
        duration: Double = 2.2,
        startAngle: Angle = .degrees(-90),   // start from top
        loop: Bool = false,
        lineWidthMultiplier: CGFloat = 1.25,
        backgroundColor: Color = .white,
        onFinished: (() -> Void)? = nil
    ) {
        self.imageName = imageName
        self.size = size
        self.duration = duration
        self.startAngle = startAngle
        self.loop = loop
        self.lineWidthMultiplier = max(1.0, lineWidthMultiplier)
        self.backgroundColor = backgroundColor
        self.onFinished = onFinished
    }

    public var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            Image(imageName)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .mask(revealMask)
                .accessibilityLabel(Text("Loading"))
        }
        .onAppear(perform: startAnimation)
        .task(id: animationCycle) {
            if loop { startAnimation() }
        }
    }

    private var revealMask: some View {
        let lineWidth = size * lineWidthMultiplier

        return Circle()
            .trim(from: 0, to: progress)
            .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(startAngle)
    }

    private func startAnimation() {
        progress = 0
        withAnimation(.easeInOut(duration: duration)) {
            progress = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            if loop {
                animationCycle += 1
            } else {
                onFinished?()
            }
        }
    }
}