//
//  PlatformStyle.swift
//  AssignmentRadar
//
//  Defines signature brand identities, accessibility-tested accents,
//  and custom vector platform marks for CodingRadar contest cards.
//

import SwiftUI

// MARK: - Platform Brand Identity & Accents

struct PlatformStyle {
    let platform: CodingPlatform
    let displayName: String
    let shortLabel: String
    let accent: Color
    let softAccent: Color

    /// Contrast ratio against CodeTheme.card (0x111712, relative luminance ~0.0084).
    /// All accents maintain a minimum of 4.5:1 text contrast while preserving brand hues.
    let contrastRatioDescription: String
}

extension CodingPlatform {
    var style: PlatformStyle {
        switch self {
        case .leetcode:
            return PlatformStyle(
                platform: .leetcode,
                displayName: "LeetCode",
                shortLabel: "LC",
                // #FFA116: Official orange, contrast ~8.8:1 against 0x111712
                accent: Color(hex: 0xFFA116),
                softAccent: Color(hex: 0xFFA116).opacity(0.18),
                contrastRatioDescription: "8.8:1"
            )

        case .codeforces:
            return PlatformStyle(
                platform: .codeforces,
                displayName: "Codeforces",
                shortLabel: "CF",
                // #2594D6: Brand blue (hue 203°), lightness tuned for ~5.1:1 contrast against 0x111712
                accent: Color(hex: 0x2594D6),
                softAccent: Color(hex: 0x2594D6).opacity(0.18),
                contrastRatioDescription: "5.1:1"
            )

        case .codechef:
            return PlatformStyle(
                platform: .codechef,
                displayName: "CodeChef",
                shortLabel: "CC",
                // #BA805E: Warm brand brown (hue 26°), brightened to 55% lightness for ~5.4:1 contrast against 0x111712
                accent: Color(hex: 0xBA805E),
                softAccent: Color(hex: 0xBA805E).opacity(0.18),
                contrastRatioDescription: "5.4:1"
            )

        case .atcoder:
            return PlatformStyle(
                platform: .atcoder,
                displayName: "AtCoder",
                shortLabel: "AC",
                // #E0E0E0: Crisp monochrome light grey, contrast ~13.3:1 against 0x111712
                accent: Color(hex: 0xE0E0E0),
                softAccent: Color(hex: 0xE0E0E0).opacity(0.15),
                contrastRatioDescription: "13.3:1"
            )

        case .all:
            return PlatformStyle(
                platform: .all,
                displayName: "All Platforms",
                shortLabel: "ALL",
                accent: CodeTheme.primary,
                softAccent: CodeTheme.primary.opacity(0.18),
                contrastRatioDescription: ">10:1"
            )
        }
    }

    var platformAccent: Color {
        style.accent
    }
}

// MARK: - Platform Mark View (Step 1)

/// Minimal vector mark built exclusively from simple shapes and text.
/// Avoids official trademarks or raster artwork.
struct PlatformMarkView: View {
    let platform: CodingPlatform
    var size: CGFloat = 36

    init(platform: CodingPlatform, size: CGFloat = 36) {
        self.platform = platform
        self.size = size
    }

    private var scale: CGFloat {
        size / 36.0
    }

    var body: some View {
        ZStack {
            switch platform {
            case .leetcode:
                // LeetCode: Small rounded square in orange containing "LC" in bold monospaced text.
                RoundedRectangle(cornerRadius: 8 * scale, style: .continuous)
                    .fill(Color(hex: 0xFFA116))
                Text("LC")
                    .font(.system(size: 13 * scale, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: 0x0A0D0B))

            case .codeforces:
                // Codeforces: Three vertical bars in yellow, blue and red (increasing heights) next to "CF".
                RoundedRectangle(cornerRadius: 8 * scale, style: .continuous)
                    .fill(Color(hex: 0x2594D6).opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8 * scale, style: .continuous)
                            .stroke(Color(hex: 0x2594D6).opacity(0.35), lineWidth: 1)
                    )

                HStack(alignment: .bottom, spacing: 2 * scale) {
                    RoundedRectangle(cornerRadius: 1 * scale)
                        .fill(Color(hex: 0xFFD233))
                        .frame(width: 2.4 * scale, height: 9 * scale)
                    RoundedRectangle(cornerRadius: 1 * scale)
                        .fill(Color(hex: 0x2594D6))
                        .frame(width: 2.4 * scale, height: 13 * scale)
                    RoundedRectangle(cornerRadius: 1 * scale)
                        .fill(Color(hex: 0xFF4D4F))
                        .frame(width: 2.4 * scale, height: 17 * scale)

                    Text("CF")
                        .font(.system(size: 10.5 * scale, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(hex: 0xD8F5E0))
                        .padding(.leading, 1 * scale)
                }

            case .codechef:
                // CodeChef: Small rounded square in brown with "CC".
                RoundedRectangle(cornerRadius: 8 * scale, style: .continuous)
                    .fill(Color(hex: 0xBA805E))
                Text("CC")
                    .font(.system(size: 13 * scale, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: 0x0A0D0B))

            case .atcoder:
                // AtCoder: Small rounded square with a light outline and "AC".
                RoundedRectangle(cornerRadius: 8 * scale, style: .continuous)
                    .fill(Color(hex: 0xE0E0E0).opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8 * scale, style: .continuous)
                            .stroke(Color(hex: 0xE0E0E0), lineWidth: 1.2 * scale)
                    )
                Text("AC")
                    .font(.system(size: 13 * scale, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: 0xE0E0E0))

            case .all:
                RoundedRectangle(cornerRadius: 8 * scale, style: .continuous)
                    .fill(CodeTheme.primary.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8 * scale, style: .continuous)
                            .stroke(CodeTheme.primary.opacity(0.4), lineWidth: 1)
                    )
                Text("ALL")
                    .font(.system(size: 10 * scale, weight: .bold, design: .monospaced))
                    .foregroundStyle(CodeTheme.primary)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Contest Type Detector (Step 2.3)

enum ContestTypeDetector {
    /// Detects a recognizable contest category chip from the contest name or platform.
    /// Never guesses; returns nil if no known pattern is matched.
    static func detect(name: String, platform: CodingPlatform) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        switch platform {
        case .leetcode:
            if lower.contains("biweekly") {
                return "Biweekly"
            } else if lower.contains("weekly") {
                return "Weekly"
            }
            return nil

        case .codeforces:
            if lower.contains("div. 1 + div. 2") || lower.contains("div.1 + div.2")
                || lower.contains("div. 1+2") || lower.contains("div.1+2")
                || lower.contains("div. 1 + 2") || lower.contains("div. 1 and div. 2") {
                return "Div. 1 + Div. 2"
            }
            if lower.contains("educational") {
                return "Educational"
            }
            if lower.contains("global") {
                return "Global"
            }
            if containsWord(lower, pattern: #"\bdiv\.?\s*1\b"#) {
                return "Div. 1"
            }
            if containsWord(lower, pattern: #"\bdiv\.?\s*2\b"#) {
                return "Div. 2"
            }
            if containsWord(lower, pattern: #"\bdiv\.?\s*3\b"#) {
                return "Div. 3"
            }
            if containsWord(lower, pattern: #"\bdiv\.?\s*4\b"#) {
                return "Div. 4"
            }
            if containsWord(lower, pattern: #"\brated\b"#) {
                return "Rated"
            }
            return nil

        case .codechef:
            if lower.contains("starters") || containsWord(lower, pattern: #"\bstart\d*\b"#) {
                return "Starters"
            }
            if lower.contains("lunchtime") {
                return "Lunchtime"
            }
            if lower.contains("ltime") {
                return "LTIME"
            }
            if lower.contains("cook-off") || lower.contains("cookoff") || lower.contains("cook off") || containsWord(lower, pattern: #"\bcook\d*\b"#) {
                return "Cook-Off"
            }
            if lower.contains("long challenge") || containsWord(lower, pattern: #"\blong\b"#) {
                return "Long"
            }
            return nil

        case .atcoder:
            if containsWord(lower, pattern: #"\babc\d*\b"#) || lower.contains("beginner") {
                return "ABC"
            }
            if containsWord(lower, pattern: #"\barc\d*\b"#) || lower.contains("regular") {
                return "ARC"
            }
            if containsWord(lower, pattern: #"\bagc\d*\b"#) || lower.contains("grand") {
                return "AGC"
            }
            if containsWord(lower, pattern: #"\bahc\d*\b"#) || lower.contains("heuristic") {
                return "AHC"
            }
            return nil

        case .all:
            return nil
        }
    }

    private static func containsWord(_ text: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return false
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }
}

// MARK: - Contest Type Chip View

struct ContestTypeChipView: View {
    let type: String
    let accent: Color

    init(type: String, accent: Color) {
        self.type = type
        self.accent = accent
    }

    var body: some View {
        Text(type)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(accent.opacity(0.14))
            .overlay(
                Capsule().stroke(accent.opacity(0.32), lineWidth: 0.5)
            )
            .clipShape(Capsule())
    }
}
