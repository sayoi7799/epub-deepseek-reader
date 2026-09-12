import SwiftUI
import Foundation

enum ReaderFont: String, CaseIterable, Identifiable, Codable {
    case serif
    case sans
    case kai

    var id: String { rawValue }

    var title: String {
        switch self {
        case .serif: return "宋体"
        case .sans: return "黑体"
        case .kai: return "楷体"
        }
    }

    var cssStack: String {
        switch self {
        case .serif:
            return "\"Songti SC\", \"Noto Serif CJK SC\", \"Source Han Serif SC\", Georgia, serif"
        case .sans:
            return "\"PingFang SC\", -apple-system, \"Helvetica Neue\", Arial, sans-serif"
        case .kai:
            return "\"Kaiti SC\", \"STKaiti\", \"KaiTi\", serif"
        }
    }
}

enum ReaderTheme: String, CaseIterable, Identifiable, Codable {
    case paper
    case white
    case gray
    case black

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paper: return "米黄"
        case .white: return "白纸"
        case .gray: return "深灰"
        case .black: return "纯黑"
        }
    }

    var isDark: Bool {
        self == .gray || self == .black
    }

    var backgroundColorHex: String {
        switch self {
        case .paper: return "#F6F0E4"
        case .white: return "#FFFFFF"
        case .gray: return "#1E1F22"
        case .black: return "#000000"
        }
    }

    var textColorHex: String {
        switch self {
        case .paper: return "#2B2620"
        case .white: return "#1A1A1A"
        case .gray: return "#D9D9DE"
        case .black: return "#C9C9CE"
        }
    }

    var translationBackgroundHex: String {
        switch self {
        case .paper: return "#EFE6D3"
        case .white: return "#F2F4F8"
        case .gray: return "#2A2B30"
        case .black: return "#151517"
        }
    }

    var accentHex: String {
        switch self {
        case .paper: return "#B4763A"
        case .white: return "#3B7DD8"
        case .gray: return "#7FA7E8"
        case .black: return "#7FA7E8"
        }
    }

    var colorScheme: ColorScheme {
        isDark ? .dark : .light
    }

    var backgroundColor: Color {
        Color(hex: backgroundColorHex)
    }

    var textColor: Color {
        Color(hex: textColorHex)
    }
}

struct ReaderAppearance: Codable, Equatable {
    var fontSize: Double = 19
    var lineHeight: Double = 1.85
    var font: ReaderFont = .serif
    var theme: ReaderTheme = .paper
    var horizontalPadding: Double = 22
    var firstLineIndent: Bool = false

    static let fontSizeRange: ClosedRange<Double> = 14...30
    static let lineHeightRange: ClosedRange<Double> = 1.3...2.4
}

extension Color {
    init(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") {
            cleaned.removeFirst()
        }
        if cleaned.count == 3 {
            cleaned = cleaned.map { "\($0)\($0)" }.joined()
        }
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let red = Double((value & 0xFF0000) >> 16) / 255
        let green = Double((value & 0x00FF00) >> 8) / 255
        let blue = Double(value & 0x0000FF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
