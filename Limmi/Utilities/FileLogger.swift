import Foundation
import Combine

/// File-based logging system with buffering and automatic rotation.
///
/// This class provides persistent file logging that works reliably in background
/// execution modes where system logging may not be available. Essential for
/// debugging beacon monitoring behavior when the debugger is not attached.
///
/// ## Features
/// - Automatic log file rotation when size exceeds 2MB
/// - Buffered writes for performance (writes every 200 lines or 10 seconds)
/// - Thread-safe operations using dedicated serial queue
/// - Real-time log line publishing for UI integration
/// - Multiple log levels (DEBUG, INFO, LOG, ERROR, FAULT)
///
/// ## Background Behavior
/// The file logger is crucial for understanding app behavior in background
/// execution modes where:
/// - Console logging may not be accessible
/// - Debugger attachment changes CoreLocation behavior
/// - Background processing time is limited
///
/// ## Performance
/// - Uses buffered I/O to minimize file system operations
/// - Automatic rotation prevents unlimited disk usage
/// - Serial queue prevents write conflicts
///
/// - Important: Singleton instance ensures consistent logging across app
/// - Since: 1.0
final class FileLogger {
    static let shared = FileLogger()
    
    // MARK: - Properties
    
    /// Serial queue for thread-safe log operations.
    private let logQueue = DispatchQueue(label: "com.limmi.filelogger.queue", qos: .utility)
    
    /// File manager for log file operations.
    private let fileManager = FileManager.default
    
    /// Primary log file name in Documents directory (process-specific).
    private let logFileName: String
    
    /// Base name for rotated log files (process-specific).
    private let rotatedLogFileBaseName: String
    
    /// Maximum log file size before rotation (2 MB).
    private let maxLogFileSize: Int = 2 * 1024 * 1024
    
    /// Maximum number of rotated log files to keep (total context).
    private let maxRotatedFiles: Int = 10
    
    /// Date formatter for log timestamps.
    private let dateFormatter: DateFormatter
    
    private var logFileURL: URL {
        if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.com.ah.limmi.shareddata") {
            return containerURL.appendingPathComponent(logFileName)
        } else {
            // Fallback to Documents directory if app group not available
            let urls = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
            return urls[0].appendingPathComponent(logFileName)
        }
    }
    
    private var logContainerURL: URL {
        if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.com.ah.limmi.shareddata") {
            return containerURL
        } else {
            // Fallback to Documents directory if app group not available
            let urls = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
            return urls[0]
        }
    }
    
    // MARK: - Buffering Properties
    
    /// In-memory buffer for log lines before writing to disk.
    private var logBuffer: [String] = []
    
    /// Maximum buffer size before forced flush.
    private let bufferLimit: Int
    
    /// Maximum time between flushes.
    private let flushInterval: TimeInterval
    
    /// Timer for periodic buffer flushing.
    private var flushTimer: Timer?
    
    /// Whether this is running in a DAM extension (affects flushing behavior)
    private let isDAMExtension: Bool
    
    /// Publishes each new log line for real-time UI updates.
    /// 
    /// This publisher emits log lines immediately when they are added to the buffer,
    /// enabling real-time log viewing in the app UI without reading from disk.
    let logLinePublisher = PassthroughSubject<String, Never>()
    
    private init() {
        // Detect process type and set appropriate log file names
        let processName = ProcessInfo.processInfo.processName
        let bundleId = Bundle.main.bundleIdentifier
        isDAMExtension = processName.contains("DAM") || processName.contains("DeviceActivity") || 
                        bundleId?.contains("shield") == true
        
        if isDAMExtension {
            logFileName = "dam_extension_log.txt"
            rotatedLogFileBaseName = "dam_extension_log"
            // DAM extension runs briefly with no timer support - flush immediately
            bufferLimit = 1
            flushInterval = 0.1 // Won't be used, but set low just in case
        } else {
            logFileName = "main_app_log.txt"
            rotatedLogFileBaseName = "main_app_log"
            // Main app runs longer - can use larger buffer
            bufferLimit = 20
            flushInterval = 2.0
        }
        
        // Debug: Log the initialization details
        print("FileLogger Init - Process: \(processName), Bundle: \(bundleId ?? "nil"), isDAMExtension: \(isDAMExtension)")
        print("FileLogger Init - Using log file: \(logFileName), bufferLimit: \(bufferLimit), flushInterval: \(flushInterval)")
        
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        // Ensure the Documents directory exists only once at startup
        let urls = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let dirURL = urls[0]
        if !fileManager.fileExists(atPath: dirURL.path) {
            try? fileManager.createDirectory(at: dirURL, withIntermediateDirectories: true, attributes: nil)
        }
        
        // Handle migration from old log file name to new process-specific names
        migrateOldLogFiles()
        
        // Only start timer in main app - DAM extensions can't rely on timers
        if !isDAMExtension {
            startFlushTimer()
        }
    }
    
    /// Migrates old log files (app_log.txt) to new process-specific names
    private func migrateOldLogFiles() {
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.com.ah.limmi.shareddata") else {
            return
        }
        
        let oldLogFile = containerURL.appendingPathComponent("app_log.txt")
        let oldRotatedLogFile = containerURL.appendingPathComponent("app_log.1.txt")
        
        // Only migrate if we're in the main app (since the old logs were from the main app)
        let processName = ProcessInfo.processInfo.processName
        let isMainApp = !processName.contains("shield") && !processName.contains("DeviceActivity") && 
                       Bundle.main.bundleIdentifier?.contains("shield") != true
        
        if isMainApp {
            // Migrate main log file
            if fileManager.fileExists(atPath: oldLogFile.path) && !fileManager.fileExists(atPath: logFileURL.path) {
                try? fileManager.moveItem(at: oldLogFile, to: logFileURL)
                print("FileLogger Migration - Moved old log file to: \(logFileName)")
            }
            
            // Migrate rotated log file to first rotation slot
            let newRotatedLogFile = logContainerURL.appendingPathComponent("\(rotatedLogFileBaseName).1.txt")
            if fileManager.fileExists(atPath: oldRotatedLogFile.path) && !fileManager.fileExists(atPath: newRotatedLogFile.path) {
                try? fileManager.moveItem(at: oldRotatedLogFile, to: newRotatedLogFile)
                print("FileLogger Migration - Moved old rotated log file to: \(rotatedLogFileBaseName).1.txt")
            }
        }
    }
    
    deinit {
        flushTimer?.invalidate()
        flushBufferToDisk()
    }
    
    /// Log levels matching os.Logger levels for consistency.
    enum LogLevel: String {
        case debug = "DEBUG"   /// Detailed debugging information
        case info = "INFO"     /// General informational messages
        case log = "LOG"       /// Standard log messages
        case error = "ERROR"   /// Error conditions that don't stop execution
        case fault = "FAULT"   /// Serious errors that may cause crashes
    }
    
    /// Writes a log message with specified level to buffer and publishes for real-time updates.
    ///
    /// Formats the message with timestamp and level, adds to buffer, and flushes
    /// if buffer limit is reached. All operations are performed on the log queue
    /// for thread safety.
    ///
    /// - Parameters:
    ///   - message: The message to log
    ///   - level: The severity level of the message
    private func write(_ message: String, level: LogLevel, category: String? = nil) {
        let timestamp = dateFormatter.string(from: Date())
        let categoryInfo = category != nil ? " [\(category!)]" : ""
        let logLine = "[\(timestamp)][\(level.rawValue)]\(categoryInfo) \(message)\n"
        logQueue.async {
            self.logBuffer.append(logLine)
            self.logLinePublisher.send(logLine) // Publish new log line
            if self.logBuffer.count >= self.bufferLimit {
                self.flushBufferToDisk()
            }
        }
    }
    
    /// Rotates log files when the primary log exceeds size limit.
    ///
    /// Implements a multi-file rotation strategy:
    /// 1. If main log > 2MB, start rotation process
    /// 2. Shift existing rotated files: log.9.txt -> log.10.txt, log.8.txt -> log.9.txt, etc.
    /// 3. Move current log to log.1.txt
    /// 4. Delete oldest file if we exceed maxRotatedFiles
    /// 5. Create new empty main log file
    ///
    /// This preserves much more log history while preventing unlimited disk usage.
    private func rotateLogsIfNeeded() {
        // Check if main log file is too large
        guard let attrs = try? fileManager.attributesOfItem(atPath: logFileURL.path),
              let fileSize = attrs[.size] as? NSNumber,
              fileSize.intValue > maxLogFileSize else {
            return
        }
        
        print("FileLogger: Rotating logs - main file size: \(fileSize.intValue) bytes")
        
        // First, remove the oldest file if it exists (would be maxRotatedFiles)
        let oldestFileURL = logContainerURL.appendingPathComponent("\(rotatedLogFileBaseName).\(maxRotatedFiles).txt")
        if fileManager.fileExists(atPath: oldestFileURL.path) {
            try? fileManager.removeItem(at: oldestFileURL)
            print("FileLogger: Removed oldest log file: \(rotatedLogFileBaseName).\(maxRotatedFiles).txt")
        }
        
        // Shift all existing rotated files up by one number
        // Start from maxRotatedFiles-1 down to 1 to avoid overwriting
        for i in stride(from: maxRotatedFiles - 1, through: 1, by: -1) {
            let currentFile = logContainerURL.appendingPathComponent("\(rotatedLogFileBaseName).\(i).txt")
            let nextFile = logContainerURL.appendingPathComponent("\(rotatedLogFileBaseName).\(i + 1).txt")
            
            if fileManager.fileExists(atPath: currentFile.path) {
                // Remove destination if it exists (shouldn't happen but just in case)
                if fileManager.fileExists(atPath: nextFile.path) {
                    try? fileManager.removeItem(at: nextFile)
                }
                // Move current file to next number
                try? fileManager.moveItem(at: currentFile, to: nextFile)
                print("FileLogger: Moved \(rotatedLogFileBaseName).\(i).txt -> \(rotatedLogFileBaseName).\(i + 1).txt")
            }
        }
        
        // Move current log to .1.txt
        let firstRotatedFile = logContainerURL.appendingPathComponent("\(rotatedLogFileBaseName).1.txt")
        if fileManager.fileExists(atPath: firstRotatedFile.path) {
            try? fileManager.removeItem(at: firstRotatedFile)
        }
        try? fileManager.moveItem(at: logFileURL, to: firstRotatedFile)
        print("FileLogger: Moved current log to \(rotatedLogFileBaseName).1.txt")
    }
    
    /// Flushes the in-memory log buffer to disk.
    ///
    /// Writes all buffered log lines to the log file, handling rotation if needed.
    /// Uses append mode to preserve existing logs. Called automatically when
    /// buffer reaches limit or timer expires.
    private func flushBufferToDisk() {
        guard !logBuffer.isEmpty else { return }
        self.rotateLogsIfNeeded()
        let data = logBuffer.joined().data(using: .utf8)!
        logBuffer.removeAll()
        if self.fileManager.fileExists(atPath: self.logFileURL.path) {
            if let fileHandle = try? FileHandle(forWritingTo: self.logFileURL) {
                defer { fileHandle.closeFile() }
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
            }
        } else {
            try? data.write(to: self.logFileURL)
        }
    }
    
    private func startFlushTimer() {
        flushTimer = Timer.scheduledTimer(withTimeInterval: flushInterval, repeats: true) { [weak self] _ in
            self?.logQueue.async {
                self?.flushBufferToDisk()
            }
        }
    }
    
    // MARK: - Public Logging Methods
    
    /// Logs a debug message for detailed diagnostic information.
    /// - Parameter message: Debug message to log
    /// - Parameter category: Optional category information for context
    func debug(_ message: String, category: String? = nil) {
        write(message, level: .debug, category: category)
    }
    
    /// Logs an informational message for general app events.
    /// - Parameter message: Info message to log
    /// - Parameter category: Optional category information for context
    func info(_ message: String, category: String? = nil) {
        write(message, level: .info, category: category)
    }
    
    /// Logs a standard message for normal app operations.
    /// - Parameter message: Log message to log
    /// - Parameter category: Optional category information for context
    func log(_ message: String, category: String? = nil) {
        write(message, level: .log, category: category)
    }
    
    /// Logs an error message for recoverable error conditions.
    /// - Parameter message: Error message to log
    /// - Parameter category: Optional category information for context
    func error(_ message: String, category: String? = nil) {
        write(message, level: .error, category: category)
    }
    
    /// Logs a fault message for serious errors that may cause crashes.
    /// - Parameter message: Fault message to log
    /// - Parameter category: Optional category information for context
    func fault(_ message: String, category: String? = nil) {
        write(message, level: .fault, category: category)
    }
    
    /// Forces an immediate flush of the log buffer to disk.
    /// 
    /// This method bypasses the normal buffering and immediately writes all pending
    /// log entries to disk. Useful for critical operations where logs must be persisted
    /// immediately, such as in extensions that may terminate unexpectedly.
    /// 
    /// - Parameter synchronous: If true, blocks until flush is complete. Use for extensions.
    func forceFlush(synchronous: Bool = false) {
        if synchronous {
            logQueue.sync {
                self.flushBufferToDisk()
            }
        } else {
            logQueue.async {
                self.flushBufferToDisk()
            }
        }
    }
    
    /// Returns the URL of the primary log file for sharing or exporting.
    /// 
    /// The returned URL points to the main log file in the app's Documents directory.
    /// This file contains the most recent log entries and can be shared via system share sheet.
    /// 
    /// - Returns: URL of the primary log file
    func getLogFileURL() -> URL {
        return logFileURL
    }
    
    /// Returns the URL of the most recent rotated log file if it exists.
    /// 
    /// The rotated log file contains older log entries that were moved during log rotation.
    /// This method returns the newest rotated file (.1.txt), or nil if no rotated files exist.
    /// 
    /// - Returns: URL of the most recent rotated log file, or nil if it doesn't exist
    func getRotatedLogFileURL() -> URL? {
        let firstRotatedFile = logContainerURL.appendingPathComponent("\(rotatedLogFileBaseName).1.txt")
        guard fileManager.fileExists(atPath: firstRotatedFile.path) else {
            return nil
        }
        return firstRotatedFile
    }
    
    /// Returns URLs of all available log files (current and rotated).
    /// 
    /// This method returns an array of all log file URLs that exist on disk,
    /// including both the current log file and any rotated log files.
    /// When called from the main app, it also includes DAM extension log files.
    /// Useful for comprehensive log collection and AWS upload scenarios.
    /// 
    /// - Returns: Array of log file URLs, ordered by process and recency
    func getAllLogFileURLs() -> [URL] {
        var urls: [URL] = []
        
        // Add current process log files (main file first)
        if fileManager.fileExists(atPath: logFileURL.path) {
            urls.append(logFileURL)
        }
        
        // Add all rotated files for current process (newest to oldest)
        for i in 1...maxRotatedFiles {
            let rotatedFileURL = logContainerURL.appendingPathComponent("\(rotatedLogFileBaseName).\(i).txt")
            if fileManager.fileExists(atPath: rotatedFileURL.path) {
                urls.append(rotatedFileURL)
            }
        }
        
        // If this is the main app, also include DAM extension log files
        let processName = ProcessInfo.processInfo.processName
        let bundleId = Bundle.main.bundleIdentifier
        let isMainApp = !processName.contains("shield") && !processName.contains("DeviceActivity") && 
                       bundleId?.contains("shield") != true
        
        // Debug: Log the process detection details
        print("FileLogger Debug - Process: \(processName), Bundle: \(bundleId ?? "nil"), isMainApp: \(isMainApp)")
        
        if isMainApp {
            // Add DAM extension main log file
            let damLogURL = getDamLogFileURL(fileName: "dam_extension_log.txt")
            print("FileLogger Debug - Checking DAM logs: \(damLogURL.path)")
            if fileManager.fileExists(atPath: damLogURL.path) {
                print("FileLogger Debug - Found DAM log file")
                urls.append(damLogURL)
            }
            
            // Add all DAM extension rotated files
            for i in 1...maxRotatedFiles {
                let damRotatedLogURL = getDamLogFileURL(fileName: "dam_extension_log.\(i).txt")
                if fileManager.fileExists(atPath: damRotatedLogURL.path) {
                    print("FileLogger Debug - Found DAM rotated log file: dam_extension_log.\(i).txt")
                    urls.append(damRotatedLogURL)
                }
            }
        }
        
        return urls
    }
    
    /// Helper method to construct DAM extension log file URLs
    private func getDamLogFileURL(fileName: String) -> URL {
        if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.com.ah.limmi.shareddata") {
            return containerURL.appendingPathComponent(fileName)
        } else {
            // Fallback to Documents directory if app group not available
            let urls = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
            return urls[0].appendingPathComponent(fileName)
        }
    }
    
    /// Extracts the rotation number from a log file name (e.g., "app_log.5.txt" -> 5)
    private func extractRotationNumber(from fileName: String) -> Int {
        let components = fileName.components(separatedBy: ".")
        if components.count >= 3, let number = Int(components[components.count - 2]) {
            return number
        }
        return 0 // Current file (no rotation number)
    }
    
    /// Returns the total size of all log files in bytes
    func getTotalLogSize() -> Int64 {
        let allFiles = getAllLogFileURLs()
        var totalSize: Int64 = 0
        
        for fileURL in allFiles {
            if let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path),
               let fileSize = attrs[.size] as? NSNumber {
                totalSize += fileSize.int64Value
            }
        }
        
        return totalSize
    }
    
    /// Returns a summary of all log files and their sizes
    func getLogFilesSummary() -> String {
        let allFiles = getAllLogFileURLs()
        var summary = "Log Files Summary:\n"
        var totalSize: Int64 = 0
        
        for fileURL in allFiles {
            if let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path),
               let fileSize = attrs[.size] as? NSNumber,
               let modDate = attrs[.modificationDate] as? Date {
                let sizeKB = fileSize.doubleValue / 1024.0
                totalSize += fileSize.int64Value
                summary += "- \(fileURL.lastPathComponent): \(String(format: "%.1f", sizeKB))KB (modified: \(modDate))\n"
            }
        }
        
        let totalMB = Double(totalSize) / (1024.0 * 1024.0)
        summary += "Total: \(String(format: "%.2f", totalMB))MB across \(allFiles.count) files"
        
        return summary
    }
    
    /// Creates a consolidated log file containing all available logs from both processes.
    /// 
    /// This method creates a temporary file that combines the content of all
    /// log files (main app and DAM extension, current and rotated).
    /// The consolidated file is organized by process and chronology.
    /// 
    /// For very large log contexts (>50MB), this method will include a summary
    /// of files and their sizes at the top for efficiency.
    /// 
    /// The caller is responsible for cleaning up the returned temporary file.
    /// 
    /// - Returns: URL of the consolidated log file, or nil if creation failed
    func createConsolidatedLogFile() -> URL? {
        let allLogURLs = getAllLogFileURLs()
        guard !allLogURLs.isEmpty else {
            return nil
        }
        
        // Always create a consolidated file with section headers for better organization
        // Create temporary file for consolidated logs
        let tempURL = fileManager.temporaryDirectory
            .appendingPathComponent("consolidated_logs_\(UUID().uuidString).txt")
        
        do {
            var consolidatedContent = ""
            let totalSize = getTotalLogSize()
            let totalMB = Double(totalSize) / (1024.0 * 1024.0)
            
            // Add debug info about what we found
            consolidatedContent += "=== LOG CONSOLIDATION DEBUG ===\n"
            consolidatedContent += "Total log context: \(String(format: "%.2f", totalMB))MB across \(allLogURLs.count) files\n"
            consolidatedContent += "Rotation strategy: \(maxRotatedFiles) files, \(maxLogFileSize / (1024 * 1024))MB per file\n"
            consolidatedContent += "\nFound log files:\n"
            for url in allLogURLs {
                if let attrs = try? fileManager.attributesOfItem(atPath: url.path),
                   let fileSize = attrs[.size] as? NSNumber,
                   let modDate = attrs[.modificationDate] as? Date {
                    let sizeKB = fileSize.doubleValue / 1024.0
                    consolidatedContent += "- \(url.lastPathComponent) (\(String(format: "%.1f", sizeKB))KB, modified: \(modDate))\n"
                } else {
                    consolidatedContent += "- \(url.lastPathComponent)\n"
                }
            }
            consolidatedContent += "\n"
            
            // Group URLs by process type and sort for chronological order
            let mainAppURLs = allLogURLs.filter { url in
                url.lastPathComponent.hasPrefix("main_app_log")
            }.sorted { url1, url2 in
                // Sort by file name to get chronological order (current, .1, .2, etc.)
                return url1.lastPathComponent < url2.lastPathComponent
            }
            
            let damExtensionURLs = allLogURLs.filter { url in
                url.lastPathComponent.hasPrefix("dam_extension_log")
            }.sorted { url1, url2 in
                // Sort by file name to get chronological order (current, .1, .2, etc.)
                return url1.lastPathComponent < url2.lastPathComponent
            }
            
            // Add main app logs (oldest to newest for chronological reading)
            if !mainAppURLs.isEmpty {
                consolidatedContent += "=== MAIN APP LOGS ===\n"
                
                // Process rotated files in reverse order (oldest first: .10, .9, .8, ..., .1)
                let rotatedFiles = mainAppURLs.filter { $0.lastPathComponent.contains(".") }
                    .sorted { url1, url2 in
                        let num1 = extractRotationNumber(from: url1.lastPathComponent)
                        let num2 = extractRotationNumber(from: url2.lastPathComponent)
                        return num1 > num2 // Higher numbers are older
                    }
                
                // Add rotated files first (oldest to newest)
                for logURL in rotatedFiles {
                    consolidatedContent += "--- \(logURL.lastPathComponent) ---\n"
                    let content = try String(contentsOf: logURL, encoding: .utf8)
                    consolidatedContent += content
                    if !content.hasSuffix("\n") {
                        consolidatedContent += "\n"
                    }
                    consolidatedContent += "\n"
                }
                
                // Add current file last (newest)
                if let currentFile = mainAppURLs.first(where: { !$0.lastPathComponent.contains(".") }) {
                    consolidatedContent += "--- \(currentFile.lastPathComponent) (CURRENT) ---\n"
                    let content = try String(contentsOf: currentFile, encoding: .utf8)
                    consolidatedContent += content
                    if !content.hasSuffix("\n") {
                        consolidatedContent += "\n"
                    }
                }
                consolidatedContent += "\n"
            }
            
            // Add DAM extension logs (same chronological order)
            if !damExtensionURLs.isEmpty {
                consolidatedContent += "=== DAM EXTENSION LOGS ===\n"
                
                // Process rotated files in reverse order (oldest first)
                let rotatedFiles = damExtensionURLs.filter { $0.lastPathComponent.contains(".") }
                    .sorted { url1, url2 in
                        let num1 = extractRotationNumber(from: url1.lastPathComponent)
                        let num2 = extractRotationNumber(from: url2.lastPathComponent)
                        return num1 > num2 // Higher numbers are older
                    }
                
                // Add rotated files first (oldest to newest)
                for logURL in rotatedFiles {
                    consolidatedContent += "--- \(logURL.lastPathComponent) ---\n"
                    let content = try String(contentsOf: logURL, encoding: .utf8)
                    consolidatedContent += content
                    if !content.hasSuffix("\n") {
                        consolidatedContent += "\n"
                    }
                    consolidatedContent += "\n"
                }
                
                // Add current file last (newest)
                if let currentFile = damExtensionURLs.first(where: { !$0.lastPathComponent.contains(".") }) {
                    consolidatedContent += "--- \(currentFile.lastPathComponent) (CURRENT) ---\n"
                    let content = try String(contentsOf: currentFile, encoding: .utf8)
                    consolidatedContent += content
                    if !content.hasSuffix("\n") {
                        consolidatedContent += "\n"
                    }
                }
            }
            
            // Write consolidated content to temporary file
            try consolidatedContent.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
            
        } catch {
            return nil
        }
    }
    
    /// Clears all log files and resets the logging system.
    /// 
    /// Removes the primary log file and all rotated log files from disk.
    /// Useful for clearing sensitive information or resetting log state for testing.
    /// Operation is performed asynchronously on the log queue.
    func clear() {
        logQueue.async {
            // Remove main log file
            try? self.fileManager.removeItem(at: self.logFileURL)
            
            // Remove all rotated log files
            for i in 1...self.maxRotatedFiles {
                let rotatedFileURL = self.logContainerURL.appendingPathComponent("\(self.rotatedLogFileBaseName).\(i).txt")
                try? self.fileManager.removeItem(at: rotatedFileURL)
            }
        }
    }
}

#if canImport(os)
import os
#endif

/// Unified logging wrapper that writes to both file and system logs.
///
/// This struct provides a single interface for logging that writes to both:
/// - FileLogger for persistent file-based logging
/// - os.Logger for system logging and Console.app integration
///
/// ## Benefits
/// - Consistent logging interface across the app
/// - File logs persist and work in background/without debugger
/// - System logs integrate with development tools and Console.app
/// - Conditional compilation handles platforms without os.Logger
///
/// ## Usage
/// ```swift
/// let logger = UnifiedLogger(
///     fileLogger: .shared,
///     osLogger: Logger(subsystem: "com.limmi.app", category: "MyClass")
/// )
/// logger.debug("App event occurred")
/// ```
///
/// - Since: 1.0
struct UnifiedLogger {
    let fileLogger: FileLogger
    #if canImport(os)
    let osLogger: Logger?
    #else
    let osLogger: Any? = nil
    #endif
    
    /// Initializes unified logger with file and system loggers.
    /// 
    /// - Parameters:
    ///   - fileLogger: File logger instance (defaults to shared)
    ///   - osLogger: System logger instance (optional)
    init(fileLogger: FileLogger = .shared, osLogger: Logger? = nil) {
        self.fileLogger = fileLogger
        self.osLogger = osLogger
    }
    
    /// Extracts subsystem and category information from the os.Logger if available.
    /// - Returns: Formatted category string like "[subsystem.category]" or nil
    private func getCategoryInfo() -> String? {
        #if canImport(os)
        if let logger = osLogger {
            // Use reflection to extract subsystem and category from Logger
            let mirror = Mirror(reflecting: logger)
            var subsystem: String?
            var category: String?
            
            for child in mirror.children {
                if child.label == "subsystem" {
                    subsystem = child.value as? String
                } else if child.label == "category" {
                    category = child.value as? String
                }
            }
            
            if let sub = subsystem, let cat = category {
                return "\(sub).\(cat)"
            } else if let cat = category {
                return cat
            }
        }
        #endif
        return nil
    }
    
    /// Logs debug message to both file and system logs.
    /// - Parameter message: Debug message to log
    func debug(_ message: String) {
        let categoryInfo = getCategoryInfo()
        fileLogger.debug(message, category: categoryInfo)
        #if canImport(os)
        osLogger?.debug("\(message, privacy: .public)")
        #endif
    }
    func info(_ message: String) {
        let categoryInfo = getCategoryInfo()
        fileLogger.info(message, category: categoryInfo)
        #if canImport(os)
        osLogger?.info("\(message, privacy: .public)")
        #endif
    }
    func log(_ message: String) {
        let categoryInfo = getCategoryInfo()
        fileLogger.log(message, category: categoryInfo)
        #if canImport(os)
        osLogger?.log("\(message, privacy: .public)")
        #endif
    }
    func error(_ message: String) {
        let categoryInfo = getCategoryInfo()
        fileLogger.error(message, category: categoryInfo)
        #if canImport(os)
        osLogger?.error("\(message, privacy: .public)")
        #endif
    }
    func fault(_ message: String) {
        let categoryInfo = getCategoryInfo()
        fileLogger.fault(message, category: categoryInfo)
        #if canImport(os)
        osLogger?.fault("\(message, privacy: .public)")
        #endif
    }
    
    /// Forces an immediate flush of file logs to disk.
    /// Useful for critical operations where logs must be persisted immediately.
    /// - Parameter synchronous: If true, blocks until flush is complete. Use for extensions.
    func forceFlush(synchronous: Bool = false) {
        fileLogger.forceFlush(synchronous: synchronous)
    }
}

/*
// Example usage:
let beaconLogger = UnifiedLogger(
    fileLogger: .shared,
    osLogger: Logger(subsystem: "com.yourcompany.limmi", category: "beacon")
)
beaconLogger.log("Beacon event started")
beaconLogger.error("Beacon error occurred")
*/ 
