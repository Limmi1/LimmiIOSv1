import SwiftUI
import UniformTypeIdentifiers
import FirebaseFirestore

struct ConfigurationView: View {
    @EnvironmentObject var blockingEngineViewModel: BlockingEngineViewModel
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var appSettings = AppSettings.shared
    @State private var showShareSheet = false
    @State private var showNoLogAlert = false
    @State private var logFileProvider: NSItemProvider? = nil
    @State private var showLogoutAlert = false
    @State private var showingBugReport = false

    var body: some View {
        VStack {
            NavigationView {
                Form {
                    Section(header: Text("Account")) {
                        if let user = authViewModel.user {
                            HStack {
                                Image(systemName: "person.crop.circle")
                                    .resizable()
                                    .frame(width: 36, height: 36)
                                    .foregroundColor(.accentColor)
                                VStack(alignment: .leading) {
                                    Text(user.email ?? "No email")
                                        .font(.headline)
                                    Text("Signed in")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("UUID: \(user.uid)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                            .padding(.vertical, 4)
                            Button(role: .destructive) {
                                showLogoutAlert = true
                            } label: {
                                HStack {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                    Text("Log Out")
                                }
                                .foregroundColor(.red)
                            }
                            .alert("Are you sure you want to log out?", isPresented: $showLogoutAlert) {
                                Button("Cancel", role: .cancel) {}
                                Button("Log Out", role: .destructive) {
                                    AnalyticsManager.shared.logEvent("user_logout")
                                    authViewModel.signOut()
                                }
                            }
                        } else {
                            Text("Not signed in.")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Section(header: Text("Protection")) {
                        HStack {
                            Image(systemName: "shield.lefthalf.filled")
                                .foregroundColor(.blue)
                            Text("Blocking Engine Status")
                            Spacer()
                            Text(blockingEngineViewModel.isActive ? "Active" : "Inactive")
                                .foregroundColor(blockingEngineViewModel.isActive ? .green : .gray)
                        }
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Strategy Type", selection: $appSettings.ruleProcessingStrategy) {
                                ForEach(RuleProcessingStrategyType.allCases) { strategy in
                                    Text(strategy.displayName)
                                        .tag(strategy)
                                }
                            }
                            .pickerStyle(.menu)
                            
                            Text(appSettings.ruleProcessingStrategy.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                            Text("This setting affects how rules are processed and can impact performance.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Rule Processing Strategy moved to Protection section above
                    /*
                    Section(header: Text("Advanced Settings")) {
                        Toggle(isOn: $appSettings.enableDetailedLogging) {
                            HStack {
                                Image(systemName: "doc.text.magnifyingglass")
                                    .foregroundColor(.orange)
                                Text("Detailed Logging")
                            }
                        }
                        
                        Toggle(isOn: $appSettings.enablePerformanceMonitoring) {
                            HStack {
                                Image(systemName: "speedometer")
                                    .foregroundColor(.green)
                                Text("Performance Monitoring")
                            }
                        }
                    }*/
                    Section(header: Text("Support")) {
                        Button(action: {
                            showingBugReport = true
                        }) {
                            HStack {
                                Image(systemName: "ladybug.fill")
                                    .foregroundColor(.red)
                                
                                Text("Report a Bug")
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                        .buttonStyle(PlainButtonStyle())
                        
                        /*Button("Share App Log File") {
                            shareLogFile()
                        }
                        .accessibilityLabel("Share the application log file")*/
                    }
                    Section(header: Text("Diagnostics")) {
                        NavigationLink(destination: BeaconLogView()) {
                            Label("Beacon RSSI & Event Log", systemImage: "waveform.path.ecg")
                        }
                        
                    }
                }
                .navigationTitle("Configuration")
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let provider = logFileProvider {
                ShareSheet(activityItems: [provider])
            }
        }
        .sheet(isPresented: $showingBugReport) {
            BugReportFormView(authViewModel: authViewModel)
        }
        .alert("No log file available", isPresented: $showNoLogAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("There is no log file to share yet.")
        }
        .trackScreen("Settings", screenClass: "ConfigurationView")
    }

    private func shareLogFile() {
        // Reset state to ensure sheet will present
        DispatchQueue.main.async {
            logFileProvider = nil
            showShareSheet = false
        }
        DispatchQueue.global(qos: .userInitiated).async {
            guard let tempURL = copyLogFileToTemp(),
                  FileManager.default.fileExists(atPath: tempURL.path),
                  let data = try? Data(contentsOf: tempURL),
                  !data.isEmpty else {
                DispatchQueue.main.async {
                    showNoLogAlert = true
                }
                return
            }
            // Create provider with explicit file attachment behavior
            let provider = NSItemProvider()
            let fileName = "limmi_app_log_\(Date().formatted(.iso8601.year().month().day())).txt"
            
            // Register as file attachment, not text content
            provider.registerFileRepresentation(
                forTypeIdentifier: UTType.plainText.identifier,
                fileOptions: .openInPlace,
                visibility: .all
            ) { completion in
                completion(tempURL, true, nil)
                return nil
            }
            
            // Also register for general file sharing
            provider.registerFileRepresentation(
                forTypeIdentifier: UTType.data.identifier,
                fileOptions: .openInPlace,
                visibility: .all
            ) { completion in
                completion(tempURL, true, nil)
                return nil
            }
            
            provider.suggestedName = fileName
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                logFileProvider = provider
                showShareSheet = true
            }
        }
    }

    private func copyLogFileToTemp() -> URL? {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
        let fileName = "limmi_consolidated_log_\(Date().formatted(.iso8601.year().month().day())).txt"
        let tempURL = tempDir.appendingPathComponent(fileName)
        
        do {
            if fileManager.fileExists(atPath: tempURL.path) {
                try fileManager.removeItem(at: tempURL)
            }
            
            // Use consolidated log file that includes both main app and DAM extension logs
            if let consolidatedLogURL = FileLogger.shared.createConsolidatedLogFile() {
                try fileManager.copyItem(at: consolidatedLogURL, to: tempURL)
                // Clean up the temporary consolidated file
                try? fileManager.removeItem(at: consolidatedLogURL)
            } else {
                // Fallback to current process log file
                let logURL = FileLogger.shared.getLogFileURL()
                try fileManager.copyItem(at: logURL, to: tempURL)
            }
            
            // Set file attributes to ensure it's treated as an attachment
            try fileManager.setAttributes([
                .posixPermissions: 0o644
            ], ofItemAtPath: tempURL.path)
            
            return tempURL
        } catch {
            print("Failed to copy log file to temp: \(error)")
            return nil
        }
    }
    
}

struct ShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let activityVC = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        
        // Configure for file sharing, not content sharing
        activityVC.setValue("Limmi App Log File", forKey: "subject")
        
        return activityVC
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    let authViewModel = AuthViewModel()
    
    // Create protocol-based dependencies
    let locationProvider = CoreLocationProvider()
    let beaconMonitor = CoreLocationBeaconMonitor()
    let clock = SystemClock()
    let ruleStore = FirebaseRuleStore(firestore: Firestore.firestore(), userId: authViewModel.user?.uid ?? "test-user")
    let screenTimeBlocker = ScreenTimeBlocker()
    
    // Create central blocking engine
    let blockingEngine = BlockingEngine(
        locationProvider: locationProvider,
        beaconMonitor: beaconMonitor,
        clock: clock,
        ruleStore: ruleStore,
        blocker: screenTimeBlocker
    )
    
    ConfigurationView()
        .environmentObject(authViewModel)
        .environmentObject(BlockingEngineViewModel(blockingEngine: blockingEngine))
} 
