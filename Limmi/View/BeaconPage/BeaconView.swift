import SwiftUI

struct BeaconView: View {
    var appColor = AppColor.shared
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var ruleStoreViewModel: RuleStoreViewModel
    var ruleName: String

    var body: some View {
        NavigationStack {
            VStack(spacing: 26) {
                HStack {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Image(systemName: "arrow.left.circle")
                            .resizable()
                            .frame(width: 32, height: 32)
                    }
                    Spacer()
                }
                .padding(.top, 16)
                .padding(.horizontal)

                txtBeacon("Beacon Connection")
                BeaconCard(authViewModel: authViewModel, ruleName: ruleName)
                    .environmentObject(ruleStoreViewModel)
                Spacer()
            }
            .frame(maxHeight: .infinity)
            .navigationBarBackButtonHidden(true)
            .toolbarBackground(appColor.darkNavyBlue, for: .navigationBar)
            .toolbar(.visible, for: .navigationBar)
            .tint(.black)
            .trackScreen("BeaconConnection", screenClass: "BeaconView", additionalParameters: ["rule_name": ruleName])
        }
    }
}

#Preview {
    let authViewModel = AuthViewModel()
    //BeaconView(zoneName: "testZone").environmentObject(authViewModel)
}
