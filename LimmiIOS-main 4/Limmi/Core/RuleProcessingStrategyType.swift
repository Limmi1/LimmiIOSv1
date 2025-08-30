//
//  RuleProcessingStrategyType.swift
//  Limmi
//
//  Purpose: Type-safe enumeration and factory for rule processing strategies
//  Dependencies: Foundation, RuleProcessingStrategy
//  Related: RuleProcessingStrategy.swift, AppSettings.swift, BlockingEngine.swift
//

import Foundation

/// Enumeration of available rule processing strategies
///
/// This enum provides a type-safe way to represent and configure different
/// rule processing strategies in the app. Each strategy has different characteristics
/// optimized for specific use cases.
///
/// ## Strategy Types
/// - **Default**: Balanced RSSI-based processing with signal quality analysis
/// - **Region**: Background-compatible region monitoring only
/// - **Conservative**: High-accuracy RSSI processing with strict requirements
/// - **Responsive**: Fast RSSI processing with relaxed requirements
///
/// ## Usage
/// ```swift
/// let strategyType = RuleProcessingStrategyType.region
/// let strategy = strategyType.createStrategy()
/// ```
enum RuleProcessingStrategyType: String, CaseIterable, Identifiable {
    case defaultStrategy = "default"
    case region = "region"
    
    var id: String { rawValue }
    
    /// Human-readable display name for UI
    var displayName: String {
        switch self {
        case .defaultStrategy:
            return "Default"
        case .region:
            return "Region-Based"
        }
    }
    
    /// Detailed description of the strategy's characteristics
    var description: String {
        switch self {
        case .defaultStrategy:
            return "Experimental RSSI-based processing with signal quality analysis. Good for speed."
        case .region:
            return "Uses only region entry/exit events. Best for background operation reliability."
        }
    }
    
    /// Recommended use cases for the strategy
    /*var recommendedFor: [String] {
        switch self {
        case .defaultStrategy:
            return ["General use", "Mixed environments", "Balanced performance"]
        case .region:
            return ["Background operation", "Battery conservation", "Simple zones"]
        }
    }*/
    
    /// Creates an instance of the corresponding rule processing strategy
    /// - Returns: Configured strategy instance ready for use
    func createStrategy() -> RuleProcessingStrategy {
        switch self {
        case .defaultStrategy:
            return DefaultRuleProcessingStrategy(config: .responsive)
        case .region:
            return RegionBasedRuleProcessingStrategy(config: .responsive)
        }
    }
}

