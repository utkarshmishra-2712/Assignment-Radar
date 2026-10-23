//
//  Theme.swift
//  AssignmentRadar
//
//  Defines the application color palette, typography, and card styling.
//  Colors dynamically adapt between Light and Dark mode.
//

import SwiftUI
import UIKit

// MARK: - Color Hex Initializers
extension Color {
    /// Initializes a Color from a 24-bit integer hex code (e.g., 0xFF6B4A).
    init(hex: UInt, opacity: Double = 1.0) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}

extension UIColor {
    /// Initializes a UIColor from a 24-bit integer hex code (e.g., 0xFF6B4A).
    convenience init(hex: UInt, alpha: CGFloat = 1.0) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255.0
        let green = CGFloat((hex >> 8) & 0xFF) / 255.0
        let blue = CGFloat(hex & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}

// MARK: - App Theme Palette
enum Theme {
    // Dynamic background: #F6F9F8 (Light), #0F1F1E (Dark)
    static let background = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(hex: 0x0F1F1E)
            : UIColor(hex: 0xF6F9F8)
    })

    // Dynamic card surface: #FFFFFF (Light), #182B2A (Dark)
    static let card = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(hex: 0x182B2A)
            : UIColor(hex: 0xFFFFFF)
    })

    // Dynamic primary brand color: #2D6F6B (Light), #5FB49C (Dark)
    static let primary = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(hex: 0x5FB49C)
            : UIColor(hex: 0x2D6F6B)
    })

    // Accent coral: #FF6B4A (Same across Light and Dark, reserved strictly for urgency)
    static let accent = Color(hex: 0xFF6B4A)

    // Dynamic primary text: #12302F (Light), #EAF2F1 (Dark)
    static let text = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(hex: 0xEAF2F1)
            : UIColor(hex: 0x12302F)
    })

    // Dynamic secondary text: #6B7F7D (Light), #8FA6A4 (Dark)
    static let secondaryText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(hex: 0x8FA6A4)
            : UIColor(hex: 0x6B7F7D)
    })

    // MARK: - Scheme-Aware Color Resolvers
    static func backgroundColor(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x0F1F1E) : Color(hex: 0xF6F9F8)
    }

    static func cardColor(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x182B2A) : Color(hex: 0xFFFFFF)
    }

    static func primaryColor(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x5FB49C) : Color(hex: 0x2D6F6B)
    }

    static func textColor(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xEAF2F1) : Color(hex: 0x12302F)
    }

    static func secondaryTextColor(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x8FA6A4) : Color(hex: 0x6B7F7D)
    }

    // MARK: - Layout Constants
    static let cardCornerRadius: CGFloat = 16.0
    static let cardPadding: CGFloat = 16.0
    static let standardSpacing: CGFloat = 16.0
    static let softShadowRadius: CGFloat = 12.0
    static let softShadowY: CGFloat = 4.0
}

// MARK: - Semantic Color Extensions
extension Color {
    static let appBackground = Theme.background
    static let appCard = Theme.card
    static let appPrimary = Theme.primary
    static let appAccent = Theme.accent
    static let appText = Theme.text
    static let appSecondaryText = Theme.secondaryText
}

// MARK: - Card Styling Modifier
struct AppCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(Theme.cardColor(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
            .shadow(
                color: colorScheme == .dark
                    ? Color.black.opacity(0.35)
                    : Color(hex: 0x12302F, opacity: 0.06),
                radius: Theme.softShadowRadius,
                x: 0,
                y: Theme.softShadowY
            )
    }
}

// MARK: - Screen Background Modifier
struct AppBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(Theme.backgroundColor(for: colorScheme).ignoresSafeArea())
    }
}

// MARK: - View Helpers
extension View {
    /// Applies 16pt rounded corners, dynamic card background, and a soft shadow.
    func appCardStyle() -> some View {
        modifier(AppCardModifier())
    }

    /// Enforces the rounded font design.
    func appRoundedFont() -> some View {
        self.fontDesign(.rounded)
    }

    /// Fills the entire view hierarchy with the dynamic theme background.
    func appBackgroundStyle() -> some View {
        modifier(AppBackgroundModifier())
    }
}
