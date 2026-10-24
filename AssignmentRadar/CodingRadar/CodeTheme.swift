//
//  CodeTheme.swift
//  AssignmentRadar
//
//  Defines the dedicated, always-dark terminal coder theme for CodingRadar.
//  Features clean typography, monospaced titles, 14pt corner radii,
//  and hairline borders instead of heavy shadows.
//

import SwiftUI

enum CodeTheme {
    // Terminal palette
    static let background = Color(hex: 0x0A0D0B)
    static let card = Color(hex: 0x111712)
    static let border = Color(hex: 0x1E2A21)
    static let primary = Color(hex: 0x2EE66B)       // Terminal green
    static let alert = Color(hex: 0xFF4D4F)         // Urgency red
    static let text = Color(hex: 0xD8F5E0)          // Bright mint-white
    static let secondaryText = Color(hex: 0x6F8F78) // Muted sage green

    // Styling constants
    static let cornerRadius: CGFloat = 14.0
    static let padding: CGFloat = 16.0
    static let spacing: CGFloat = 16.0

    // Card modifier with hairline border
    struct CardModifier: ViewModifier {
        func body(content: Content) -> some View {
            content
                .background(CodeTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: CodeTheme.cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: CodeTheme.cornerRadius, style: .continuous)
                        .stroke(CodeTheme.border, lineWidth: 1)
                )
        }
    }
}

extension View {
    /// Applies CodingRadar card styling: dark background with a subtle 1pt hairline border.
    func codeCardStyle() -> some View {
        modifier(CodeTheme.CardModifier())
    }
}
