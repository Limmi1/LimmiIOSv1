import Foundation
import FirebaseAuth
import os
import CryptoKit
import CommonCrypto

// MARK: - Direct S3 Upload Service (using REST API)

class DirectS3UploadService: S3UploadServiceProtocol {
    private let credentialsService: AWSCredentialsServiceProtocol
    private let logger = UnifiedLogger(
        fileLogger: .shared,
        osLogger: Logger(subsystem: "com.limmi.app", category: "DirectS3UploadService")
    )
    
    // MARK: - Initialization
    
    init(credentialsService: AWSCredentialsServiceProtocol = AWSCredentialsService()) {
        self.credentialsService = credentialsService
        logger.debug("DirectS3UploadService initialized")
    }
    
    // MARK: - Public Methods
    
    func uploadLogFile(fileURL: URL, userUid: String) async throws -> S3UploadResult {
        logger.debug("Starting direct S3 log file upload for user: \(userUid)")
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
        
        // Upload to S3 using REST API
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
        logger.debug("Starting comprehensive direct S3 log file upload for user: \(userUid)")
        
        let fileLogger = FileLogger.shared
        
        // Try to create consolidated log file first (includes both current and rotated)
        if let consolidatedURL = fileLogger.createConsolidatedLogFile() {
            logger.debug("Created consolidated log file, uploading comprehensive logs via direct S3")
            
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
        logger.debug("Consolidation failed, uploading most recent log file via direct S3")
        return try await uploadLogFile(fileURL: allLogURLs[0], userUid: userUid)
    }
    
    func uploadBugReportData(_ data: Data, fileName: String, userUid: String) async throws -> S3UploadResult {
        logger.debug("Starting direct S3 bug report data upload for user: \(userUid)")
        logger.debug("Data size: \(data.count) bytes, fileName: \(fileName)")
        
        // Create S3 key
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let key = "\(userUid)/bug-reports/\(timestamp)_\(fileName)"
        
        // Upload to S3 using REST API
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
        
        logger.debug("Uploading to S3 with key: \(key)")
        
        // Get AWS credentials
        guard let userId = Auth.auth().currentUser?.uid else {
            throw S3UploadError.authenticationRequired
        }
        
        let credentials = try await credentialsService.assumeRoleWithWebIdentity(
            roleArn: AWSConfiguration.roleArn,
            sessionName: userId
        )
        
        guard let accessKeyId = credentials.accessKeyId,
              let secretAccessKey = credentials.secretAccessKey,
              let sessionToken = credentials.sessionToken else {
            logger.error("Missing required credentials")
            throw S3UploadError.invalidData
        }
        
        // Create S3 REST API request
        let url = URL(string: "https://\(AWSConfiguration.bucketName).s3.\(AWSConfiguration.region).amazonaws.com/\(key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = data
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")
        request.setValue("aws-kms", forHTTPHeaderField: "x-amz-server-side-encryption")
        request.setValue(AWSConfiguration.kmsKeyId, forHTTPHeaderField: "x-amz-server-side-encryption-aws-kms-key-id")
        request.setValue(sessionToken, forHTTPHeaderField: "x-amz-security-token")
        
        // Add metadata headers
        for (key, value) in metadata {
            request.setValue(value, forHTTPHeaderField: "x-amz-meta-\(key)")
        }
        
        // Create AWS signature
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        dateFormatter.timeZone = TimeZone(abbreviation: "UTC")
        let timestamp = dateFormatter.string(from: Date())
        
        let dateStamp = String(timestamp.prefix(8))
        
        request.setValue(timestamp, forHTTPHeaderField: "x-amz-date")
        request.setValue("AWS4-HMAC-SHA256", forHTTPHeaderField: "x-amz-content-sha256")
        
        // Create authorization header
        let authHeader = try createAWSAuthorizationHeader(
            request: request,
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            region: AWSConfiguration.region,
            service: "s3",
            timestamp: timestamp,
            dateStamp: dateStamp
        )
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        
        logger.debug("S3 request prepared - URL: \(url)")
        logger.debug("Authorization header: \(authHeader.prefix(50))...")
        
        // Execute request
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                logger.debug("S3 upload response status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    logger.debug("S3 upload successful")
                    
                    let result = S3UploadResult(
                        bucketName: AWSConfiguration.bucketName,
                        key: key,
                        url: url.absoluteString,
                        uploadedAt: Date(),
                        fileSize: Int64(data.count)
                    )
                    
                    return result
                } else {
                    logger.error("S3 upload failed with status code: \(httpResponse.statusCode)")
                    throw S3UploadError.uploadFailed(NSError(domain: "S3Upload", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"]))
                }
            } else {
                logger.error("Invalid response type from S3")
                throw S3UploadError.uploadFailed(NSError(domain: "S3Upload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"]))
            }
        } catch {
            logger.error("S3 upload network error: \(error)")
            throw S3UploadError.uploadFailed(error)
        }
    }
    
    private func createAWSAuthorizationHeader(
        request: URLRequest,
        accessKeyId: String,
        secretAccessKey: String,
        region: String,
        service: String,
        timestamp: String,
        dateStamp: String
    ) throws -> String {
        
        // This is a simplified AWS signature version 4 implementation
        // For production use, consider using a more robust implementation
        
        let algorithm = "AWS4-HMAC-SHA256"
        let credentialScope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let credential = "\(accessKeyId)/\(credentialScope)"
        
        // Create canonical request (simplified)
        let httpMethod = request.httpMethod ?? "PUT"
        let canonicalUri = request.url?.path ?? "/"
        let canonicalQueryString = ""
        
        var canonicalHeaders = ""
        var signedHeaders = ""
        
        // Sort headers and create canonical string
        let sortedHeaders = request.allHTTPHeaderFields?.sorted { $0.key.lowercased() < $1.key.lowercased() } ?? []
        for (key, value) in sortedHeaders {
            let lowerKey = key.lowercased()
            canonicalHeaders += "\(lowerKey):\(value.trimmingCharacters(in: .whitespacesAndNewlines))\n"
            if !signedHeaders.isEmpty {
                signedHeaders += ";"
            }
            signedHeaders += lowerKey
        }
        
        let payloadHash = sha256Hash(data: request.httpBody ?? Data())
        
        let canonicalRequest = """
        \(httpMethod)
        \(canonicalUri)
        \(canonicalQueryString)
        \(canonicalHeaders)
        \(signedHeaders)
        \(payloadHash)
        """
        
        let canonicalRequestHash = sha256Hash(string: canonicalRequest)
        
        // Create string to sign
        let stringToSign = """
        \(algorithm)
        \(timestamp)
        \(credentialScope)
        \(canonicalRequestHash)
        """
        
        // Create signing key
        let signingKey = try getSigningKey(
            secretAccessKey: secretAccessKey,
            dateStamp: dateStamp,
            region: region,
            service: service
        )
        
        let signature = hmacSHA256(key: signingKey, data: stringToSign.data(using: .utf8) ?? Data()).map { String(format: "%02x", $0) }.joined()
        
        return "\(algorithm) Credential=\(credential), SignedHeaders=\(signedHeaders), Signature=\(signature)"
    }
    
    private func getSigningKey(secretAccessKey: String, dateStamp: String, region: String, service: String) throws -> Data {
        let kDate = hmacSHA256(key: "AWS4\(secretAccessKey)".data(using: .utf8) ?? Data(), data: dateStamp.data(using: .utf8) ?? Data())
        let kRegion = hmacSHA256(key: kDate, data: region.data(using: .utf8) ?? Data())
        let kService = hmacSHA256(key: kRegion, data: service.data(using: .utf8) ?? Data())
        let kSigning = hmacSHA256(key: kService, data: "aws4_request".data(using: .utf8) ?? Data())
        return kSigning
    }
    
    private func hmacSHA256(key: Data, data: Data) -> Data {
        var result = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        result.withUnsafeMutableBytes { resultBytes in
            key.withUnsafeBytes { keyBytes in
                data.withUnsafeBytes { dataBytes in
                    CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256), keyBytes.baseAddress, key.count, dataBytes.baseAddress, data.count, resultBytes.baseAddress)
                }
            }
        }
        return result
    }
    
    private func sha256Hash(data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
    
    private func sha256Hash(string: String) -> String {
        return sha256Hash(data: string.data(using: .utf8) ?? Data())
    }
}