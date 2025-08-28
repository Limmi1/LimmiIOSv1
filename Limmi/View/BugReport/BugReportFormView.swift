import SwiftUI

// MARK: - Bug Report Form View

struct BugReportFormView: View {
    @StateObject private var viewModel: BugReportViewModel
    @Environment(\.dismiss) private var dismiss
    
    init(authViewModel: AuthViewModel) {
        _viewModel = StateObject(wrappedValue: BugReportViewModel(authViewModel: authViewModel))
    }
    
    var body: some View {
        NavigationView {
            Form {
                descriptionSection
                diagnosticsSection
                deviceInfoSection
            }
            .navigationTitle("Report a Bug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(viewModel.isSubmitting)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Submit") {
                        Task {
                            await viewModel.submitBugReport()
                        }
                    }
                    .disabled(!viewModel.isValid || viewModel.isSubmitting)
                    .fontWeight(.semibold)
                }
            }
            .overlay {
                if viewModel.isSubmitting {
                    submissionOverlay
                }
            }
        }
        .alert("Bug Report Submitted", isPresented: $viewModel.showingSuccessAlert) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Thank you for your feedback! We'll investigate the issue and get back to you if needed.")
        }
        .alert("Submission Failed", isPresented: $viewModel.showingErrorAlert) {
            Button("OK") { }
        } message: {
            Text(viewModel.errorMessage)
        }
    }
    
    // MARK: - Section Views
    
    private var descriptionSection: some View {
        Section(header: Text("Describe the Issue")) {
            TextEditor(text: $viewModel.userComment)
                .frame(minHeight: 120)
                .disabled(viewModel.isSubmitting)
                .overlay(
                    Group {
                        if viewModel.userComment.isEmpty {
                            VStack {
                                HStack {
                                    Text("Please provide as much detail as possible about the bug, including steps to reproduce it...")
                                        .foregroundColor(.secondary)
                                        .font(.body)
                                    Spacer()
                                }
                                Spacer()
                            }
                            .padding(.top, 8)
                            .padding(.leading, 4)
                            .allowsHitTesting(false)
                        }
                    }
                )
            
            if !viewModel.userComment.isEmpty {
                Text("Character count: \(viewModel.userComment.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .headerProminence(.increased)
    }
    
    private var diagnosticsSection: some View {
        Section(header: Text("Diagnostics")) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Include log file", isOn: $viewModel.includeLogFile)
                        .disabled(viewModel.isSubmitting || !viewModel.hasLogFile)
                    
                    if !viewModel.hasLogFile {
                        Text("No log file available")
                            .font(.caption)
                            .foregroundColor(.orange)
                    } else if let logSize = viewModel.getLogFileSize(), logSize.contains("MB") {
                        Text("Large files will be truncated to 700KB")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                Spacer()
                
                if viewModel.hasLogFile, let logSize = viewModel.getLogFileSize() {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(logSize)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Image(systemName: "doc.text")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if viewModel.includeLogFile && viewModel.hasLogFile {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                        .font(.caption)
                    
                    Text("Log files help us diagnose technical issues. Large files are automatically truncated. No personal information is included.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .headerProminence(.increased)
    }
    
    private var deviceInfoSection: some View {
        Section(header: Text("Device Information")) {
            InfoRow(title: "Device", value: UIDevice.current.model)
            InfoRow(title: "iOS Version", value: UIDevice.current.systemVersion)
            InfoRow(title: "App Version", value: Bundle.main.appVersionWithBuild)
            
            HStack {
                Text("Report ID")
                    .foregroundColor(.primary)
                Spacer()
                Text("Auto-generated on submission")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .headerProminence(.increased)
    }
    
    private var submissionOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                
                VStack(spacing: 8) {
                    Text("Submitting Report...")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    if viewModel.includeLogFile {
                        Text("Uploading log file...")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
            .padding(40)
            .background(Color.black.opacity(0.8))
            .cornerRadius(20)
        }
    }
}

// MARK: - Info Row Component

struct InfoRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Previews

#if DEBUG
struct BugReportFormView_Previews: PreviewProvider {
    static var previews: some View {
        BugReportFormView(authViewModel: AuthViewModel())
            .preferredColorScheme(.light)
        
        BugReportFormView(authViewModel: AuthViewModel())
            .preferredColorScheme(.dark)
    }
}
#endif