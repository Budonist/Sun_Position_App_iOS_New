import SwiftUI

enum Theme {
    // MARK: - Colors
    enum Colors {
        static let background = Color(light: .init(hex: 0xFAF7F0), dark: .init(hex: 0x121417))
        static let surface = Color(light: .white, dark: .init(hex: 0x1E2126))
        static let primaryText = Color(light: .init(hex: 0x1C1E21), dark: .init(hex: 0xF2F0EB))
        static let secondaryText = Color(light: .init(hex: 0x5E6470), dark: .init(hex: 0xA5ABB5))
        static let sunYellow = Color(hex: 0xF2B705)
        static let shadowSlate = Color(hex: 0x4A5361)
        static let night = Color(hex: 0x121417)
        static let nightBorder = Color(hex: 0x3A3F48)
        static let separator = Color(light: .init(hex: 0xE6E1D6), dark: .init(hex: 0x2C3036))
        static let warningTint = Color(hex: 0xB5541B)
        static let warningBackground = Color(hex: 0xFBEFE6)
        static let loadingNeutral = Color(hex: 0xE6E1D6)
    }

    // MARK: - Fonts
    // Hinweis: SwiftUI skaliert Font.system(size:) automatisch mit der
    // Dynamic-Type-Einstellung des Systems (Einstellungen → Anzeige & Helligkeit
    // → Textgröße). Die Basisgrößen sind bewusst kompakt gehalten.
    enum Fonts {
        static let display = Font.system(size: 26, weight: .bold, design: .default)
        static let title = Font.system(size: 19, weight: .semibold)
        static let headline = Font.system(size: 16, weight: .semibold)
        static let body = Font.system(size: 15)
        static let caption = Font.system(size: 12)
        static let monoTime = Font.system(size: 15).monospacedDigit()
        static let monoCaption = Font.system(size: 12).monospacedDigit()
        static let monoLarge = Font.system(size: 19, weight: .semibold).monospacedDigit()
    }

    // MARK: - Spacing (8pt grid)
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    // MARK: - Radius
    enum Radius {
        static let sheet: CGFloat = 24
        static let card: CGFloat = 16
        static let symbolTile: CGFloat = 14
        static let chip: CGFloat = 100
    }
}

// MARK: - Color Helpers

extension Color {
    init(hex: UInt) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    init(light: UIColor, dark: UIColor) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

extension UIColor {
    convenience init(hex: UInt) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Status Helpers

extension PointStatus {
    var color: Color {
        switch self {
        case .sun: return Theme.Colors.sunYellow
        case .shadow: return Theme.Colors.shadowSlate
        case .night: return Theme.Colors.night
        }
    }

    var symbolName: String {
        switch self {
        case .sun: return "sun.max.fill"
        case .shadow: return "building.2.fill"
        case .night: return "moon.stars.fill"
        }
    }

    var title: String {
        switch self {
        case .sun: return "Direkte Sonne"
        case .shadow: return "Geb\u{00E4}udeschatten"
        case .night: return "Nacht \u{2013} Sonne unter dem Horizont"
        }
    }

    var symbolOnColor: Color {
        switch self {
        case .sun: return Color(hex: 0x1C1E21)
        case .shadow: return .white
        case .night: return .white
        }
    }
}
