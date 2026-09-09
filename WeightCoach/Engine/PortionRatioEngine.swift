import Foundation

/// 用户自定义食用比例的结构化校验错误，UI 可按 case 显示对应提示。
enum PortionRatioValidationError: Error, Equatable, Sendable {
    case empty
    case invalidFormat
    case negative
    case mustBePositive
    case divisionByZero
    case notFinite
    case exceedsMaximum(maximum: Double)
}

/// 解析和格式化「相对原记录吃了多少份」。
///
/// 支持小数、普通分数、带分数和常见 Unicode 分数字符，例如：
/// `0.75`、`3/4`、`3／4`、`1 1/2`、`¾`、`1½`。
enum PortionRatioEngine {
    /// 防止误输入把一条历史记录放大成不合理的热量和营养值。
    static let suggestedMaximum = 10.0

    static func parse(
        _ text: String,
        maximum: Double = suggestedMaximum
    ) throws -> Double {
        let normalized = normalize(text)
        guard !normalized.isEmpty else {
            throw PortionRatioValidationError.empty
        }
        guard maximum.isFinite, maximum > 0 else {
            preconditionFailure("Portion ratio maximum must be finite and positive")
        }

        if containsNegativeSign(normalized) {
            throw PortionRatioValidationError.negative
        }

        let value: Double
        if normalized.contains("/") {
            value = try parseSlashFraction(normalized)
        } else if let unicodeFraction = parseUnicodeFraction(normalized) {
            value = try unicodeFraction.get()
        } else if let parsed = Double(normalized) {
            value = parsed
        } else {
            throw PortionRatioValidationError.invalidFormat
        }

        guard value.isFinite else {
            throw PortionRatioValidationError.notFinite
        }
        guard value > 0 else {
            throw PortionRatioValidationError.mustBePositive
        }
        guard value <= maximum else {
            throw PortionRatioValidationError.exceedsMaximum(maximum: maximum)
        }
        return value
    }

    /// 用于输入框回填：保留最多 6 位小数，并按指定 locale 使用小数点或逗号。
    static func formattedForEditing(
        _ ratio: Double,
        locale: Locale = .current
    ) -> String {
        guard ratio.isFinite else { return "" }
        return ratio.formatted(
            .number
                .grouping(.never)
                .precision(.fractionLength(0...6))
                .locale(locale)
        )
    }

    /// 用于摘要展示：能无损表示时优先使用紧凑分数，否则显示简洁小数。
    static func formattedForDisplay(
        _ ratio: Double,
        locale: Locale = .current
    ) -> String {
        guard ratio.isFinite, ratio >= 0 else { return "" }

        let whole = Int(ratio.rounded(.down))
        let remainder = ratio - Double(whole)
        if let glyph = matchingFractionGlyph(for: remainder) {
            return whole == 0 ? glyph : "\(whole)\(glyph)"
        }
        return formattedForEditing(ratio, locale: locale)
    }

    private static func normalize(_ text: String) -> String {
        let converted = String(text.map { character in
            switch character {
            case "／", "⁄", "∕": return "/"
            case "．": return "."
            case "，": return ","
            case "−", "－": return "-"
            case "０": return "0"
            case "１": return "1"
            case "２": return "2"
            case "３": return "3"
            case "４": return "4"
            case "５": return "5"
            case "６": return "6"
            case "７": return "7"
            case "８": return "8"
            case "９": return "9"
            default: return character
            }
        })

        let collapsedWhitespace = converted
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        let decimalNormalized: String
        if collapsedWhitespace.contains(","),
           !collapsedWhitespace.contains(".") {
            decimalNormalized = collapsedWhitespace
                .replacingOccurrences(of: ",", with: ".")
        } else {
            decimalNormalized = collapsedWhitespace
        }
        return decimalNormalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func containsNegativeSign(_ text: String) -> Bool {
        text.contains("-")
    }

    private static func parseSlashFraction(_ text: String) throws -> Double {
        let slashParts = text.split(separator: "/", omittingEmptySubsequences: false)
        guard slashParts.count == 2 else {
            throw PortionRatioValidationError.invalidFormat
        }

        let leftParts = slashParts[0]
            .split(whereSeparator: { $0.isWhitespace })
        let denominatorText = slashParts[1]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard leftParts.count == 1 || leftParts.count == 2,
              !denominatorText.isEmpty,
              let denominator = parseUnsignedInteger(denominatorText) else {
            throw PortionRatioValidationError.invalidFormat
        }
        guard denominator != 0 else {
            throw PortionRatioValidationError.divisionByZero
        }

        let whole: UInt64
        let numeratorText: Substring
        if leftParts.count == 2 {
            guard let parsedWhole = parseUnsignedInteger(String(leftParts[0])) else {
                throw PortionRatioValidationError.invalidFormat
            }
            whole = parsedWhole
            numeratorText = leftParts[1]
        } else {
            whole = 0
            numeratorText = leftParts[0]
        }
        guard let numerator = parseUnsignedInteger(String(numeratorText)) else {
            throw PortionRatioValidationError.invalidFormat
        }

        return Double(whole) + Double(numerator) / Double(denominator)
    }

    private static func parseUnsignedInteger(_ text: String) -> UInt64? {
        guard !text.isEmpty, text.allSatisfy(\.isNumber) else { return nil }
        return UInt64(text)
    }

    private static func parseUnicodeFraction(
        _ text: String
    ) -> Result<Double, PortionRatioValidationError>? {
        guard let last = text.last,
              let fraction = unicodeFractions[last] else {
            return nil
        }

        let wholeText = text.dropLast()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let whole: UInt64
        if wholeText.isEmpty {
            whole = 0
        } else if let parsedWhole = parseUnsignedInteger(wholeText) {
            whole = parsedWhole
        } else {
            return .failure(.invalidFormat)
        }

        return .success(
            Double(whole) + Double(fraction.numerator) / Double(fraction.denominator)
        )
    }

    private static func matchingFractionGlyph(for value: Double) -> String? {
        guard value > 0 else { return nil }
        return displayFractions.first { fraction in
            abs(value - fraction.value) < 0.000_000_1
        }?.glyph
    }

    private static let unicodeFractions: [Character: (numerator: Int, denominator: Int)] = [
        "¼": (1, 4), "½": (1, 2), "¾": (3, 4),
        "⅐": (1, 7), "⅑": (1, 9), "⅒": (1, 10),
        "⅓": (1, 3), "⅔": (2, 3),
        "⅕": (1, 5), "⅖": (2, 5), "⅗": (3, 5), "⅘": (4, 5),
        "⅙": (1, 6), "⅚": (5, 6),
        "⅛": (1, 8), "⅜": (3, 8), "⅝": (5, 8), "⅞": (7, 8),
    ]

    private static let displayFractions: [(glyph: String, value: Double)] = [
        ("⅛", 1.0 / 8.0),
        ("¼", 1.0 / 4.0),
        ("⅓", 1.0 / 3.0),
        ("⅜", 3.0 / 8.0),
        ("½", 1.0 / 2.0),
        ("⅝", 5.0 / 8.0),
        ("⅔", 2.0 / 3.0),
        ("¾", 3.0 / 4.0),
        ("⅞", 7.0 / 8.0),
    ]
}
