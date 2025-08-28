import SwiftUI

struct SplashScreenView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    private var colorApp = AppColor.shared
    @State private var animateGradient = false
    @State private var logoOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var sloganOpacity: Double = 0
    @State private var showMainView = false
    @State private var logoRotation: Double = 0
    @State private var colorIntensity: Double = 0.7
    @State private var fadeOutOpacity: Double = 1.0

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    colorApp.darkNavyBlue.opacity(0.6 + colorIntensity * 0.4),
                    colorApp.darkYellow.opacity(0.5 + colorIntensity * 0.5)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .onAppear {
                // Start breathing animation
                withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) {
                    colorIntensity = 1.0
                }
                
                // Switch to main view after 1.5 seconds with fade transition
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        fadeOutOpacity = 0.0
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        showMainView = true
                    }
                }
            }

            if showMainView {
                // Navigate back to the main app flow
                RootView()
                    .opacity(fadeOutOpacity)
                    .transition(.opacity.combined(with: .scale))
            } else {
                VStack(spacing: 14) {
                    Image("Limmi Logo Only (Transparent) copy")
                        .resizable()
                        .padding(10)
                        .scaledToFit()
                        .frame(width: 140, height: 140)
                        .opacity(logoOpacity)
                        .scaleEffect(logoOpacity == 1 ? 1 : 0.8)
                        .cornerRadius(20)
                        .rotationEffect(.degrees(logoRotation))

                    Text("My Family is Safe with Limmi")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .opacity(textOpacity)

                    Text("Your Safety is Our Priority")
                        .font(.system(size: 18, weight: .thin, design: .rounded))
                        .foregroundColor(.white)
                        .opacity(sloganOpacity)
                        .padding(.top, 10)
                        .bold()
                }
                .onAppear {
                    withAnimation(.easeOut(duration: 1.2)) {
                        logoOpacity = 1
                    }
                    withAnimation(.easeOut(duration: 1.6).delay(0.4)) {
                        textOpacity = 1
                    }
                    withAnimation(.easeOut(duration: 1.8).delay(0.8)) {
                        sloganOpacity = 1
                    }
                    
                    // Start spinning animation
                    withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                        logoRotation = 360
                    }
                }
            }
        }
    }
}

#Preview {
    SplashScreenView().environmentObject(AuthViewModel())
}
