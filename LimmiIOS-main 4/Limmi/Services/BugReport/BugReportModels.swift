import Foundation
import FirebaseFirestore
import UIKit

// MARK: - Bug Report Protocol

protocol BugReport: Identifiable {
    var id: String? { get }
    var userId: String { get }
    var userComment: String { get }
    var logFileContent: String? { get } // For backward compatibility
    var logFileSize: Int64? { get }
    var deviceInfo: DeviceInfo { get }
    var appVersion: String { get }
    var timestamp: Date { get }
    var status: BugReportStatus { get }
    var priority: BugPriority { get }
}

// MARK: - Firebase Bug Report Model

struct FirebaseBugReport: BugReport, Codable {
    @DocumentID var id: String?
    let userId: String
    let userComment: String
    let logFileContent: String? // Base64 encoded log content
    let logFileSize: Int64? // Original file size in bytes
    let deviceInfo: DeviceInfo
    let appVersion: String
    let timestamp: Date
    let status: BugReportStatus
    let priority: BugPriority
    
    init(userId: String, userComment: String, logFileContent: String? = nil, logFileSize: Int64? = nil) {
        // @DocumentID property will be nil initially and set by Firestore
        self._id = DocumentID(wrappedValue: nil)
        self.userId = userId
        self.userComment = userComment
        self.logFileContent = logFileContent
        self.logFileSize = logFileSize
        self.deviceInfo = DeviceInfo.current
        self.appVersion = Bundle.main.appVersionWithBuild
        self.timestamp = Date()
        self.status = .submitted
        self.priority = .normal
    }
}

struct DeviceInfo: Codable {
    let model: String
    let systemVersion: String
    let appVersion: String
    let buildNumber: String
    
    static var current: DeviceInfo {
        DeviceInfo(
            model: UIDevice.current.model,
            systemVersion: UIDevice.current.systemVersion,
            appVersion: Bundle.main.appVersion,
            buildNumber: Bundle.main.buildNumber
        )
    }
}

enum BugReportStatus: String, Codable, CaseIterable {
    case submitted = "submitted"
    case inProgress = "in_progress"
    case resolved = "resolved"
    case closed = "closed"
    
    var displayName: String {
        switch self {
        case .submitted:
            return "Submitted"
        case .inProgress:
            return "In Progress"
        case .resolved:
            return "Resolved"
        case .closed:
            return "Closed"
        }
    }
}

enum BugPriority: String, Codable, CaseIterable {
    case low = "low"
    case normal = "normal"
    case high = "high"
    case critical = "critical"
    
    var displayName: String {
        switch self {
        case .low:
            return "Low"
        case .normal:
            return "Normal"
        case .high:
            return "High"
        case .critical:
            return "Critical"
        }
    }
}

enum BugReportError: LocalizedError {
    case storageError(Error)
    case firestoreError(Error)
    case fileNotFound
    case invalidData
    case authenticationRequired
    
    var errorDescription: String? {
        switch self {
        case .storageError(let error):
            return "Storage error: \(error.localizedDescription)"
        case .firestoreError(let error):
            return "Database error: \(error.localizedDescription)"
        case .fileNotFound:
            return "Log file not found"
        case .invalidData:
            return "Invalid data format"
        case .authenticationRequired:
            return "User authentication required"
        }
    }
}