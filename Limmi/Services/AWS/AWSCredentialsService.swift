import Foundation
import FirebaseAuth
import AWSClientRuntime
import AWSSTS
import os

// MARK: - AWS Configuration

struct AWSConfiguration {
    static let roleArn = "arn:aws:iam::038462768011:role/Limmi1_logs"
    static let region = "us-east-1"
    static let bucketName = "limmi-logs-bucket"
    static let kmsKeyId = "arn:aws:kms:us-east-1:038462768011:key/10ce4a04-a3bf-4e2e-9858-87d19b80ebba"
}

// MARK: - AWS Credentials Service Protocol

protocol AWSCredentialsServiceProtocol {
    func assumeRoleWithWebIdentity(roleArn: String, sessionName: String) async throws -> STSClientTypes.Credentials
}

// MARK: - AWS Credentials Service Implementation

class AWSCredentialsService: AWSCredentialsServiceProtocol {
    private let logger = UnifiedLogger(
        fileLogger: .shared,
        osLogger: Logger(subsystem: "com.limmi.app", category: "AWSCredentialsService")
    )
    
    private var cachedCredentials: STSClientTypes.Credentials?
    private var credentialsExpiryTime: Date?
    
    // MARK: - Public Methods
    
    func assumeRoleWithWebIdentity(
        roleArn: String,
        sessionName: String
    ) async throws -> STSClientTypes.Credentials {
        logger.debug("Assuming role with web identity for session: \(sessionName)")
        
        // Check cached credentials
        if let cached = cachedCredentials,
           let expiryTime = credentialsExpiryTime,
           Date() < expiryTime.addingTimeInterval(-300) { // Refresh 5 minutes early
            logger.debug("Using cached AWS credentials")
            return cached
        }
        
        // Get fresh Firebase ID token
        let idToken = try await getFirebaseIDToken()
        
        // Create basic STS client configuration
        let config = try await STSClient.STSClientConfiguration(region: AWSConfiguration.region)
        let stsClient = STSClient(config: config)
        
        logger.debug("Created STS client for region: \(AWSConfiguration.region)")
        logger.debug("Role ARN: \(roleArn)")
        logger.debug("Session Name: \(sessionName)")
        logger.debug("ID Token length: \(idToken.count)")
        
        // Create assume role request
        let request = AssumeRoleWithWebIdentityInput(
            durationSeconds: 3600,
            roleArn: roleArn,
            roleSessionName: sessionName,
            webIdentityToken: idToken
        )
        
        // Execute assume role
        do {
            let response = try await stsClient.assumeRoleWithWebIdentity(input: request)
            logger.debug("STS assume role response received")
            
            guard let credentials = response.credentials else {
                logger.error("No credentials returned from STS")
                throw AWSCredentialsError.noCredentialsReturned
            }
            
            logger.debug("Credentials obtained - AccessKeyId: \(credentials.accessKeyId?.prefix(10) ?? "nil")...")
            logger.debug("Session token length: \(credentials.sessionToken?.count ?? 0)")
            
            // Cache credentials
            cachedCredentials = credentials
            if let expiration = credentials.expiration {
                credentialsExpiryTime = expiration
                logger.debug("Credentials expire at: \(expiration)")
            }
            
            logger.debug("AWS credentials obtained successfully")
            return credentials
            
        } catch {
            logger.error("STS AssumeRoleWithWebIdentity failed: \(error)")
            throw AWSCredentialsError.roleAssumptionFailed(error)
        }
    }
    
    // MARK: - Private Methods
    
    private func getFirebaseIDToken() async throws -> String {
        logger.debug("Requesting Firebase ID token")
        
        guard let currentUser = Auth.auth().currentUser else {
            logger.error("No authenticated Firebase user")
            throw AWSCredentialsError.authenticationRequired
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            currentUser.getIDTokenForcingRefresh(true) { token, error in
                if let token = token {
                    self.logger.debug("Firebase ID token obtained successfully")
                    continuation.resume(returning: token)
                } else {
                    let error = error ?? NSError(
                        domain: "AuthError",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to get ID token"]
                    )
                    self.logger.error("Failed to get Firebase ID token: \(error.localizedDescription)")
                    continuation.resume(throwing: AWSCredentialsError.tokenFetchFailed(error))
                }
            }
        }
    }
}

// MARK: - AWS Credentials Error

enum AWSCredentialsError: LocalizedError {
    case authenticationRequired
    case tokenFetchFailed(Error)
    case noCredentialsReturned
    case roleAssumptionFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            return "User authentication required for AWS access"
        case .tokenFetchFailed(let error):
            return "Failed to get Firebase token: \(error.localizedDescription)"
        case .noCredentialsReturned:
            return "AWS STS did not return credentials"
        case .roleAssumptionFailed(let error):
            return "Failed to assume AWS role: \(error.localizedDescription)"
        }
    }
}
