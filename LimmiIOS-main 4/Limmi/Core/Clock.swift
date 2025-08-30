//
//  Clock.swift
//  Limmi
//
//  Purpose: Time abstraction for testable time-based rule evaluation
//  Dependencies: Foundation
//  Related: BlockingEngine.swift, TimeRule evaluation, Unit testing infrastructure
//

import Foundation

/// Protocol abstraction for time operations enabling testable time-based logic.
///
/// This protocol provides a clean abstraction for time operations, crucial for:
/// - **Testability**: Mock time progression in unit tests
/// - **Time Zone Handling**: Consistent time interpretation across app
/// - **Rule Evaluation**: Reliable time-based blocking rule evaluation
///
/// ## Usage in Blocking Engine
/// Time is used for evaluating time-based blocking rules:
/// - Daily time windows (9 AM - 5 PM)
/// - Weekly schedules (weekdays only)
/// - Monthly patterns (first Monday of month)
/// - Custom intervals (every 3 days)
///
/// ## Implementation Strategy
/// - **Production**: SystemClock using actual system time
/// - **Testing**: TestClock with controllable time progression
/// - **Future**: Could support timezone-specific clocks
///
/// ## Testability Benefits
/// ```swift
/// let testClock = TestClock()
/// testClock.set(to: specificDate)
/// // Test time-based rule evaluation
/// testClock.advance(by: .hours(2))
/// // Test rule transitions
/// ```
///
/// - Since: 1.0
protocol Clock {
    /// Returns the current date and time for rule evaluation.
    /// 
    /// This is the primary method used throughout the app for time-based
    /// rule evaluation. Production returns system time, tests can control this.
    /// 
    /// - Returns: Current date and time according to this clock
    func now() -> Date
}

/// Production implementation using actual system time.
///
/// This implementation provides real system time for production use.
/// Simple and efficient with no overhead or state management.
///
/// ## Thread Safety
/// Date() is thread-safe and can be called from any queue.
///
/// - Since: 1.0
struct SystemClock: Clock {
    func now() -> Date {
        Date()
    }
}

/// Test implementation of Clock with controllable time
final class TestClock: Clock {
    private var currentTime: Date
    
    init(currentTime: Date = Date()) {
        self.currentTime = currentTime
    }
    
    func now() -> Date {
        currentTime
    }
    
    /// Advances the clock by the specified time interval
    func advance(by interval: TimeInterval) {
        currentTime = currentTime.addingTimeInterval(interval)
    }
    
    /// Sets the clock to a specific time
    func set(to date: Date) {
        currentTime = date
    }
}

/// Extension for convenient time operations
extension Clock {
    /// Returns true if the current time is within the specified time range
    func isNow(between startTime: Date, and endTime: Date) -> Bool {
        let current = now()
        return current >= startTime && current <= endTime
    }
    
    /// Returns the current time components
    func currentTimeComponents() -> DateComponents {
        Calendar.current.dateComponents([.hour, .minute, .second, .weekday, .day, .month, .year], from: now())
    }
}

// MARK: - Shared Instance

extension Clock {
    /// Shared system clock instance for production use
    static var system: Clock { SystemClock() }
}