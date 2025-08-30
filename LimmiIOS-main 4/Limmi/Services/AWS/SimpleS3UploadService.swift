import Foundation
import FirebaseAuth
import os

// MARK: - S3 Upload Service Protocol

protocol S3UploadServiceProtocol {
    func uploadLogFile(fileURL: URL, userUid: String) async throws -> S3UploadResult
    func uploadComprehensiveLogFiles(userUid: String) async throws -> S3UploadResult
    func uploadBugReportData(_ data: Data, fileName: String, userUid: String) async throws -> S3UploadResult
}

// MARK: - S3 Upload Result

struct S3UploadResult {
    let bucketName: String
    let key: String
    let url: String
    let uploadedAt: Date
    let fileSize: Int64
    
    var s3URL: String {
        return "s3://\(bucketName)/\(key)"
    }
}

// MARK: - S3 Upload Error

enum S3UploadError: LocalizedError {
    case fileNotFound
    case fileTooLarge(Int64, Int64) // actual size, max size
    case invalidData
    case uploadFailed(Error)
    case authenticationRequired
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "File not found for upload"
        case .fileTooLarge(let actual, let max):
            let actualMB = Double(actual) / (1024 * 1024)
            let maxMB = Double(max) / (1024 * 1024)
            return String(format: "File size (%.1f MB) exceeds maximum (%.1f MB)", actualMB, maxMB)
        case .invalidData:
            return "Invalid data format for upload"
        case .uploadFailed(let error):
            return "Upload failed: \(error.localizedDescription)"
        case .authenticationRequired:
            return "Authentication required for upload"
        }
    }
}

// MARK: - Simple S3 Upload Service

class SimpleS3UploadService: S3UploadServiceProtocol {
    private let credentialsService: AWSCredentialsServiceProtocol
    private let logger = UnifiedLogger(
        fileLogger: .shared,
        osLogger: Logger(subsystem: "com.limmi.app", category: "SimpleS3UploadService")
    )
    
    // MARK: - Initialization
    
    init(credentialsService: AWSCredentialsServiceProtocol = AWSCredentialsService()) {
        self.credentialsService = credentialsService
        logger.debug("SimpleS3UploadService initialized")
    }
    
    // MARK: - Public Methods
    
    func uploadLogFile(fileURL: URL, userUid: String) async throws -> S3UploadResult {
        logger.debug("Starting log file upload for user: \(userUid)")
        logger.debug("File path: \(fileURL.path)")
        
        // For now, this is a placeholder that simulates successful upload
        // In production, you would implement the actual S3 upload using URLSession
        // with signed requests based on the credentials from credentialsService
        
        // Verify file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            logger.error("Log file not found at path: \(fileURL.path)")
            throw S3UploadError.fileNotFound
        }
        
        // Get file size
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileSize = fileAttributes[.size] as? Int64 ?? 0
        logger.debug("Log file size: \(fileSize) bytes")
        
        // Create S3 key
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let fileName = fileURL.lastPathComponent
        let key = "\(userUid)/logs/\(timestamp)_\(fileName)"
        
        // Get credentials (for future implementation)
        let credentials = try await credentialsService.assumeRoleWithWebIdentity(
            roleArn: AWSConfiguration.roleArn,
            sessionName: userUid
        )
        
        logger.debug("AWS credentials obtained, would upload to S3 with key: \(key)")
        
        // Simulate successful upload
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay to simulate upload
        
        logger.debug("Log file upload simulated successfully")
        
        // Create result
        let result = S3UploadResult(
            bucketName: AWSConfiguration.bucketName,
            key: key,
            url: "https://\(AWSConfiguration.bucketName).s3.\(AWSConfiguration.region).amazonaws.com/\(key)",
            uploadedAt: Date(),
            fileSize: fileSize
        )
        
        return result
    }
    
    /// Uploads comprehensive log files including both current and rotated logs
    func uploadComprehensiveLogFiles(userUid: String) async throws -> S3UploadResult {
        logger.debug("Starting comprehensive log file upload for user: \(userUid)")
        
        let fileLogger = FileLogger.shared
        
        // Try to create consolidated log file first (includes both current and rotated)
        if let consolidatedURL = fileLogger.createConsolidatedLogFile() {
            logger.debug("Created consolidated log file, uploading comprehensive logs")
            
            // Upload the consolidated file
            let result = try await uploadLogFile(fileURL: consolidatedURL, userUid: userUid)
            
            // Clean up temporary consolidated file
            try? FileManager.default.removeItem(at: consolidatedURL)
            
            return result
        }
        
        // Fallback: upload individual log files if consolidation fails
        let allLogURLs = fileLogger.getAllLogFileURLs()
        guard !allLogURLs.isEmpty else {
            logger.error("No log files found to upload")
            throw S3UploadError.fileNotFound
        }
        
        // Upload the most recent log file (first in array)
        logger.debug("Consolidation failed, uploading most recent log file")
        return try await uploadLogFile(fileURL: allLogURLs[0], userUid: userUid)
    }
    
    func uploadBugReportData(_ data: Data, fileName: String, userUid: String) async throws -> S3UploadResult {
        logger.debug("Starting bug report data upload for user: \(userUid)")
        logger.debug("Data size: \(data.count) bytes, fileName: \(fileName)")
        
        // Create S3 key
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let key = "\(userUid)/bug-reports/\(timestamp)_\(fileName)"
        
        // Get credentials (for future implementation)
        let credentials = try await credentialsService.assumeRoleWithWebIdentity(
            roleArn: AWSConfiguration.roleArn,
            sessionName: userUid
        )
        
        logger.debug("AWS credentials obtained, would upload bug report data to S3 with key: \(key)")
        
        // Simulate successful upload
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay to simulate upload
        
        logger.debug("Bug report data upload simulated successfully")
        
        // Create result
        let result = S3UploadResult(
            bucketName: AWSConfiguration.bucketName,
            key: key,
            url: "https://\(AWSConfiguration.bucketName).s3.\(AWSConfiguration.region).amazonaws.com/\(key)",
            uploadedAt: Date(),
            fileSize: Int64(data.count)
        )
        
        return result
    }
}