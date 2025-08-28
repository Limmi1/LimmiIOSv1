import SwiftUI
import CoreLocation
#if canImport(Charts)
import Charts
#endif
import Combine

/*
 RegionMonitoringManager: didEnterRegion CLBeaconRegion (identifier:'BeaconRegion_E2C56DB5-0001-48D2-B060-D0F5A71096E0:1331:1', uuid:E2C56DB5-0001-48D2-B060-D0F5A71096E0, major:1331, minor:1)
 RegionMonitoringManager: didExitRegion CLBeaconRegion (identifier:'BeaconRegion_E2C56DB5-0001-48D2-B060-D0F5A71096E0:1331:1', uuid:E2C56DB5-0001-48D2-B060-D0F5A71096E0, major:1331, minor:1)
 RSSIRangingManager: Detected BeaconID(uuid: E2C56DB5-0001-48D2-B060-D0F5A71096E0, major: Optional(1331), minor: Optional(1)) with RSSI -74
 
 */


private let dateFormatter: DateFormatter = {
    let df = DateFormatter()
    df.dateFormat = "HH:mm:ss"
    return df
}()

private let fullDateFormatter: DateFormatter = {
    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS ZZZ"
    return df
}()

class BeaconLogViewModel: ObservableObject {
    @Published var rssiLogs: [(timestamp: Date, rssi: Int, beaconID: String)] = []
    @Published var eventLogs: [(timestamp: Date, event: String, beaconID: String)] = []
    @Published var errorMessage: String? = nil
    private var logLineCancellable: AnyCancellable?
    private let logFileURL = FileLogger.shared.getLogFileURL()
    private let maxLogFileSize: Int = 2 * 1024 * 1024 // 2 MB
    private let maxInMemoryLogs = 1000

    init() {
        // Initial hydration from file
        hydrateFromFile()
        // Subscribe to real-time log updates
        logLineCancellable = FileLogger.shared.logLinePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] line in
                self?.parseAndAppendLogLine(String(line))
            }
    }

    deinit {
        logLineCancellable?.cancel()
    }
    
    func debugLogFile() {
        print("DEBUG: Manually triggering log file debug")
        hydrateFromFile()
        
        // Test with sample log lines (both old and new formats)
        let sampleLines = [
            // Old format
            "[2025-07-23 07:20:28.469] [DEBUG] RSSIRangingManager: Detected BeaconID(uuid: E2C56DB5-0001-48D2-B060-D0F5A71096E0, major: Optional(1331), minor: Optional(1)) with RSSI -74",
            "[2025-07-23 07:20:28.469] [DEBUG] RegionMonitoringManager: didEnterRegion CLBeaconRegion (identifier:'BeaconRegion_E2C56DB5-0001-48D2-B060-D0F5A71096E0:1331:1', uuid:E2C56DB5-0001-48D2-B060-D0F5A71096E0, major:1331, minor:1)",
            // New format with category
            "[2025-07-23 07:20:28.469][DEBUG] [com.limmi.app.BeaconMonitor] RSSIRangingManager: Detected BeaconID(uuid: E2C56DB5-0001-48D2-B060-D0F5A71096E0, major: Optional(1331), minor: Optional(1)) with RSSI -74",
            "[2025-07-23 07:20:28.469][DEBUG] [com.limmi.app.BeaconMonitor] RegionMonitoringManager: didExitRegion CLBeaconRegion (identifier:'BeaconRegion_E2C56DB5-0001-48D2-B060-D0F5A71096E0:1331:1', uuid:E2C56DB5-0001-48D2-B060-D0F5A71096E0, major:1331, minor:1)",
            "[2025-07-23 07:20:28.469][DEBUG] [com.limmi.app.BeaconMonitor] RegionMonitoringManager: didDetermineState 1 for CLBeaconRegion (identifier:'BeaconRegion_E2C56DB5-0001-48D2-B060-D0F5A71096E0:1331:1', uuid:E2C56DB5-0001-48D2-B060-D0F5A71096E0, major:1331, minor:1)",
        ]
        
        for (index, sampleLine) in sampleLines.enumerated() {
            var testRSSI: [(Date, Int, String)] = []
            var testEvents: [(Date, String, String)] = []
            parseLogLine(sampleLine, rssiLogs: &testRSSI, eventLogs: &testEvents)
            print("DEBUG: Sample line \(index) - RSSI: \(testRSSI.count), Events: \(testEvents.count)")
            if !testRSSI.isEmpty {
                print("DEBUG: Sample RSSI \(index): \(testRSSI[0])")
            }
            if !testEvents.isEmpty {
                print("DEBUG: Sample Event \(index): \(testEvents[0])")
            }
        }
    }

    private func hydrateFromFile() {
        // Check file size first
        if let attrs = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
           let fileSize = attrs[.size] as? NSNumber, fileSize.intValue > maxLogFileSize {
            self.errorMessage = "Log file is too large to display (>2 MB). Please clear the log file from settings."
            self.rssiLogs = []
            self.eventLogs = []
            return
        }
        guard let data = try? Data(contentsOf: logFileURL),
              let content = String(data: data, encoding: .utf8) else {
            self.errorMessage = "No log file found or unable to read log file at: \(logFileURL.path)"
            self.rssiLogs = []
            self.eventLogs = []
            return
        }
        
        print("DEBUG: Log file content length: \(content.count) characters")
        let lines = content.split(separator: "\n")
        print("DEBUG: Found \(lines.count) lines in log file")
        
        var newRSSI: [(Date, Int, String)] = []
        var newEvents: [(Date, String, String)] = []
        var parsedLines = 0
        
        for (index, line) in lines.enumerated() {
            let lineString = String(line)
            if index < 5 {
                print("DEBUG: Sample line \(index): \(lineString)")
            }
            parseLogLine(lineString, rssiLogs: &newRSSI, eventLogs: &newEvents)
            if !newRSSI.isEmpty || !newEvents.isEmpty {
                parsedLines += 1
            }
        }
        
        print("DEBUG: Successfully parsed \(parsedLines) lines")
        print("DEBUG: Found \(newRSSI.count) RSSI logs, \(newEvents.count) event logs")
        
        self.errorMessage = nil
        self.rssiLogs = Array(newRSSI.suffix(maxInMemoryLogs))
        self.eventLogs = Array(newEvents.suffix(maxInMemoryLogs))
    }

    private func parseAndAppendLogLine(_ line: String) {
        var rssiArr: [(Date, Int, String)] = []
        var eventArr: [(Date, String, String)] = []
        parseLogLine(line, rssiLogs: &rssiArr, eventLogs: &eventArr)
        if let rssi = rssiArr.first {
            rssiLogs.append(rssi)
            if rssiLogs.count > maxInMemoryLogs { rssiLogs.removeFirst() }
        }
        if let event = eventArr.first {
            eventLogs.append(event)
            if eventLogs.count > maxInMemoryLogs { eventLogs.removeFirst() }
        }
    }

    // Parse log lines in format: [timestamp] [LEVEL] message or [timestamp][LEVEL] [category] message
    private func parseLogLine(_ line: String, rssiLogs: inout [(Date, Int, String)], eventLogs: inout [(Date, String, String)]) {
        guard line.count > 30, line.hasPrefix("[") else { return }
        
        // Extract timestamp from [timestamp]
        guard let timestampEnd = line.firstIndex(of: "]") else { return }
        let timestampString = String(line[line.index(after: line.startIndex)..<timestampEnd])
        
        // Parse timestamp
        let timestamp: Date
        if let date = fullDateFormatter.date(from: timestampString) {
            timestamp = date
        } else {
            // Try without timezone
            let simpleDateFormatter = DateFormatter()
            simpleDateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
            if let date = simpleDateFormatter.date(from: timestampString) {
                timestamp = date
            } else {
                return
            }
        }
        
        // Extract the message part after timestamp and level (and optional category)
        let afterTimestamp = line[line.index(after: timestampEnd)...]
        guard let levelEnd = afterTimestamp.firstIndex(of: "]") else { return }
        
        // Check if there's a third bracket for category: [timestamp][LEVEL] [category] message
        let afterLevel = afterTimestamp[afterTimestamp.index(after: levelEnd)...]
        let message: String
        
        if afterLevel.trimmingCharacters(in: .whitespaces).hasPrefix("[") {
            // New format with category: find the end of category bracket
            guard let categoryEnd = afterLevel.firstIndex(of: "]") else { return }
            message = String(afterLevel[afterLevel.index(after: categoryEnd)...]).trimmingCharacters(in: .whitespaces)
        } else {
            // Old format without category
            message = String(afterLevel).trimmingCharacters(in: .whitespaces)
        }
        
        // Parse RSSI readings: "RSSIRangingManager: Detected BeaconID(...) with RSSI -74"
        if message.contains("RSSIRangingManager: Detected BeaconID") && message.contains("with RSSI") {
            if let rssiMatch = message.range(of: "with RSSI (-?\\d+)", options: .regularExpression) {
                let rssiString = String(message[rssiMatch])
                if let rssi = Int(rssiString.components(separatedBy: " ").last ?? ""), rssi != 0 {
                    if let beaconID = extractBeaconID(from: message) {
                        rssiLogs.append((timestamp, rssi, beaconID))
                    }
                }
            }
        }
        // Parse region enter events: "RegionMonitoringManager: didEnterRegion CLBeaconRegion (...)"
        else if message.contains("RegionMonitoringManager: didEnterRegion") {
            if let beaconID = extractBeaconID(from: message) {
                eventLogs.append((timestamp, "Enter", beaconID))
            }
        }
        // Parse region exit events: "RegionMonitoringManager: didExitRegion CLBeaconRegion (...)"
        else if message.contains("RegionMonitoringManager: didExitRegion") {
            if let beaconID = extractBeaconID(from: message) {
                eventLogs.append((timestamp, "Exit", beaconID))
            }
        }
        // Parse didDetermineState events: "RegionMonitoringManager: didDetermineState 1 for CLBeaconRegion (...)"
        else if message.contains("RegionMonitoringManager: didDetermineState") {
            if message.contains("didDetermineState 1 for") {
                // State 1 = Enter
                if let beaconID = extractBeaconID(from: message) {
                    eventLogs.append((timestamp, "Enter", beaconID))
                }
            } else if message.contains("didDetermineState 2 for") {
                // State 2 = Exit
                if let beaconID = extractBeaconID(from: message) {
                    eventLogs.append((timestamp, "Exit", beaconID))
                }
            }
        }
    }
    
    private func extractBeaconID(from message: String) -> String? {
        // Extract UUID - this is always present
        guard let uuid = extractUUID(from: message) else { return nil }
        
        // Check for major and minor - they can be Optional(number) or nil
        let major = extractMajor(from: message) ?? "nil"
        let minor = extractMinor(from: message) ?? "nil"
        
        return "\(uuid)_\(major)_\(minor)"
    }
    
    private func extractUUID(from string: String) -> String? {
        if let range = string.range(of: "uuid: ?([A-Fa-f0-9-]+)", options: .regularExpression) {
            let match = String(string[range])
            return match.components(separatedBy: "uuid: ").last
        }
        return nil
    }
    
    private func extractMajor(from string: String) -> String? {
        // Handle both "major: Optional(number)" and "major: nil"
        if string.contains("major: ?nil") {
            return nil
        }
        
        let pattern = #"(?:major:\s*)(?:Optional\()?(\d+)(?:\))?"#
        let regex = try! NSRegularExpression(pattern: pattern)

        if let match = regex.firstMatch(
             in: string,
             range: NSRange(string.startIndex..., in: string)
           ),
           let digitRange = Range(match.range(at: 1), in: string)
        {
            return String(string[digitRange])
        }
        return nil
    }
    
    private func extractMinor(from string: String) -> String? {
        // Handle both "minor: Optional(number)" and "minor: nil"
        if string.contains("minor: ?nil") {
            return nil
        }

        let pattern = #"(?:minor:\s*)(?:Optional\()?(\d+)(?:\))?"#
        let regex = try! NSRegularExpression(pattern: pattern)

        if let match = regex.firstMatch(
             in: string,
             range: NSRange(string.startIndex..., in: string)
           ),
           let digitRange = Range(match.range(at: 1), in: string)
        {
            return String(string[digitRange])
        }
        return nil
    }
}

// Helper for color assignment
fileprivate func colorForBeacon(_ beaconID: String) -> Color {
    let palette: [Color] = [.purple, .blue, .green, .orange, .red, .pink, .teal, .indigo, .yellow, .brown, .mint, .cyan]
    
    // If minor is available, use it for color selection (more predictable)
    if beaconID.contains("_") {
        let parts = beaconID.components(separatedBy: "_")
        if parts.count >= 3 {
            let minor = parts[2]
            if minor != "nil", let minorInt = Int(minor) {
                return palette[minorInt % palette.count]
            }
        }
    }
    
    // Fallback to hash of beaconID
    let hash = abs(beaconID.hashValue)
    return palette[hash % palette.count]
}

// Helper for beacon name assignment
fileprivate func nameForBeacon(_ beaconID: String) -> String {
    let colorNames = ["Purple", "Blue", "Green", "Orange", "Red", "Pink", "Teal", "Indigo", "Yellow", "Brown", "Mint", "Cyan"]
    
    // Use the same color selection logic as colorForBeacon for consistency
    var colorName: String
    if beaconID.contains("_") {
        let parts = beaconID.components(separatedBy: "_")
        if parts.count >= 3 {
            let major = parts[1]
            let minor = parts[2]
            if minor != "nil", let minorInt = Int(minor) {
                // Use minor for color selection (same as colorForBeacon)
                colorName = colorNames[minorInt % colorNames.count]
                if major != "nil" {
                    return "\(major).\(minor)"
                } else {
                    return "\(minor)"
                }
            }
        }
    }
    
    // Fallback to hash of beaconID (same as colorForBeacon)
    let hash = abs(beaconID.hashValue)
    colorName = colorNames[hash % colorNames.count]
    let suffix = String(beaconID.suffix(4))
    return "\(colorName)-\(suffix)"
}

struct BeaconLogView: View {
    @StateObject private var viewModel = BeaconLogViewModel()
    @State private var chartTick: Int = 0
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Debug button
                HStack {
                    Button("Debug Logs") {
                        viewModel.debugLogFile()
                    }
                    .padding()
                    Spacer()
                }
                .background(Color.gray.opacity(0.1))
                // Entry/Exit Events (top 1/3)
                EntryExitLogSection(
                    eventLogs: viewModel.eventLogs,
                    height: geometry.size.height / 3
                )
                Divider()
                // RSSI Logs (middle 1/3)
                RSSILogSection(
                    rssiLogs: viewModel.rssiLogs,
                    height: geometry.size.height / 3
                )
                Divider()
                // Graph (bottom 1/3)
                Group {
                    #if canImport(Charts)
                    RSSITimeWindowChartLive(
                        liveRSSILogs: viewModel.rssiLogs,
                        eventLogs: viewModel.eventLogs,
                        chartTick: chartTick
                    )
                    #else
                    SimpleRSSIGraphLive(liveRSSILogs: viewModel.rssiLogs, chartTick: chartTick)
                    #endif
                }
                .frame(height: geometry.size.height / 3)
                // Legend
                BeaconLegend(beaconIDs: Array(Set(viewModel.rssiLogs.map { $0.beaconID } + viewModel.eventLogs.map { $0.beaconID })))
            }
            .navigationTitle("Beacon RSSI & Events")
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
                chartTick += 1
            }
            .overlay(
                // Error banner
                Group {
                    if let error = viewModel.errorMessage {
                        Text(error)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.red)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .zIndex(1)
                    }
                }, alignment: .top
            )
        }
    }
}

struct EntryExitLogSection: View {
    let eventLogs: [(timestamp: Date, event: String, beaconID: String)]
    let height: CGFloat
    @State private var highlightedTimestamps: Set<Date> = []
    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .top) {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 8) {
                        Color.clear.frame(height: 28)
                        ForEach(Array(eventLogs.suffix(100).enumerated()), id: \.offset) { index, log in
                            EntryExitLogRow(
                                log: log,
                                isHighlighted: highlightedTimestamps.contains(log.timestamp)
                            )
                            .id("\(log.timestamp.timeIntervalSince1970)_\(log.event)_\(log.beaconID)_\(index)")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding([.horizontal, .bottom])
                .frame(height: height)
                .onChange(of: eventLogs.count) {
                    let suffix = eventLogs.suffix(100)
                    if let last = suffix.last {
                        let lastIndex = suffix.count - 1
                        let lastID = "\(last.timestamp.timeIntervalSince1970)_\(last.event)_\(last.beaconID)_\(lastIndex)"
                        proxy.scrollTo(lastID, anchor: .bottom)
                        highlightedTimestamps.insert(last.timestamp)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            highlightedTimestamps.remove(last.timestamp)
                        }
                    }
                }
                Text("Entry/Exit Events")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top, 4)
                    .background(Color(.systemBackground).opacity(0.95))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .zIndex(1)
            }
        }
    }
}

struct EntryExitLogRow: View {
    let log: (timestamp: Date, event: String, beaconID: String)
    let isHighlighted: Bool
    
    private func formatLogText() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let time = formatter.string(from: log.timestamp)
        let beaconName = nameForBeacon(log.beaconID)
        let baseText = "\(time) [\(log.event)] \(beaconName)"
        
        // Truncate to 30 characters maximum
        if baseText.count > 30 {
            return String(baseText.prefix(27)) + "..."
        }
        return baseText
    }
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(colorForBeacon(log.beaconID))
                .frame(width: 10, height: 10)
            Text(formatLogText())
                .font(.caption)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(isHighlighted ? Color.yellow.opacity(0.4) : Color.clear)
        .cornerRadius(6)
        .animation(.easeInOut(duration: 0.5), value: isHighlighted)
    }
}

struct RSSILogSection: View {
    let rssiLogs: [(timestamp: Date, rssi: Int, beaconID: String)]
    let height: CGFloat
    @State private var highlightedTimestamps: Set<Date> = []
    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .top) {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 8) {
                        Color.clear.frame(height: 28)
                        ForEach(Array(rssiLogs.suffix(100).enumerated()), id: \.offset) { index, log in
                            RSSILogRow(
                                log: log,
                                isHighlighted: highlightedTimestamps.contains(log.timestamp)
                            )
                            .id("\(log.timestamp.timeIntervalSince1970)_\(log.rssi)_\(log.beaconID)_\(index)")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding([.horizontal, .bottom])
                .frame(height: height)
                .onChange(of: rssiLogs.count) {
                    let suffix = rssiLogs.suffix(100)
                    if let last = suffix.last {
                        let lastIndex = suffix.count - 1
                        let lastID = "\(last.timestamp.timeIntervalSince1970)_\(last.rssi)_\(last.beaconID)_\(lastIndex)"
                        proxy.scrollTo(lastID, anchor: .bottom)
                        highlightedTimestamps.insert(last.timestamp)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            highlightedTimestamps.remove(last.timestamp)
                        }
                    }
                }
                Text("RSSI Logs")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top, 4)
                    .background(Color(.systemBackground).opacity(0.95))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .zIndex(1)
            }
        }
    }
}

struct RSSILogRow: View {
    let log: (timestamp: Date, rssi: Int, beaconID: String)
    let isHighlighted: Bool
    
    private func formatLogText() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let time = formatter.string(from: log.timestamp)
        let beaconName = nameForBeacon(log.beaconID)
        let baseText = "\(time) \(log.rssi)dB \(beaconName)"
        
        // Truncate to 30 characters maximum
        if baseText.count > 30 {
            return String(baseText.prefix(27)) + "..."
        }
        return baseText
    }
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(colorForBeacon(log.beaconID))
                .frame(width: 10, height: 10)
            Text(formatLogText())
                .font(.caption2)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(isHighlighted ? Color.yellow.opacity(0.4) : Color.clear)
        .cornerRadius(6)
        .animation(.easeInOut(duration: 0.5), value: isHighlighted)
    }
}

struct BeaconLegend: View {
    let beaconIDs: [String]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(beaconIDs.sorted(), id: \.self) { beaconID in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(colorForBeacon(beaconID))
                            .frame(width: 12, height: 12)
                        Text(nameForBeacon(beaconID))
                            .font(.caption2)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
    }
}

#if canImport(Charts)
struct RSSITimeWindowChartLive: View {
    let liveRSSILogs: [(timestamp: Date, rssi: Int, beaconID: String)]
    let eventLogs: [(timestamp: Date, event: String, beaconID: String)]
    let chartTick: Int // Dummy prop to force redraw every second

    var body: some View {
        let now = Date()
        let window: TimeInterval = 120 // 2 minutes
        let start = now.addingTimeInterval(-window)
        let filteredLogs = liveRSSILogs.filter { $0.timestamp >= start }
        let filteredEvents = eventLogs.filter { $0.timestamp >= start }
        let beaconIDs = Array(Set(filteredLogs.map { $0.beaconID } + filteredEvents.map { $0.beaconID }))
        let timePoints = stride(from: 0, to: Int(window), by: 1).map { i in
            start.addingTimeInterval(TimeInterval(i))
        }
        
        Chart {
            ForEach(beaconIDs, id: \.self) { beaconID in
                let beaconLogs = filteredLogs.filter { $0.beaconID == beaconID }
                let logDict: [Double: Int] = Dictionary(grouping: beaconLogs, by: { $0.timestamp.timeIntervalSince1970.rounded() })
                    .mapValues { $0.last!.rssi }
                ForEach(Array(timePoints.enumerated()), id: \.offset) { entry in
                    let (_, t) = entry
                    if let rssi = logDict[t.timeIntervalSince1970.rounded()] {
                        PointMark(
                            x: .value("Time", t),
                            y: .value("RSSI", rssi)
                        )
                        .foregroundStyle(colorForBeacon(beaconID))
                    } else {
                        PointMark(
                            x: .value("Time", t),
                            y: .value("RSSI", -100)
                        )
                        .foregroundStyle(.clear)
                    }
                }
            }
            // Entry/Exit/Lost event markers
            ForEach(Array(filteredEvents.enumerated()), id: \.offset) { index, event in
                let beaconColor = colorForBeacon(event.beaconID)
                if event.event == "Enter" {
                    PointMark(
                        x: .value("Time", event.timestamp),
                        y: .value("RSSI", -80)
                    )
                    .symbol(.triangle)
                    .symbolSize(300)
                    .foregroundStyle(beaconColor)
                    .opacity(1.0)
                } else if event.event == "Exit" {
                    PointMark(
                        x: .value("Time", event.timestamp),
                        y: .value("RSSI", -80)
                    )
                    .symbol(.diamond)
                    .symbolSize(300)
                    .foregroundStyle(beaconColor)
                } else if event.event == "Lost" {
                    PointMark(
                        x: .value("Time", event.timestamp),
                        y: .value("RSSI", -80)
                    )
                    .symbol(.cross)
                    .symbolSize(300)
                    .foregroundStyle(beaconColor)
                }
            }
        }
        .chartYScale(domain: -120 ... -30)
        .chartXAxis {
            AxisMarks(values: .stride(by: 30)) { value in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour().minute().second(), centered: true)
            }
        }
        .padding()
    }
}
#endif

#if !canImport(Charts)
struct SimpleRSSIGraphLive: View {
    let liveRSSILogs: [(timestamp: Date, rssi: Int, beaconID: String)]
    let chartTick: Int // Dummy prop to force redraw every second
    var body: some View {
        GeometryReader { geo in
            let now = Date()
            let window: TimeInterval = 120
            let start = now.addingTimeInterval(-window)
            let filteredLogs = liveRSSILogs.filter { $0.timestamp >= start }
            let timePoints = stride(from: 0, to: Int(window), by: 1).map { i in
                start.addingTimeInterval(TimeInterval(i))
            }
            let logDict = Dictionary(grouping: filteredLogs, by: { $0.timestamp.timeIntervalSince1970.rounded() })
                .mapValues { $0.last!.rssi }
            let points = timePoints.enumerated().map { (i, t) in
                logDict[t.timeIntervalSince1970.rounded()].map { rssi in
                    CGPoint(
                        x: geo.size.width * CGFloat(i) / CGFloat(max(1, timePoints.count - 1)),
                        y: geo.size.height * (1 - CGFloat((Double(rssi) + 100) / 100))
                    )
                }
            }
            Path { path in
                var didMove = false
                for pt in points {
                    if let pt = pt {
                        if !didMove {
                            path.move(to: pt)
                            didMove = true
                        } else {
                            path.addLine(to: pt)
                        }
                    } else {
                        didMove = false // break the line
                    }
                }
            }
            .stroke(Color.purple, lineWidth: 2)
        }
        .padding([.horizontal, .bottom])
    }
}
#endif 
