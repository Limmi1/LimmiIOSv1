import Foundation
import FirebaseAuth
import os

// MARK: - AWS Diagnostic Service

class AWSDiagnosticService {
    private let logger = UnifiedLogger(
        fileLogger: .shared,
        osLogger: Logger(subsystem: "com.limmi.app", category: "AWSDiagnosticService")
    )
    
    func runDiagnostics() async {
        logger.debug("=== AWS Diagnostics Starting ===")
        
        await checkFirebaseAuth()
        await checkFirebaseIDToken()
        await checkAWSConfiguration()
        await testSTSConnection()
        
        logger.debug("=== AWS Diagnostics Complete ===")
    }
    
    private func checkFirebaseAuth() async {
        logger.debug("--- Checking Firebase Authentication ---")
        
        if let user = Auth.auth().currentUser {
            logger.debug("✅ Firebase user authenticated")
            logger.debug("User ID: \(user.uid)")
            logger.debug("Email: \(user.email ?? "none")")
            logger.debug("Provider data count: \(user.providerData.count)")
            
            for provider in user.providerData {
                logger.debug("Provider ID: \(provider.providerID)")
            }
        } else {
            logger.error("❌ No Firebase user authenticated")
        }
    }
    
    private func checkFirebaseIDToken() async {
        logger.debug("--- Checking Firebase ID Token ---")
        
        guard let user = Auth.auth().currentUser else {
            logger.error("❌ No user to get token from")
            return
        }
        
        do {
            let token = try await withCheckedThrowingContinuation { continuation in
                user.getIDTokenForcingRefresh(true) { token, error in
                    if let token = token {
                        continuation.resume(returning: token)
                    } else {
                        continuation.resume(throwing: error ?? NSError(domain: "Token", code: -1))
                    }
                }
            }
            
            logger.debug("✅ Firebase ID token obtained")
            logger.debug("Token length: \(token.count)")
            logger.debug("Token prefix: \(token.prefix(50))...")
            
            // Try to decode the token header to check format
            let parts = token.split(separator: ".")
            if parts.count >= 3 {
                logger.debug("✅ Token has correct JWT structure (3 parts)")
                
                // Decode header
                if let headerData = base64UrlDecode(String(parts[0])),
                   let headerJSON = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any] {
                    logger.debug("Token header: \(headerJSON)")
                }
                
                // Decode payload
                if let payloadData = base64UrlDecode(String(parts[1])),
                   let payloadJSON = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] {
                    logger.debug("Token issuer: \(payloadJSON["iss"] as? String ?? "unknown")")
                    logger.debug("Token audience: \(payloadJSON["aud"] as? String ?? "unknown")")
                    
                    if let exp = payloadJSON["exp"] as? Double {
                        let expDate = Date(timeIntervalSince1970: exp)
                        logger.debug("Token expires: \(expDate)")
                        
                        if expDate > Date() {
                            logger.debug("✅ Token is not expired")
                        } else {
                            logger.error("❌ Token is expired!")
                        }
                    }
                }
            } else {
                logger.error("❌ Token does not have correct JWT structure")
            }
            
        } catch {
            logger.error("❌ Failed to get Firebase ID token: \(error)")
        }
    }
    
    private func checkAWSConfiguration() async {
        logger.debug("--- Checking AWS Configuration ---")
        
        logger.debug("AWS Role ARN: \(AWSConfiguration.roleArn)")
        logger.debug("AWS Region: \(AWSConfiguration.region)")
        logger.debug("S3 Bucket: \(AWSConfiguration.bucketName)")
        logger.debug("KMS Key: \(AWSConfiguration.kmsKeyId)")
        
        // Validate ARN format
        if AWSConfiguration.roleArn.hasPrefix("arn:aws:iam::") && AWSConfiguration.roleArn.contains(":role/") {
            logger.debug("✅ Role ARN format appears correct")
        } else {
            logger.error("❌ Role ARN format appears incorrect")
        }
        
        // Validate region format
        if AWSConfiguration.region.contains("-") && AWSConfiguration.region.count > 5 {
            logger.debug("✅ Region format appears correct")
        } else {
            logger.error("❌ Region format appears incorrect")
        }
    }
    
    private func testSTSConnection() async {
        logger.debug("--- Testing STS Connection ---")
        
        let credentialsService = AWSCredentialsService()
        
        do {
            guard let userId = Auth.auth().currentUser?.uid else {
                logger.error("❌ No user ID for STS test")
                return
            }
            
            let credentials = try await credentialsService.assumeRoleWithWebIdentity(
                roleArn: AWSConfiguration.roleArn,
                sessionName: userId
            )
            
            logger.debug("✅ STS AssumeRoleWithWebIdentity succeeded")
            logger.debug("Access Key ID: \(credentials.accessKeyId?.prefix(10) ?? "nil")...")
            logger.debug("Secret Access Key length: \(credentials.secretAccessKey?.count ?? 0)")
            logger.debug("Session Token length: \(credentials.sessionToken?.count ?? 0)")
            
            if let expiration = credentials.expiration {
                logger.debug("Credentials expire: \(expiration)")
            }
            
        } catch {
            logger.error("❌ STS AssumeRoleWithWebIdentity failed: \(error)")
            
            if let nsError = error as NSError? {
                logger.error("Error domain: \(nsError.domain)")
                logger.error("Error code: \(nsError.code)")
                logger.error("Error userInfo: \(nsError.userInfo)")
            }
        }
    }
    
    private func base64UrlDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        // Add padding if needed
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        
        return Data(base64Encoded: base64)
    }
}