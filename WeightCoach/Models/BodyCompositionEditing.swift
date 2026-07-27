import Foundation

enum BodyCompositionPresentation {
    static func primaryValueText(
        _ measurement: BodyCompositionMeasurement,
        approximate: Bool = false
    ) -> String {
        guard let value = measurement.value else {
            return "精确值未提供"
        }
        let prefix = approximate ? "约 " : ""
        return "\(prefix)\(numberText(value)) \(measurement.unit.symbol)"
    }

    static func primaryValueText(
        _ measurement: BodyCompositionMeasurement,
        approximate: Bool = false,
        locale: Locale
    ) -> String {
        guard let value = measurement.value else {
            return localized("精确值未提供", locale: locale)
        }
        let prefix = approximate ? "\(localized("约", locale: locale)) " : ""
        return "\(prefix)\(numberText(value)) \(measurement.unit.symbol)"
    }

    static func rangeText(_ measurement: BodyCompositionMeasurement) -> String {
        switch (measurement.lowerBound, measurement.upperBound) {
        case let (lower?, upper?):
            return "\(numberText(lower))–\(numberText(upper)) \(measurement.unit.symbol)"
        case let (lower?, nil):
            return "≥ \(numberText(lower)) \(measurement.unit.symbol)"
        case let (nil, upper?):
            return "≤ \(numberText(upper)) \(measurement.unit.symbol)"
        case (nil, nil):
            return "未提供"
        }
    }

    static func sourceText(_ measurement: BodyCompositionMeasurement) -> String {
        guard let source = cleaned(measurement.source), !source.isEmpty else {
            return "未提供"
        }
        return source
    }

    static func sourceText(
        _ measurement: BodyCompositionMeasurement,
        locale: Locale
    ) -> String {
        guard let source = cleaned(measurement.source), !source.isEmpty else {
            return localized("未提供", locale: locale)
        }
        // A source is entered by the user, so it must never be translated.
        return source
    }

    static func dateText(_ measurement: BodyCompositionMeasurement) -> String {
        guard let measuredAt = measurement.measuredAt else {
            return "未提供"
        }
        let components = Calendar.current.dateComponents(
            [.year, .month, .day],
            from: measuredAt
        )
        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            return "未提供"
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func dateText(
        _ measurement: BodyCompositionMeasurement,
        locale: Locale
    ) -> String {
        guard measurement.measuredAt != nil else {
            return localized("未提供", locale: locale)
        }
        return dateText(measurement)
    }

    static func numberText(_ value: Double) -> String {
        let text = String(
            format: "%.1f",
            locale: Locale(identifier: "en_US_POSIX"),
            value
        )
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }

    private static func cleaned(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func localized(_ key: String, locale: Locale) -> String {
        interfaceLocalized(key, locale: locale)
    }
}

struct BodyCompositionMeasurementDraft: Equatable {
    var valueText: String
    var lowerBoundText: String
    var upperBoundText: String
    var sourceText: String
    var includesDate: Bool
    var measuredAt: Date
    var noteText: String

    init(measurement: BodyCompositionMeasurement, fallbackDate: Date = .now) {
        valueText = measurement.value.map(BodyCompositionPresentation.numberText) ?? ""
        lowerBoundText = measurement.lowerBound.map(BodyCompositionPresentation.numberText) ?? ""
        upperBoundText = measurement.upperBound.map(BodyCompositionPresentation.numberText) ?? ""
        sourceText = measurement.source ?? ""
        includesDate = measurement.measuredAt != nil
        measuredAt = measurement.measuredAt ?? fallbackDate
        noteText = measurement.note ?? ""
    }

    func validatedMeasurement(
        unit: BodyCompositionUnit
    ) throws -> BodyCompositionMeasurement {
        let value = try parsed(valueText, field: "精确值")
        let lower = try parsed(lowerBoundText, field: "范围下限")
        let upper = try parsed(upperBoundText, field: "范围上限")

        for (field, candidate) in [
            ("精确值", value),
            ("范围下限", lower),
            ("范围上限", upper),
        ] {
            if let candidate, !Self.isPlausible(candidate, unit: unit) {
                throw BodyCompositionDraftError.implausible(field: field, unit: unit)
            }
        }

        if let lower, let upper, lower > upper {
            throw BodyCompositionDraftError.invertedRange
        }
        if let value, let lower, value < lower {
            throw BodyCompositionDraftError.valueOutsideRange
        }
        if let value, let upper, value > upper {
            throw BodyCompositionDraftError.valueOutsideRange
        }

        return BodyCompositionMeasurement(
            value: value,
            lowerBound: lower,
            upperBound: upper,
            unit: unit,
            source: cleaned(sourceText),
            measuredAt: includesDate ? measuredAt : nil,
            note: cleaned(noteText)
        )
    }

    func validationMessage(unit: BodyCompositionUnit) -> String? {
        do {
            _ = try validatedMeasurement(unit: unit)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func validationMessage(
        unit: BodyCompositionUnit,
        locale: Locale
    ) -> String? {
        do {
            _ = try validatedMeasurement(unit: unit)
            return nil
        } catch let error as BodyCompositionDraftError {
            return error.message(locale: locale)
        } catch {
            return error.localizedDescription
        }
    }

    mutating func clear() {
        valueText = ""
        lowerBoundText = ""
        upperBoundText = ""
        sourceText = ""
        includesDate = false
        noteText = ""
    }

    private func parsed(_ text: String, field: String) throws -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        let normalized = cleaned.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite else {
            throw BodyCompositionDraftError.invalidNumber(field: field)
        }
        return value
    }

    private func cleaned(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func isPlausible(
        _ value: Double,
        unit: BodyCompositionUnit
    ) -> Bool {
        switch unit {
        case .percent:
            return value > 0 && value < 100
        case .kilograms:
            return value > 0 && value <= 500
        case .kilogramsPerSquareMeter:
            return value > 0 && value <= 100
        }
    }
}

enum BodyCompositionDraftError: LocalizedError {
    case invalidNumber(field: String)
    case implausible(field: String, unit: BodyCompositionUnit)
    case invertedRange
    case valueOutsideRange

    var errorDescription: String? {
        switch self {
        case .invalidNumber(let field):
            return "\(field)必须是有效数字。"
        case .implausible(let field, let unit):
            return "\(field)超出合理的 \(unit.symbol) 范围。"
        case .invertedRange:
            return "范围下限不能大于上限。"
        case .valueOutsideRange:
            return "精确值必须落在填写的范围内。"
        }
    }

    func message(locale: Locale) -> String {
        switch self {
        case .invalidNumber(let field):
            return String(
                format: localized("%@必须是有效数字。", locale: locale),
                locale: locale,
                localized(field, locale: locale)
            )
        case .implausible(let field, let unit):
            return String(
                format: localized("%@超出合理的 %@ 范围。", locale: locale),
                locale: locale,
                localized(field, locale: locale),
                unit.symbol
            )
        case .invertedRange:
            return localized("范围下限不能大于上限。", locale: locale)
        case .valueOutsideRange:
            return localized("精确值必须落在填写的范围内。", locale: locale)
        }
    }

    private func localized(_ key: String, locale: Locale) -> String {
        interfaceLocalized(key, locale: locale)
    }
}

struct DailyIntakeReferenceDraft: Equatable {
    var valueText: String

    init(value: Double?) {
        valueText = value.map(BodyCompositionPresentation.numberText) ?? ""
    }

    func validatedValue() throws -> Double? {
        let cleaned = valueText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        let normalized = cleaned.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized),
              value.isFinite,
              value > 0,
              value < 10_000 else {
            throw DailyIntakeReferenceError.invalidValue
        }
        return value
    }

    var validationMessage: String? {
        do {
            _ = try validatedValue()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func validationMessage(locale: Locale) -> String? {
        do {
            _ = try validatedValue()
            return nil
        } catch let error as DailyIntakeReferenceError {
            return error.message(locale: locale)
        } catch {
            return error.localizedDescription
        }
    }
}

enum DailyIntakeReferenceError: LocalizedError {
    case invalidValue

    var errorDescription: String? {
        "日均参考必须是大于 0 且小于 10,000 的有效千卡数。"
    }

    func message(locale: Locale) -> String {
        interfaceLocalized(
            "日均参考必须是大于 0 且小于 10,000 的有效千卡数。",
            locale: locale
        )
    }
}
