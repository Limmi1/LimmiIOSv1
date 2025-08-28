import Foundation
import FirebaseAuth
import AWSClientRuntime
import AWSS3
import AWSSDKIdentity
import os

// MARK: - Real S3 Upload Service Implementation

class RealS3UploadService: S3UploadServiceProtocol {
    private let credentialsService: AWSCredentialsServiceProtocol
    private let logger = UnifiedLogger(
        fileLogger: .shared,
        osLogger: Logger(subsystem: "com.limmi.app", category: "RealS3UploadService")
    )
    
    // MARK: - Initialization
    
    init(credentialsService: AWSCredentialsServiceProtocol = AWSCredentialsService()) {
        self.credentialsService = credentialsService
        logger.debug("RealS3UploadService initialized")
    }
    
    // MARK: - Public Methods
    
    func uploadLogFile(fileURL: URL, userUid: String) async throws -> S3UploadResult {
        logger.debug("Starting real S3 log file upload for user: \(userUid)")
        logger.debug("File path: \(fileURL.path)")
        
        // Verify file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            logger.error("Log file not found at path: \(fileURL.path)")
            throw S3UploadError.fileNotFound
        }
        
        // Get file size and data
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileSize = fileAttributes[.size] as? Int64 ?? 0
        let fileData = try Data(contentsOf: fileURL)
        
        logger.debug("Log file size: \(fileSize) bytes")
        
        // Create S3 key
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let fileName = fileURL.lastPathComponent
        let key = "\(userUid)/logs/\(timestamp)_\(fileName)"
        
        // Upload to S3
        return try await uploadToS3(
            data: fileData,
            key: key,
            contentType: "text/plain",
            metadata: [
                "user-id": userUid,
                "file-type": "log",  
                "original-name": fileName,
                "uploaded-at": timestamp
            ]
        )
    }
    
    /// Uploads comprehensive log files including both current and rotated logs
    func uploadComprehensiveLogFiles(userUid: String) async throws -> S3UploadResult {
        logger.debug("Starting comprehensive real S3 log file upload for user: \(userUid)")
        
        let fileLogger = FileLogger.shared
        
        // Try to create consolidated log file first (includes both current and rotated)
        if let consolidatedURL = fileLogger.createConsolidatedLogFile() {
            logger.debug("Created consolidated log file, uploading comprehensive logs to real S3")
            
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
        logger.debug("Consolidation failed, uploading most recent log file to real S3")
        return try await uploadLogFile(fileURL: allLogURLs[0], userUid: userUid)
    }
    
    func uploadBugReportData(_ data: Data, fileName: String, userUid: String) async throws -> S3UploadResult {
        logger.debug("Starting real S3 bug report data upload for user: \(userUid)")
        logger.debug("Data size: \(data.count) bytes, fileName: \(fileName)")
        
        // Create S3 key
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let key = "\(userUid)/bug-reports/\(timestamp)_\(fileName)"
        
        // Upload to S3
        return try await uploadToS3(
            data: data,
            key: key,
            contentType: "application/json",
            metadata: [
                "user-id": userUid,
                "file-type": "bug-report",
                "original-name": fileName,
                "uploaded-at": timestamp
            ]
        )
    }
    
    // MARK: - Private Methods
    
    private func uploadToS3(
        data: Data,
        key: String,
        contentType: String,
        metadata: [String: String]
    ) async throws -> S3UploadResult {
        
        logger.debug("Real S3 upload starting for key: \(key)")
        logger.debug("Data size: \(data.count) bytes")
        logger.debug("Content type: \(contentType)")
        
        // Get AWS credentials
        guard let userId = Auth.auth().currentUser?.uid else {
            logger.error("No authenticated user for S3 upload")
            throw S3UploadError.authenticationRequired
        }
        
        logger.debug("Getting AWS credentials for user: \(userId)")
        
        let stsCredentials = try await credentialsService.assumeRoleWithWebIdentity(
            roleArn: AWSConfiguration.roleArn,
            sessionName: userId
        )
        
        logger.debug("AWS credentials obtained successfully")
        
        guard let accessKeyId = stsCredentials.accessKeyId,
              let secretAccessKey = stsCredentials.secretAccessKey,
              let sessionToken = stsCredentials.sessionToken else {
            logger.error("Missing required credential components")
            throw S3UploadError.invalidData
        }
        
        logger.debug("Creating AWS credentials from STS response")
        logger.debug("Access Key ID: \(accessKeyId.prefix(10))...")
        logger.debug("Session Token length: \(sessionToken.count)")
        
        // Create AWS credential identity
        let awsCredentials = AWSCredentialIdentity(
            accessKey: accessKeyId,
            secret: secretAccessKey,
            sessionToken: sessionToken
        )
        
        // Create static credential resolver
        let credentialResolver = StaticAWSCredentialIdentityResolver(awsCredentials)
        
        logger.debug("Created credential resolver")
        
        // Configure S3 client
        let s3Config = try await S3Client.S3ClientConfiguration(
            awsCredentialIdentityResolver: credentialResolver,
            region: AWSConfiguration.region
        )
        
        let s3Client = S3Client(config: s3Config)
        
        logger.debug("S3 client configured for region: \(AWSConfiguration.region)")
        logger.debug("Target bucket: \(AWSConfiguration.bucketName)")
        
        // Prepare metadata for S3
        var s3Metadata: [String: String] = [:]
        for (key, value) in metadata {
            // S3 metadata keys must be lowercase and can only contain certain characters
            let cleanKey = key.lowercased().replacingOccurrences(of: "-", with: "")
            s3Metadata[cleanKey] = value
        }
        
        // Create PutObject request
        let putObjectInput = PutObjectInput(
            body: .data(data),
            bucket: AWSConfiguration.bucketName,
            contentType: contentType,
            key: key,
            metadata: s3Metadata,
            serverSideEncryption: .awsKms,
            ssekmsKeyId: AWSConfiguration.kmsKeyId
        )
        
        logger.debug("Created PutObject request")
        logger.debug("Server-side encryption: AWS KMS")
        logger.debug("KMS Key ID: \(AWSConfiguration.kmsKeyId)")
        
        // Execute the upload
        do {
            logger.debug("Executing S3 putObject request...")
            
            let response = try await s3Client.putObject(input: putObjectInput)
            
            logger.debug("S3 upload completed successfully!")
            logger.debug("ETag: \(response.eTag ?? "none")")
            logger.debug("Server-side encryption: \(response.serverSideEncryption?.rawValue ?? "none")")
            
            // Create result
            let result = S3UploadResult(
                bucketName: AWSConfiguration.bucketName,
                key: key,
                url: "https://\(AWSConfiguration.bucketName).s3.\(AWSConfiguration.region).amazonaws.com/\(key)",
                uploadedAt: Date(),
                fileSize: Int64(data.count)
            )
            
            logger.debug("Upload successful - S3 URL: \(result.url)")
            
            return result
            
        } catch {
            logger.error("S3 upload failed with error: \(error)")
            
            //if let awsError = error as? ServiceError {
            //    logger.error("AWS Service Error - Code: \(awsError)")
            //}
            
            if let nsError = error as NSError? {
                logger.error("NSError domain: \(nsError.domain), code: \(nsError.code)")
                logger.error("NSError userInfo: \(nsError.userInfo)")
            }
            
            throw S3UploadError.uploadFailed(error)
        }
    }
}
