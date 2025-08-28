import Foundation
import FirebaseFirestore
import FirebaseAuth
import os

// MARK: - AWS Bug Report Service Implementation

class AWSBugReportService: BugReportServiceProtocol {
    private let firestore = Firestore.firestore()
    private let s3UploadService: S3UploadServiceProtocol
    private let logger = UnifiedLogger(
        fileLogger: .shared,
        osLogger: Logger(subsystem: "com.limmi.app", category: "AWSBugReportService")
    )
    
    // MARK: - Initialization
    
    init(s3UploadService: S3UploadServiceProtocol = RealS3UploadService()) {
        self.s3UploadService = s3UploadService
        logger.debug("AWSBugReportService initialized")
    }
    
    // MARK: - Public Methods
    
    func submitBugReport(_ report: any BugReport, logFile: URL?) async -> Result<String, BugReportError> {
        logger.debug("Starting AWS-based bug report submission for user: \(report.userId)")
        
        var finalReport: any BugReport = report
        var logUploadResult: S3UploadResult?
        
        // Step 1: Upload log file to S3 (specific file or comprehensive logs)
        do {
            if let logFile = logFile {
                logger.debug("Uploading specific log file to S3: \(logFile.path)")
                logUploadResult = try await s3UploadService.uploadLogFile(
                    fileURL: logFile,
                    userUid: report.userId
                )
            } else {
                logger.debug("No specific log file provided, uploading comprehensive logs to S3")
                logUploadResult = try await s3UploadService.uploadComprehensiveLogFiles(
                    userUid: report.userId
                )
            }
            
            logger.debug("Log files uploaded successfully to S3: \(logUploadResult?.s3URL ?? "unknown")")
            
            // Update report with S3 information instead of base64 content
            finalReport = AWSBugReport(
                id: report.id,
                userId: report.userId,
                userComment: report.userComment,
                logFileS3Key: logUploadResult?.key,
                logFileS3URL: logUploadResult?.url,
                logFileSize: logUploadResult?.fileSize,
                deviceInfo: report.deviceInfo,
                appVersion: report.appVersion,
                timestamp: report.timestamp,
                status: report.status,
                priority: report.priority
            )
            
        } catch {
                logger.error("Failed to upload log file to S3: \(error)")
                logger.error("Error details - localizedDescription: \(error.localizedDescription)")
                if let nsError = error as NSError? {
                    logger.error("Error domain: \(nsError.domain), code: \(nsError.code)")
                    logger.error("User info: \(nsError.userInfo)")
                }
                
                // Fallback: Store log file as base64 in Firestore (for smaller files)
                if let logFile = logFile {
                    logger.debug("Attempting fallback: storing specific log file as base64 in Firestore")
                    
                    do {
                        let fileData = try Data(contentsOf: logFile)
                        let maxSize = 500 * 1024 // 500KB limit for fallback
                        
                        if fileData.count <= maxSize {
                            let base64Content = fileData.base64EncodedString()
                            finalReport = FirebaseBugReport(
                                userId: report.userId,
                                userComment: report.userComment,
                                logFileContent: base64Content,
                                logFileSize: Int64(fileData.count)
                            )
                            logger.debug("Fallback successful: log file stored as base64 (\(fileData.count) bytes)")
                        } else {
                            logger.debug("Log file too large for fallback (\(fileData.count) bytes > \(maxSize) bytes)")
                            finalReport = report
                        }
                    } catch {
                        logger.error("Fallback failed: \(error.localizedDescription)")
                        finalReport = report
                    }
                } else {
                    logger.debug("No specific log file for fallback, attempting with current log file")
                    let currentLogURL = FileLogger.shared.getLogFileURL()
                    
                    do {
                        let fileData = try Data(contentsOf: currentLogURL)
                        let maxSize = 500 * 1024 // 500KB limit for fallback
                        
                        if fileData.count <= maxSize {
                            let base64Content = fileData.base64EncodedString()
                            finalReport = FirebaseBugReport(
                                userId: report.userId,
                                userComment: report.userComment,
                                logFileContent: base64Content,
                                logFileSize: Int64(fileData.count)
                            )
                            logger.debug("Fallback successful: current log file stored as base64 (\(fileData.count) bytes)")
                        } else {
                            logger.debug("Current log file too large for fallback (\(fileData.count) bytes > \(maxSize) bytes)")
                            finalReport = report
                        }
                    } catch {
                        logger.error("Fallback with current log file failed: \(error.localizedDescription)")
                        finalReport = report
                    }
                }
        }
        
        // Step 2: Create bug report JSON data
        do {
            let bugReportJSON = try createBugReportJSON(finalReport, logUploadResult: logUploadResult)
            let fileName = "bug_report_\(UUID().uuidString).json"
            
            // Step 3: Upload bug report data to S3
            logger.debug("Uploading bug report data to S3")
            let reportUploadResult = try await s3UploadService.uploadBugReportData(
                bugReportJSON,
                fileName: fileName,
                userUid: finalReport.userId
            )
            
            logger.debug("Bug report data uploaded to S3: \(reportUploadResult.s3URL)")
            
            // Step 4: Save metadata to Firestore (minimal data, references to S3)
            let firestoreData: [String: Any] = [
                "userId": finalReport.userId,
                "timestamp": finalReport.timestamp,
                "status": finalReport.status.rawValue,
                "priority": finalReport.priority.rawValue,
                "s3BucketName": reportUploadResult.bucketName,
                "s3Key": reportUploadResult.key,
                "s3URL": reportUploadResult.url,
                "hasLogFile": logUploadResult != nil,
                "logFileS3Key": logUploadResult?.key as Any,
                "logFileS3URL": logUploadResult?.url as Any,
                "deviceModel": finalReport.deviceInfo.model,
                "systemVersion": finalReport.deviceInfo.systemVersion,
                "appVersion": finalReport.appVersion
            ]
            
            logger.debug("Saving bug report metadata to Firestore")
            let docRef = try await firestore
                .collection("users")
                .document(finalReport.userId)
                .collection("bugReports")
                .addDocument(data: firestoreData)
            
            logger.debug("Bug report saved successfully with ID: \(docRef.documentID)")
            logger.debug("S3 data location: \(reportUploadResult.s3URL)")
            if let logURL = logUploadResult?.s3URL {
                logger.debug("S3 log location: \(logURL)")
            }
            
            return .success(docRef.documentID)
            
        } catch {
            logger.error("Failed to upload bug report data: \(error.localizedDescription)")
            return .failure(.storageError(error))
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
            
            var reports: [any BugReport] = []
            
            for document in snapshot.documents {
                let data = document.data()
                
                // Reconstruct BugReport from Firestore metadata
                if let userId = data["userId"] as? String,
                   let timestamp = data["timestamp"] as? Timestamp,
                   let statusRaw = data["status"] as? String,
                   let priorityRaw = data["priority"] as? String,
                   let s3Key = data["s3Key"] as? String,
                   let s3URL = data["s3URL"] as? String,
                   let deviceModel = data["deviceModel"] as? String,
                   let systemVersion = data["systemVersion"] as? String,
                   let appVersion = data["appVersion"] as? String,
                   let status = BugReportStatus(rawValue: statusRaw),
                   let priority = BugPriority(rawValue: priorityRaw) {
                    
                    // For listing purposes, we don't fetch the full content from S3
                    // The userComment will be "[Stored in S3]" as a placeholder
                    let report = AWSBugReport(
                        id: document.documentID,
                        userId: userId,
                        userComment: "[Bug report stored in S3]",
                        logFileS3Key: data["logFileS3Key"] as? String,
                        logFileS3URL: data["logFileS3URL"] as? String,
                        logFileSize: data["logFileSize"] as? Int64,
                        deviceInfo: DeviceInfo(
                            model: deviceModel,
                            systemVersion: systemVersion,
                            appVersion: appVersion,
                            buildNumber: "Unknown"
                        ),
                        appVersion: appVersion,
                        timestamp: timestamp.dateValue(),
                        status: status,
                        priority: priority,
                        s3BucketName: data["s3BucketName"] as? String,
                        s3Key: s3Key,
                        s3URL: s3URL
                    )
                    
                    reports.append(report)
                }
            }
            
            logger.debug("Fetched \(reports.count) bug reports for user")
            return .success(reports)
            
        } catch {
            logger.error("Failed to fetch user bug reports: \(error.localizedDescription)")
            return .failure(.firestoreError(error))
        }
    }
    
    // MARK: - Private Methods
    
    private func createBugReportJSON(_ report: any BugReport, logUploadResult: S3UploadResult?) throws -> Data {
        var jsonDict: [String: Any] = [
            "userId": report.userId,
            "userComment": report.userComment,
            "deviceInfo": [
                "model": report.deviceInfo.model,
                "systemVersion": report.deviceInfo.systemVersion,
                "appVersion": report.deviceInfo.appVersion,
                "buildNumber": report.deviceInfo.buildNumber
            ],
            "appVersion": report.appVersion,
            "timestamp": ISO8601DateFormatter().string(from: report.timestamp),
            "status": report.status.rawValue,
            "priority": report.priority.rawValue
        ]
        
        // Add S3 log file information if available
        if let logResult = logUploadResult {
            jsonDict["logFile"] = [
                "s3Bucket": logResult.bucketName,
                "s3Key": logResult.key,
                "s3URL": logResult.url,
                "fileSize": logResult.fileSize,
                "uploadedAt": ISO8601DateFormatter().string(from: logResult.uploadedAt)
            ]
        }
        
        return try JSONSerialization.data(withJSONObject: jsonDict, options: .prettyPrinted)
    }
}

// MARK: - AWS Bug Report Model

struct AWSBugReport: BugReport {
    let id: String?
    let userId: String
    let userComment: String
    let logFileContent: String? = nil // Not used in AWS version
    let logFileSize: Int64?
    let deviceInfo: DeviceInfo
    let appVersion: String
    let timestamp: Date
    let status: BugReportStatus
    let priority: BugPriority
    
    // AWS-specific properties
    let logFileS3Key: String?
    let logFileS3URL: String?
    let s3BucketName: String?
    let s3Key: String?
    let s3URL: String?
    
    init(
        id: String? = nil,
        userId: String,
        userComment: String,
        logFileS3Key: String? = nil,
        logFileS3URL: String? = nil,
        logFileSize: Int64? = nil,
        deviceInfo: DeviceInfo = DeviceInfo.current,
        appVersion: String = Bundle.main.appVersionWithBuild,
        timestamp: Date = Date(),
        status: BugReportStatus = .submitted,
        priority: BugPriority = .normal,
        s3BucketName: String? = nil,
        s3Key: String? = nil,
        s3URL: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.userComment = userComment
        self.logFileS3Key = logFileS3Key
        self.logFileS3URL = logFileS3URL
        self.logFileSize = logFileSize
        self.deviceInfo = deviceInfo
        self.appVersion = appVersion
        self.timestamp = timestamp
        self.status = status
        self.priority = priority
        self.s3BucketName = s3BucketName
        self.s3Key = s3Key
        self.s3URL = s3URL
    }
}
