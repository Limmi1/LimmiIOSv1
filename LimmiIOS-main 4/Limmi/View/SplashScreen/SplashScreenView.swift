import SwiftUI

struct SplashScreenView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    private var colorApp = AppColor.shared
    @State private var animateGradient = false
    @State private var logoOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var sloganOpacity: Double = 0
    @State private var showMainView = false

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: animateGradient ?
                                   [colorApp.darkNavyBlue, colorApp.darkYellow] :
                                   [colorApp.darkYellow, colorApp.darkNavyBlue]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .animation(.linear(duration: 200).repeatForever(autoreverses: true), value: animateGradient)
            .onAppear {
                animateGradient.toggle()
                // Switch to main view after 2 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showMainView = true
                }
            }

            if showMainView {
                // Navigate back to the main app flow
                RootView()
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "figure.2.and.child.holdinghands")
                        .resizable()
                        .padding(10)
                        .scaledToFit()
                        .frame(width: 140, height: 140)
                        .foregroundColor(.white)
                        .opacity(logoOpacity)
                        .scaleEffect(logoOpacity == 1 ? 1 : 0.8)
                        .cornerRadius(20)
                        .bold()

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
                }
            }
        }
    }
}

#Preview {
    SplashScreenView().environmentObject(AuthViewModel())
}
