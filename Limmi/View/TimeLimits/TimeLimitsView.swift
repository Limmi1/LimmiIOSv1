import SwiftUI
import FamilyControls
import ManagedSettings

struct TimeLimitsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var timeLimitManager = TimeLimitManager.shared
    @State private var showingAddTimeLimit = false
    @State private var editingTimeLimit: DailyTimeLimit?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 16) {
                    HStack {
                        Spacer()
                        
                        // Status indicator
                        HStack(spacing: 8) {
                            Circle()
                                .fill(timeLimitManager.dailyTimeLimits.isEmpty ? .gray : .green)
                                .frame(width: 8, height: 8)
                            
                            Text(timeLimitManager.dailyTimeLimits.isEmpty ? "No Limits Set" : "\(timeLimitManager.dailyTimeLimits.count) Active")
                                .font(DesignSystem.captionText)
                                .foregroundColor(DesignSystem.secondaryBlue)
                        }
                    }
                    .padding(.horizontal, DesignSystem.spacingL)
                    .padding(.top, DesignSystem.spacingS)
                }
                
                // Add Time Limit Section
                VStack(spacing: DesignSystem.spacingL) {
                    // Section Header with Divider
                    VStack(spacing: DesignSystem.spacingS) {
                        HStack {
                            Text("Set Daily Limits")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(DesignSystem.pureBlack)
                            Spacer()
                        }
                        
                        // Subtle divider line
                        Rectangle()
                            .fill(DesignSystem.secondaryBlue.opacity(0.2))
                            .frame(height: 1)
                    }
                    .padding(.horizontal, DesignSystem.spacingL)
                    
                    // Add Time Limit Button (Matching Allowed/Blocked Space Style)
                    Button(action: {
                        showingAddTimeLimit = true
                    }) {
                        VStack(spacing: DesignSystem.spacingS) {
                            Image("timerlogo")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 64, height: 64)
                            
                            Text("Add Daily Limit")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(DesignSystem.secondaryBlue)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)
                        .background(DesignSystem.pureWhite)
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                                .stroke(DesignSystem.secondaryBlue, lineWidth: 2)
                        )
                        .cornerRadius(DesignSystem.cornerRadius)
                        .shadow(
                            color: DesignSystem.subtleShadow.color,
                            radius: DesignSystem.subtleShadow.radius,
                            x: DesignSystem.subtleShadow.x,
                            y: DesignSystem.subtleShadow.y
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal, DesignSystem.spacingL)
                }
                .padding(.vertical, DesignSystem.spacingM)
                
                // Spacing between sections
                Spacer()
                    .frame(height: 12)
                
                // Active Time Limits Section
                VStack(spacing: DesignSystem.spacingL) {
                    // Section Header with Divider
                    VStack(spacing: DesignSystem.spacingS) {
                        HStack {
                            Text("Active Time Limits")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(DesignSystem.pureBlack)
                            Spacer()
                        }
                        
                        // Subtle divider line
                        Rectangle()
                            .fill(DesignSystem.secondaryBlue.opacity(0.2))
                            .frame(height: 1)
                    }
                    .padding(.horizontal, DesignSystem.spacingL)
                    
                    // Time Limits Content
                    ScrollView {
                        VStack(spacing: DesignSystem.spacingL) {
                            if timeLimitManager.dailyTimeLimits.isEmpty {
                                // Empty State
                                VStack(spacing: DesignSystem.spacingXL) {
                                    Image(systemName: "clock")
                                        .font(.system(size: 64))
                                        .foregroundColor(DesignSystem.secondaryBlue.opacity(0.6))
                                    
                                    VStack(spacing: DesignSystem.spacingS) {
                                        Text("No Time Limits Set")
                                            .font(DesignSystem.headingMedium)
                                            .fontWeight(.semibold)
                                            .foregroundColor(DesignSystem.pureBlack)
                                        
                                        Text("Set daily time limits for apps to control usage with Limmi's shield blocking")
                                            .font(DesignSystem.bodyText)
                                            .foregroundColor(DesignSystem.secondaryBlue)
                                            .multilineTextAlignment(.center)
                                            .lineLimit(3)
                                    }
                                }
                                .padding(.horizontal, DesignSystem.spacingXXL)
                                .padding(.vertical, DesignSystem.spacingXXL)
                            } else {
                                // Time Limits List
                                LazyVStack(spacing: DesignSystem.spacingM) {
                                    ForEach(timeLimitManager.dailyTimeLimits) { timeLimit in
                                        Button(action: {
                                            editingTimeLimit = timeLimit
                                        }) {
                                            TimeLimitCard(timeLimit: timeLimit, timeLimitManager: timeLimitManager)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                                .padding(.horizontal, DesignSystem.spacingL)
                                .padding(.top, DesignSystem.spacingS)
                            }
                        }
                        
                        Spacer(minLength: DesignSystem.spacingXL)
                    }
                }
                .padding(.vertical, DesignSystem.spacingL)
                .background(DesignSystem.subtleYellowBackground)
            }
            .background(DesignSystem.subtleYellowBackground)
            .navigationTitle("Time Limits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(DesignSystem.secondaryBlue)
                }
            }
        }
        .sheet(isPresented: $showingAddTimeLimit) {
            AddTimeLimitView { newTimeLimit in
                timeLimitManager.addTimeLimit(newTimeLimit)
            }
        }
        .sheet(item: $editingTimeLimit) { tl in
            EditTimeLimitView(
                timeLimit: tl,
                onSave: { updated in
                    timeLimitManager.updateTimeLimit(updated)
                }
            )
        }
    }
}



// MARK: - Time Limit Card
struct TimeLimitCard: View {
    let timeLimit: DailyTimeLimit
    let timeLimitManager: TimeLimitManager
    @State private var showingDeleteAlert = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingM) {
            // Time Limit Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "app.fill")
                        .font(.system(size: 20))
                        .foregroundColor(DesignSystem.secondaryBlue)
                    
                    Text(timeLimit.appName)
                        .font(DesignSystem.headingSmall)
                        .fontWeight(.semibold)
                        .foregroundColor(DesignSystem.pureBlack)
                }
                
                Spacer()
                
                // Time Limit Badge
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DesignSystem.primaryYellow)
                    
                    Text("\(timeLimit.dailyLimitMinutes) min/day")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DesignSystem.primaryYellow)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(DesignSystem.primaryYellow.opacity(0.1))
                )
            }
            
            // Status Chips
            HStack(spacing: DesignSystem.spacingS) {
                // Active Status
                HStack(spacing: DesignSystem.spacingXS) {
                    Image(systemName: timeLimit.isActive ? "checkmark.circle.fill" : "pause.circle.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(timeLimit.isActive ? .green : .gray)
                    
                    Text(timeLimit.isActive ? "Active" : "Paused")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(timeLimit.isActive ? .green : .gray)
                }
                .padding(.horizontal, DesignSystem.spacingS)
                .padding(.vertical, 6)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.chipCornerRadius)
                        .fill(timeLimit.isActive ? .green.opacity(0.1) : .gray.opacity(0.1))
                )
                
                // Reset Time
                Text("Resets at \(formatTime(timeLimit.resetTime))")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DesignSystem.secondaryBlue)
                    .padding(.horizontal, DesignSystem.spacingS)
                    .padding(.vertical, 6)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.chipCornerRadius)
                            .stroke(DesignSystem.secondaryBlue.opacity(0.3), lineWidth: 1)
                    )
            }
            
            // Usage Progress (Mock data for now)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Today's Usage")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DesignSystem.secondaryBlue)
                    Spacer()
                    Text("15 min / \(timeLimit.dailyLimitMinutes) min")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DesignSystem.secondaryBlue)
                }
                
                ProgressView(value: 0.3) // Mock 30% usage
                    .progressViewStyle(LinearProgressViewStyle(tint: DesignSystem.primaryYellow))
                    .scaleEffect(x: 1, y: 0.5, anchor: .center)
            }
        }
        .padding(DesignSystem.cardPadding)
        .background(DesignSystem.pureWhite)
        .cornerRadius(DesignSystem.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                .stroke(DesignSystem.secondaryBlue.opacity(0.3), lineWidth: 1)
        )
        .shadow(
            color: DesignSystem.subtleShadow.color,
            radius: DesignSystem.subtleShadow.radius,
            x: DesignSystem.subtleShadow.x,
            y: DesignSystem.subtleShadow.y
        )
        .contextMenu {
            Button(role: .destructive) {
                showingDeleteAlert = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .alert("Delete Time Limit", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                timeLimitManager.deleteTimeLimit(id: timeLimit.id)
            }
        } message: {
            Text("Are you sure you want to delete the time limit for '\(timeLimit.appName)'?")
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Edit Time Limit View
struct EditTimeLimitView: View {
    @Environment(\.dismiss) private var dismiss
    let timeLimit: DailyTimeLimit
    let onSave: (DailyTimeLimit) -> Void
    
    @State private var selectedApp: FamilyActivitySelection = FamilyActivitySelection()
    @State private var selectedTimeLimit: Int
    @State private var showingAppPicker = false
    
    init(timeLimit: DailyTimeLimit, onSave: @escaping (DailyTimeLimit) -> Void) {
        self.timeLimit = timeLimit
        self.onSave = onSave
        _selectedTimeLimit = State(initialValue: timeLimit.dailyLimitMinutes)
    }
    
    // Time limit options in 15-minute increments up to 24 hours
    private let timeLimitOptions: [Int] = {
        var options: [Int] = []
        for hours in 0..<24 {
            for minutes in stride(from: 0, to: 60, by: 15) {
                let totalMinutes = hours * 60 + minutes
                if totalMinutes > 0 {
                    options.append(totalMinutes)
                }
            }
        }
        return options
    }()
    
    private var formattedTimeLimit: String {
        let hours = selectedTimeLimit / 60
        let minutes = selectedTimeLimit % 60
        if hours > 0 && minutes > 0 { return "\(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(minutes)m"
    }
    
    private func formatTimeLimit(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours > 0 && remainingMinutes > 0 { return "\(hours)h \(remainingMinutes)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(remainingMinutes)m"
    }
    
    private var isFormValid: Bool {
        // Allow save if either existing selection name is present or new selection chosen
        !selectedApp.applicationTokens.isEmpty || !timeLimit.appName.isEmpty
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header status
                VStack(spacing: 16) {
                    HStack {
                        Spacer()
                        HStack(spacing: 8) {
                            Circle()
                                .fill(isFormValid ? .green : .gray)
                                .frame(width: 8, height: 8)
                            Text(isFormValid ? "Ready to Save" : "Select App & Time")
                                .font(DesignSystem.captionText)
                                .foregroundColor(DesignSystem.secondaryBlue)
                        }
                    }
                    .padding(.horizontal, DesignSystem.spacingL)
                    .padding(.top, DesignSystem.spacingS)
                }
                
                // App selection
                VStack(spacing: DesignSystem.spacingL) {
                    sectionHeader(title: "Select App")
                    Button(action: { showingAppPicker = true }) {
                        HStack(spacing: DesignSystem.spacingM) {
                            Image(systemName: "app.fill")
                                .font(.system(size: 24))
                                .foregroundColor(DesignSystem.secondaryBlue)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                if selectedApp.applicationTokens.isEmpty {
                                    Text(timeLimit.appName.isEmpty ? "Choose App(s)" : timeLimit.appName)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(DesignSystem.pureBlack)
                                } else {
                                    Text("\(selectedApp.applicationTokens.count) App(s) Selected")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(DesignSystem.pureBlack)
                                }
                                Text("Tap to change")
                                    .font(.system(size: 12))
                                    .foregroundColor(DesignSystem.secondaryBlue.opacity(0.6))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(DesignSystem.secondaryBlue)
                        }
                        .padding(DesignSystem.cardPadding)
                        .background(DesignSystem.pureWhite)
                        .cornerRadius(DesignSystem.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                                .stroke(DesignSystem.secondaryBlue.opacity(0.3), lineWidth: 1)
                        )
                        .shadow(
                            color: DesignSystem.subtleShadow.color,
                            radius: DesignSystem.subtleShadow.radius,
                            x: DesignSystem.subtleShadow.x,
                            y: DesignSystem.subtleShadow.y
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal, DesignSystem.spacingL)
                }
                .padding(.vertical, DesignSystem.spacingM)
                
                Spacer().frame(height: 12)
                
                // Time selection
                VStack(spacing: DesignSystem.spacingL) {
                    sectionHeader(title: "Set Daily Limit")
                    VStack(spacing: DesignSystem.spacingM) {
                        HStack {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 20))
                                .foregroundColor(DesignSystem.primaryYellow)
                            Text("Daily Limit: \(formattedTimeLimit)")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(DesignSystem.pureBlack)
                            Spacer()
                        }
                        .padding(DesignSystem.cardPadding)
                        .background(DesignSystem.pureWhite)
                        .cornerRadius(DesignSystem.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                                .stroke(DesignSystem.primaryYellow, lineWidth: 2)
                        )
                        .shadow(
                            color: DesignSystem.subtleShadow.color,
                            radius: DesignSystem.subtleShadow.radius,
                            x: DesignSystem.subtleShadow.x,
                            y: DesignSystem.subtleShadow.y
                        )
                        
                        Picker("Time Limit", selection: $selectedTimeLimit) {
                            ForEach(timeLimitOptions, id: \.self) { minutes in
                                Text(formatTimeLimit(minutes)).tag(minutes)
                            }
                        }
                        .pickerStyle(WheelPickerStyle())
                        .frame(height: 200)
                        .background(DesignSystem.pureWhite)
                        .cornerRadius(DesignSystem.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                                .stroke(DesignSystem.secondaryBlue.opacity(0.3), lineWidth: 1)
                        )
                        .padding(.horizontal, DesignSystem.spacingL)
                        
                        HStack(spacing: DesignSystem.spacingS) {
                            ForEach([15, 30, 60, 120], id: \.self) { minutes in
                                Button(formatTimeLimit(minutes)) { selectedTimeLimit = minutes }
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(selectedTimeLimit == minutes ? DesignSystem.pureWhite : DesignSystem.secondaryBlue)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(selectedTimeLimit == minutes ? DesignSystem.secondaryBlue : DesignSystem.secondaryBlue.opacity(0.1))
                                    )
                            }
                        }
                        .padding(.horizontal, DesignSystem.spacingL)
                    }
                }
                .padding(.vertical, DesignSystem.spacingL)
                .background(DesignSystem.subtleYellowBackground)
                
                Spacer()
            }
            .background(DesignSystem.subtleYellowBackground)
            .navigationTitle("Edit Time Limit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(DesignSystem.secondaryBlue)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        var updated = DailyTimeLimit(
                            appName: selectedApp.applicationTokens.isEmpty ? timeLimit.appName : (selectedApp.applicationTokens.count == 1 ? "1 App Blocked" : "\(selectedApp.applicationTokens.count) Apps Blocked"),
                            appTokenId: selectedApp.applicationTokens.isEmpty ? timeLimit.appTokenId : "family_activity_selection",
                            dailyLimitMinutes: selectedTimeLimit,
                            resetTime: timeLimit.resetTime,
                            isActive: timeLimit.isActive,
                            warningThresholdMinutes: timeLimit.warningThresholdMinutes,
                            gracePeriodMinutes: timeLimit.gracePeriodMinutes
                        )
                        updated.id = timeLimit.id
                        onSave(updated)
                        dismiss()
                    }
                    .foregroundColor(isFormValid ? DesignSystem.primaryYellow : DesignSystem.secondaryBlue.opacity(0.5))
                    .disabled(!isFormValid)
                }
            }
        }
        .familyActivityPicker(isPresented: $showingAppPicker, selection: $selectedApp)
    }
    
    private func sectionHeader(title: String) -> some View {
        VStack(spacing: DesignSystem.spacingS) {
            HStack {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(DesignSystem.pureBlack)
                Spacer()
            }
            Rectangle()
                .fill(DesignSystem.secondaryBlue.opacity(0.2))
                .frame(height: 1)
        }
        .padding(.horizontal, DesignSystem.spacingL)
    }
}

// MARK: - Add Time Limit View
struct AddTimeLimitView: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (DailyTimeLimit) -> Void
    
    @State private var selectedApp: FamilyActivitySelection = FamilyActivitySelection()
    @State private var selectedTimeLimit: Int = 30 // Default to 30 minutes
    @State private var showingAppPicker = false
    @State private var showingTimePicker = false
    
    // Time limit options in 15-minute increments up to 24 hours
    private let timeLimitOptions: [Int] = {
        var options: [Int] = []
        for hours in 0..<24 {
            for minutes in stride(from: 0, to: 60, by: 15) {
                let totalMinutes = hours * 60 + minutes
                if totalMinutes > 0 { // Skip 0 minutes
                    options.append(totalMinutes)
                }
            }
        }
        return options
    }()
    
    private var formattedTimeLimit: String {
        let hours = selectedTimeLimit / 60
        let minutes = selectedTimeLimit % 60
        
        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(minutes)m"
        }
    }
    
    private func formatTimeLimit(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        
        if hours > 0 && remainingMinutes > 0 {
            return "\(hours)h \(remainingMinutes)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(remainingMinutes)m"
        }
    }
    
    private var isFormValid: Bool {
        !selectedApp.applicationTokens.isEmpty && selectedTimeLimit > 0
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerSection
                appSelectionSection
                Spacer().frame(height: 12)
                timeLimitSelectionSection
                Spacer()
            }
            .background(DesignSystem.subtleYellowBackground)
            .navigationTitle("Add Time Limit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(DesignSystem.secondaryBlue)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    saveButton
                }
            }
        }
        .familyActivityPicker(isPresented: $showingAppPicker, selection: $selectedApp)
    }
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            HStack {
                Spacer()
                
                HStack(spacing: 8) {
                    Circle()
                        .fill(isFormValid ? .green : .gray)
                        .frame(width: 8, height: 8)
                    
                    Text(isFormValid ? "Ready to Save" : "Select App & Time")
                        .font(DesignSystem.captionText)
                        .foregroundColor(DesignSystem.secondaryBlue)
                }
            }
            .padding(.horizontal, DesignSystem.spacingL)
            .padding(.top, DesignSystem.spacingS)
        }
    }
    
    private var appSelectionSection: some View {
        VStack(spacing: DesignSystem.spacingL) {
            sectionHeader(title: "Select App")
            
            Button(action: {
                showingAppPicker = true
            }) {
                appSelectionButton
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, DesignSystem.spacingL)
        }
        .padding(.vertical, DesignSystem.spacingM)
    }
    
    private var appSelectionButton: some View {
        HStack(spacing: DesignSystem.spacingM) {
            Image(systemName: "app.fill")
                .font(.system(size: 24))
                .foregroundColor(DesignSystem.secondaryBlue)
            
            VStack(alignment: .leading, spacing: 4) {
                if selectedApp.applicationTokens.isEmpty {
                    Text("Choose App(s)")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(DesignSystem.secondaryBlue.opacity(0.6))
                } else {
                    Text("\(selectedApp.applicationTokens.count) App(s) Selected")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(DesignSystem.pureBlack)
                }
                
                if !selectedApp.applicationTokens.isEmpty {
                    Text("Tap to change")
                        .font(.system(size: 12))
                        .foregroundColor(DesignSystem.secondaryBlue.opacity(0.6))
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(DesignSystem.secondaryBlue)
        }
        .padding(DesignSystem.cardPadding)
        .background(DesignSystem.pureWhite)
        .cornerRadius(DesignSystem.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                .stroke(selectedApp.applicationTokens.isEmpty ? DesignSystem.secondaryBlue.opacity(0.3) : DesignSystem.primaryYellow, lineWidth: selectedApp.applicationTokens.isEmpty ? 1 : 2)
        )
        .shadow(
            color: DesignSystem.subtleShadow.color,
            radius: DesignSystem.subtleShadow.radius,
            x: DesignSystem.subtleShadow.x,
            y: DesignSystem.subtleShadow.y
        )
    }
    
    private var timeLimitSelectionSection: some View {
        VStack(spacing: DesignSystem.spacingL) {
            sectionHeader(title: "Set Daily Limit")
            
            VStack(spacing: DesignSystem.spacingM) {
                currentSelectionDisplay
                timeLimitPicker
            }
        }
        .padding(.vertical, DesignSystem.spacingL)
        .background(DesignSystem.subtleYellowBackground)
    }
    
    private var currentSelectionDisplay: some View {
        HStack {
            Image(systemName: "clock.fill")
                .font(.system(size: 20))
                .foregroundColor(DesignSystem.primaryYellow)
            
            Text("Daily Limit: \(formattedTimeLimit)")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(DesignSystem.pureBlack)
            
            Spacer()
        }
        .padding(DesignSystem.cardPadding)
        .background(DesignSystem.pureWhite)
        .cornerRadius(DesignSystem.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                .stroke(DesignSystem.primaryYellow, lineWidth: 2)
        )
        .shadow(
            color: DesignSystem.subtleShadow.color,
            radius: DesignSystem.subtleShadow.radius,
            x: DesignSystem.subtleShadow.x,
            y: DesignSystem.subtleShadow.y
        )
    }
    
    private var timeLimitPicker: some View {
        VStack(spacing: DesignSystem.spacingM) {
            // Wheel Picker
            Picker("Time Limit", selection: $selectedTimeLimit) {
                ForEach(timeLimitOptions, id: \.self) { minutes in
                    Text(formatTimeLimit(minutes))
                        .tag(minutes)
                }
            }
            .pickerStyle(WheelPickerStyle())
            .frame(height: 200)
            .background(DesignSystem.pureWhite)
            .cornerRadius(DesignSystem.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                    .stroke(DesignSystem.secondaryBlue.opacity(0.3), lineWidth: 1)
            )
            .padding(.horizontal, DesignSystem.spacingL)
            
            // Quick Selection Buttons
            HStack(spacing: DesignSystem.spacingS) {
                ForEach([15, 30, 60, 120], id: \.self) { minutes in
                    Button(formatTimeLimit(minutes)) {
                        selectedTimeLimit = minutes
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(selectedTimeLimit == minutes ? DesignSystem.pureWhite : DesignSystem.secondaryBlue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selectedTimeLimit == minutes ? DesignSystem.secondaryBlue : DesignSystem.secondaryBlue.opacity(0.1))
                    )
                }
            }
            .padding(.horizontal, DesignSystem.spacingL)
        }
    }
    
    private var saveButton: some View {
        Button("Save") {
            if !selectedApp.applicationTokens.isEmpty {
                let appCount = selectedApp.applicationTokens.count
                let appName = appCount == 1 ? "1 App Blocked" : "\(appCount) Apps Blocked"
                
                let timeLimit = DailyTimeLimit(
                    appName: appName,
                    appTokenId: "family_activity_selection", // Use a more descriptive ID
                    dailyLimitMinutes: selectedTimeLimit
                )
                onSave(timeLimit)
                dismiss()
            }
        }
        .foregroundColor(isFormValid ? DesignSystem.primaryYellow : DesignSystem.secondaryBlue.opacity(0.5))
        .disabled(!isFormValid)
    }
    
    private func sectionHeader(title: String) -> some View {
        VStack(spacing: DesignSystem.spacingS) {
            HStack {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(DesignSystem.pureBlack)
                Spacer()
            }
            
            Rectangle()
                .fill(DesignSystem.secondaryBlue.opacity(0.2))
                .frame(height: 1)
        }
        .padding(.horizontal, DesignSystem.spacingL)
    }
}

// MARK: - Time Limit Option View
struct TimeLimitOptionView: View {
    let minutes: Int
    let isSelected: Bool
    let onTap: () -> Void
    
    private var formattedTime: String {
        let hours = minutes / 60
        let mins = minutes % 60
        
        if hours > 0 && mins > 0 {
            return "\(hours)h \(mins)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(mins)m"
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            Text(formattedTime)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isSelected ? DesignSystem.pureWhite : DesignSystem.secondaryBlue)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? DesignSystem.primaryYellow : DesignSystem.pureWhite)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? DesignSystem.primaryYellow : DesignSystem.secondaryBlue.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    TimeLimitsView()
}