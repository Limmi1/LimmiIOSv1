//
//  LegalModal.swift
//  Limmi
//
//  Created by Assistant on 2025-01-27.
//

import SwiftUI

struct LegalModal: View {
    let title: String
    let content: String
    let onAccept: () -> Void
    let onCancel: () -> Void
    let requiresAcceptance: Bool
    let onScrollComplete: (() -> Void)?
    
    @State private var scrollOffset: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var scrollViewHeight: CGFloat = 0
    
    private var scrollProgress: Double {
        guard contentHeight > scrollViewHeight && contentHeight > 0 else { return 1.0 }
        let progress = min(max(scrollOffset / (contentHeight - scrollViewHeight), 0), 1)
        return progress
    }
    
    private var isAcceptEnabled: Bool {
        if !requiresAcceptance {
            return true
        }
        // For Beta Agreement, require 95% scroll to enable checkbox
        return scrollProgress >= 0.95
    }
    
    private var isScrollComplete: Bool {
        return scrollProgress >= 0.95
    }
    
    private var scrollProgressText: String {
        if !requiresAcceptance {
            return "Read to learn more"
        }
        
        if scrollProgress >= 0.95 {
            return "Ready to accept"
        } else if scrollProgress >= 0.75 {
            return "Almost there..."
        } else if scrollProgress >= 0.5 {
            return "Keep scrolling"
        } else if scrollProgress >= 0.25 {
            return "Scroll to read"
        } else {
            return "Start reading"
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text(title)
                        .font(DesignSystem.headingMedium)
                        .foregroundColor(DesignSystem.pureBlack)
                    
                    Spacer()
                    
                    Button("Cancel") {
                        onCancel()
                    }
                    .font(DesignSystem.bodyText)
                    .foregroundColor(DesignSystem.secondaryBlue)
                }
                .padding(DesignSystem.spacingL)
                .background(DesignSystem.pureWhite)
                
                Divider()
                    .background(DesignSystem.secondaryBlue.opacity(0.3))
                
                // Content
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: DesignSystem.spacingL) {
                            Text(content)
                                .font(DesignSystem.bodyText)
                                .foregroundColor(DesignSystem.pureBlack)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(DesignSystem.spacingL)
                        .background(
                            GeometryReader { geometry in
                                Color.clear
                                    .onAppear {
                                        contentHeight = geometry.size.height
                                    }
                                    .onChange(of: geometry.size.height) { _, newHeight in
                                        contentHeight = newHeight
                                    }
                            }
                        )
                    }
                    .scrollIndicators(.hidden)
                    .coordinateSpace(name: "scroll")
                    .background(
                        GeometryReader { geometry in
                            Color.clear
                                .onAppear {
                                    scrollViewHeight = geometry.size.height
                                }
                                .onChange(of: geometry.size.height) { _, newHeight in
                                    scrollViewHeight = newHeight
                                }
                        }
                    )
                    .onScrollOffsetChange { offset in
                        scrollOffset = offset
                    }
                }
                
                Divider()
                    .background(DesignSystem.secondaryBlue.opacity(0.3))
                
                // Footer
                HStack(spacing: DesignSystem.spacingL) {
                    // Progress indicator
                    HStack(spacing: DesignSystem.spacingS) {
                        Text(scrollProgressText)
                            .font(DesignSystem.captionText)
                            .foregroundColor(DesignSystem.secondaryBlue.opacity(0.6))
                        
                        ProgressView(value: scrollProgress)
                            .progressViewStyle(LinearProgressViewStyle(tint: DesignSystem.primaryYellow))
                            .frame(width: 100)
                    }
                    
                    Spacer()
                    
                    Button("Close") {
                        onAccept()
                    }
                    .font(DesignSystem.bodyText)
                    .fontWeight(.semibold)
                    .foregroundColor(DesignSystem.pureBlack)
                    .padding(.horizontal, DesignSystem.spacingL)
                    .padding(.vertical, DesignSystem.spacingM)
                    .background(DesignSystem.primaryYellow)
                    .cornerRadius(DesignSystem.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                            .stroke(DesignSystem.secondaryBlue, lineWidth: DesignSystem.borderWidth)
                    )
                }
                .padding(DesignSystem.spacingL)
                .background(DesignSystem.pureWhite)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onChange(of: isScrollComplete) { _, newValue in
            if newValue && requiresAcceptance {
                onScrollComplete?()
            }
        }
    }
}

// MARK: - Scroll Offset Tracking

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension View {
    func onScrollOffsetChange(action: @escaping (CGFloat) -> Void) -> some View {
        self.background(
            GeometryReader { geometry in
                Color.clear
                    .preference(
                        key: ScrollOffsetPreferenceKey.self,
                        value: -geometry.frame(in: .named("scroll")).minY
                    )
            }
        )
        .onPreferenceChange(ScrollOffsetPreferenceKey.self, perform: action)
    }
}

#Preview {
    LegalModal(
        title: "Beta Tester Agreement (Private Evaluation)",
        content: """
        Beta Tester Agreement
        
        This is a sample agreement content for preview purposes.
        
        Section 1
        Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.
        
        Section 2
        Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.
        
        Section 3
        Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur.
        
        Section 4
        Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.
        
        Section 5
        Sed ut perspiciatis unde omnis iste natus error sit voluptatem accusantium doloremque laudantium.
        
        Section 6
        Totam rem aperiam, eaque ipsa quae ab illo inventore veritatis et quasi architecto beatae vitae dicta sunt.
        
        Section 7
        Explicabo nemo enim ipsam voluptatem quia voluptas sit aspernatur aut odit aut fugit.
        
        Section 8
        Sed quia consequuntur magni dolores eos qui ratione voluptatem sequi nesciunt.
        
        Section 9
        Neque porro quisquam est, qui dolorem ipsum quia dolor sit amet, consectetur, adipisci velit.
        
        Section 10
        Sed quia non numquam eius modi tempora incidunt ut labore et dolore magnam aliquam quaerat voluptatem.
        """,
        onAccept: {},
        onCancel: {},
        requiresAcceptance: true,
        onScrollComplete: nil
    )
}
