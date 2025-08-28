import Foundation
import FirebaseFirestore
import os

// MARK: - Bug Report Service Protocol

protocol BugReportServiceProtocol {
    func submitBugReport(_ report: any BugReport, logFile: URL?) async -> Result<String, BugReportError>
    func getUserBugReports(userId: String) async -> Result<[any BugReport], BugReportError>
}

// MARK: - Bug Report Service Implementation

class BugReportService: BugReportServiceProtocol {
    private let firestore = Firestore.firestore()
    private let logger = UnifiedLogger(
        fileLogger: .shared,
        osLogger: Logger(subsystem: "com.limmi.app", category: "BugReportService")
    )
    
    // MARK: - Public Methods
    
    func submitBugReport(_ report: any BugReport, logFile: URL?) async -> Result<String, BugReportError> {
        logger.debug("Starting bug report submission for user: \(report.userId)")
        
        let finalReport: any BugReport
        
        // Step 1: Process log file if provided
        if let logFile = logFile {
            logger.debug("Processing log file: \(logFile.path)")
            
            switch processLogFile(logFile) {
            case .success(let (base64Content, fileSize)):
                finalReport = FirebaseBugReport(
                    userId: report.userId,
                    userComment: report.userComment,
                    logFileContent: base64Content,
                    logFileSize: Int64(fileSize)
                )
                logger.debug("Log file processed successfully, size: \(fileSize) bytes")
            case .failure(let error):
                logger.error("Failed to process log file: \(error.localizedDescription)")
                // Continue without log file - user comment is still valuable
                finalReport = report
            }
        } else {
            finalReport = report
        }
        
        // Step 2: Save bug report to Firestore
        do {
            logger.debug("Attempting to save to collection 'users/\(finalReport.userId)/bugReports'")
            logger.debug("Report data: userId=\(finalReport.userId), comment=\(finalReport.userComment.prefix(50))...")
            
            // Estimate document size for logging
            let estimatedSize = estimateDocumentSize(finalReport)
            logger.debug("Estimated Firestore document size: \(estimatedSize) bytes")
            
            let docRef = try await firestore
                .collection("users")
                .document(finalReport.userId)
                .collection("bugReports")
                .addDocument(from: finalReport as! FirebaseBugReport)
            logger.debug("Bug report saved successfully with ID: \(docRef.documentID)")
            logger.debug("Firestore path: users/\(finalReport.userId)/bugReports/\(docRef.documentID)")
            return .success(docRef.documentID)
        } catch {
            logger.error("Failed to save bug report to Firestore: \(error)")
            logger.error("Error details: \(error.localizedDescription)")
            return .failure(.firestoreError(error))
        }
    }
    
    func getUserBugReports(userId: String) async -> Result<[any BugReport], BugReportError> {
        logger.debug("Fetching bug reports for user: \(userId)")
        
        do {
            let snapshot = try await firestore
                .collection("users")
                .document(userId)
                .collection("bugReports")
                .order(by: "timestamp", descending: true)
                .getDocuments()
            
            let reports = try snapshot.documents.compactMap { document in
                try document.data(as: FirebaseBugReport.self)
            }
            
            logger.debug("Fetched \(reports.count) bug reports for user")
            return .success(reports)
        } catch {
            logger.error("Failed to fetch user bug reports: \(error.localizedDescription)")
            return .failure(.firestoreError(error))
        }
    }
    
    // MARK: - Private Methods
    
    private func processLogFile(_ fileURL: URL) -> Result<(String, Int), BugReportError> {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            logger.error("Log file does not exist at path: \(fileURL.path)")
            return .failure(.fileNotFound)
        }
        
        do {
            let fileData = try Data(contentsOf: fileURL)
            let fileSize = fileData.count
            
            // Check file size - limit to 700KB to account for base64 encoding overhead
            // Base64 encoding increases size by ~33%, so 700KB -> ~930KB base64 -> safe for 1MB Firestore limit
            let maxRawSize = 700 * 1024 // 700KB
            if fileSize > maxRawSize {
                logger.error("Log file size (\(fileSize) bytes) exceeds maximum (\(maxRawSize) bytes), truncating")
                let truncatedData = fileData.prefix(maxRawSize)
                let base64Content = truncatedData.base64EncodedString()
                let base64Size = base64Content.count
                logger.debug("Truncated: raw=\(maxRawSize) bytes, base64=\(base64Size) bytes")
                return .success((base64Content, maxRawSize))
            }
            
            let base64Content = fileData.base64EncodedString()
            let base64Size = base64Content.count
            logger.debug("Log file processed, original size: \(fileSize) bytes, base64 size: \(base64Size) characters")
            
            // Final safety check - ensure base64 content isn't too large
            let maxBase64Size = 900 * 1024 // 900KB base64 limit
            if base64Size > maxBase64Size {
                logger.error("Base64 content (\(base64Size) bytes) exceeds safe limit, truncating further")
                let safeTruncatedData = fileData.prefix(600 * 1024) // Reduce to 600KB raw
                let safeBase64Content = safeTruncatedData.base64EncodedString()
                logger.debug("Further truncated to: raw=600KB, base64=\(safeBase64Content.count) bytes")
                return .success((safeBase64Content, 600 * 1024))
            }
            
            return .success((base64Content, fileSize))
        } catch {
            logger.error("Failed to read log file: \(error.localizedDescription)")
            return .failure(.storageError(error))
        }
    }
    
    /// Decodes and saves log file content to a temporary file for viewing/sharing
    func extractLogFile(from report: any BugReport) -> Result<URL, BugReportError> {
        guard let base64Content = report.logFileContent, !base64Content.isEmpty else {
            logger.error("No log file content available in bug report")
            return .failure(.invalidData)
        }
        
        guard let logData = Data(base64Encoded: base64Content) else {
            logger.error("Failed to decode base64 log content")
            return .failure(.invalidData)
        }
        
        do {
            let tempDir = FileManager.default.temporaryDirectory
            let fileName = "bug_report_\(report.id ?? "unknown")_log.txt"
            let tempURL = tempDir.appendingPathComponent(fileName)
            
            // Remove existing file if it exists
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try FileManager.default.removeItem(at: tempURL)
            }
            
            try logData.write(to: tempURL)
            logger.debug("Log file extracted to: \(tempURL.path)")
            return .success(tempURL)
        } catch {
            logger.error("Failed to write extracted log file: \(error.localizedDescription)")
            return .failure(.storageError(error))
        }
    }
    
    /// Estimates the Firestore document size for logging purposes
    private func estimateDocumentSize(_ report: any BugReport) -> Int {
        var size = 0
        
        // Basic fields (rough estimation)
        size += report.userId.count
        size += report.userComment.count
        size += (report.logFileContent?.count ?? 0)
        size += 200 // Overhead for other fields, metadata, etc.
        
        return size
    }
}

