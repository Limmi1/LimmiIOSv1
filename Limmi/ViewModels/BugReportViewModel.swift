import Foundation
import SwiftUI
import os

// MARK: - Bug Report ViewModel

@MainActor
final class BugReportViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var userComment: String = ""
    @Published var isSubmitting: Bool = false
    @Published var showingSuccessAlert: Bool = false
    @Published var showingErrorAlert: Bool = false
    @Published var errorMessage: String = ""
    @Published var includeLogFile: Bool = true
    
    // MARK: - Private Properties
    
    private let bugReportService: BugReportServiceProtocol
    private let authViewModel: AuthViewModel
    private let logger = UnifiedLogger(
        fileLogger: .shared,
        osLogger: Logger(subsystem: "com.limmi.app", category: "BugReportViewModel")
    )
    
    // MARK: - Initialization
    
    init(bugReportService: BugReportServiceProtocol = AWSBugReportService(), 
         authViewModel: AuthViewModel) {
        self.bugReportService = bugReportService
        self.authViewModel = authViewModel
        
        logger.debug("BugReportViewModel initialized with AWS service")
    }
    
    // MARK: - Computed Properties
    
    var isValid: Bool {
        !userComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var currentLogFileURL: URL? {
        return FileLogger.shared.getLogFileURL()
    }
    
    var hasLogFile: Bool {
        guard let logURL = currentLogFileURL else { return false }
        return FileManager.default.fileExists(atPath: logURL.path)
    }
    
    // MARK: - Public Methods
    
    func submitBugReport() async {
        logger.debug("Submit bug report requested")
        
        guard isValid else {
            logger.error("Bug report validation failed: empty comment")
            errorMessage = "Please provide a description of the issue."
            showingErrorAlert = true
            return
        }
        
        guard let userId = authViewModel.user?.uid else {
            logger.error("Bug report submission failed: user not authenticated")
            errorMessage = "User authentication required to submit bug reports."
            showingErrorAlert = true
            return
        }
        
        isSubmitting = true
        logger.debug("Submitting bug report for user: \(userId)")
        
        let trimmedComment = userComment.trimmingCharacters(in: .whitespacesAndNewlines)
        let report = AWSBugReport(userId: userId, userComment: trimmedComment)
        
        // Pass nil to trigger comprehensive log upload (includes both main app and DAM extension logs)
        // instead of passing a specific file which would only include current process logs
        let logFile: URL? = nil
        
        if includeLogFile && hasLogFile {
            logger.debug("Including comprehensive logs in bug report (main app + DAM extension)")
        } else {
            logger.debug("Bug report submitted without log file")
        }
        
        let result = await bugReportService.submitBugReport(report, logFile: logFile)
        
        isSubmitting = false
        
        switch result {
        case .success(let reportId):
            logger.debug("Bug report submitted successfully with ID: \(reportId)")
            userComment = ""
            includeLogFile = true // Reset to default
            showingSuccessAlert = true
        case .failure(let error):
            logger.error("Bug report submission failed: \(error.localizedDescription)")
            
            // Run diagnostics for AWS-related errors
            if error.localizedDescription.contains("AWSClientRuntime") || 
               error.localizedDescription.contains("AWS") {
                logger.debug("Running AWS diagnostics due to AWS-related error")
                Task {
                    let diagnostics = AWSDiagnosticService()
                    await diagnostics.runDiagnostics()
                }
            }
            
            errorMessage = error.localizedDescription
            showingErrorAlert = true
        }
    }
    
    func getLogFileSize() -> String? {
        guard let logURL = currentLogFileURL else { return nil }
        
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: logURL.path)
            if let fileSize = attributes[.size] as? Int64 {
                return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
            }
        } catch {
            logger.error("Failed to get log file size: \(error.localizedDescription)")
        }
        
        return nil
    }
    
    func getLogFileInfo() -> (exists: Bool, size: String?) {
        guard let logURL = currentLogFileURL else {
            return (false, nil)
        }
        
        let exists = FileManager.default.fileExists(atPath: logURL.path)
        let size = exists ? getLogFileSize() : nil
        
        return (exists, size)
    }
    
    func resetForm() {
        userComment = ""
        includeLogFile = true
        errorMessage = ""
        showingErrorAlert = false
        showingSuccessAlert = false
    }
}