import Foundation

enum NutritionLabelFieldKey: String, CaseIterable, Hashable, Sendable {
    case energyKcal
    case proteinG
    case carbohydratesG
    case fatG
    case saturatedFatG
    case transFatG
    case cholesterolMg
    case fiberG
    case sugarG
    case addedSugarG
    case sodiumMg
    case vitaminDMcg
    case calciumMg
    case ironMg
    case potassiumMg

    var label: String {
        switch self {
        case .energyKcal: return "热量"
        case .proteinG: return "蛋白质"
        case .carbohydratesG: return "碳水化合物"
        case .fatG: return "总脂肪"
        case .saturatedFatG: return "饱和脂肪"
        case .transFatG: return "反式脂肪"
        case .cholesterolMg: return "胆固醇"
        case .fiberG: return "膳食纤维"
        case .sugarG: return "总糖"
        case .addedSugarG: return "添加糖"
        case .sodiumMg: return "钠"
        case .vitaminDMcg: return "维生素 D"
        case .calciumMg: return "钙"
        case .ironMg: return "铁"
        case .potassiumMg: return "钾"
        }
    }
}

enum NutritionLabelValueUnit: String, Equatable, Sendable {
    case kilocalories
    case grams
    case milligrams
    case micrograms
    case milliliters
    case count

    var symbol: String {
        switch self {
        case .kilocalories: return "千卡"
        case .grams: return "g"
        case .milligrams: return "mg"
        case .micrograms: return "µg"
        case .milliliters: return "mL"
        case .count: return ""
        }
    }
}

enum NutritionValueQualifier: String, Equatable, Sendable {
    case exact
    case lessThan
    case approximate
}

struct ParsedNutritionField: Equatable, Sendable {
    let key: NutritionLabelFieldKey?
    let amount: Decimal
    let unit: NutritionLabelValueUnit
    let qualifier: NutritionValueQualifier
    let confidence: Float
    let rawText: String
    let requiresConfirmation: Bool
}

struct ParsedNutritionColumn: Equatable, Sendable {
    let basis: NutritionBasis
    let basisConfidence: Float
    let basisRequiresConfirmation: Bool
    let fields: [NutritionLabelFieldKey: ParsedNutritionField]
    let values: NutritionValues

    func field(_ key: NutritionLabelFieldKey) -> ParsedNutritionField? {
        fields[key]
    }
}

struct ParsedNutritionLabel: Equatable, Sendable {
    let columns: [ParsedNutritionColumn]
    let servingSizeText: String?
    let servingGrams: ParsedNutritionField?
    let servingMilliliters: ParsedNutritionField?
    let unitsPerServing: ParsedNutritionField?
    let servingsPerPackage: ParsedNutritionField?
    let rawOCRText: String
    let warnings: [String]

    var fieldsRequiringConfirmation: [ParsedNutritionField] {
        columns.flatMap { column in
            column.fields.values.filter(\.requiresConfirmation)
        }
    }
}

/// 规则化营养标签解析器。只转换 OCR 已读出的文字，不联网、不猜缺失的营养值。
enum NutritionLabelParser {
    static let automaticAcceptanceConfidence: Float = 0.85

    static func parse(lines: [RecognizedNutritionTextLine]) -> ParsedNutritionLabel {
        let sanitizedLines = lines
            .map {
                RecognizedNutritionTextLine(
                    id: $0.id,
                    text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    confidence: min(max($0.confidence, 0), 1),
                    boundingBox: $0.boundingBox
                )
            }
            .filter { !$0.text.isEmpty }
        let usableLines = mergeSameRowFragments(in: sanitizedLines)

        let basisMatches = detectedBases(in: usableLines)
        let bases: [DetectedBasis]
        let inferredBasis: Bool
        if basisMatches.isEmpty {
            bases = [
                DetectedBasis(
                    basis: .perServing,
                    confidence: 0,
                    lineIndex: Int.max,
                    characterOffset: Int.max
                )
            ]
            inferredBasis = true
        } else {
            bases = basisMatches
            inferredBasis = false
        }

        let isMultiColumn = bases.count > 1
        var fieldsByColumn = Array(
            repeating: [NutritionLabelFieldKey: ParsedNutritionField](),
            count: bases.count
        )
        var warnings: [String] = []

        for line in usableLines {
            let normalized = normalize(line.text)
            guard let key = nutrientKey(in: normalized) else { continue }
            let converted = nutrientTokens(
                in: normalized,
                key: key,
                confidence: line.confidence
            )
            guard !converted.isEmpty else { continue }

            let hasUnexpectedValueCount = converted.count != bases.count
            for columnIndex in bases.indices {
                guard columnIndex < converted.count else { continue }
                let token = converted[columnIndex]
                let needsConfirmation =
                    line.confidence < automaticAcceptanceConfidence
                    || token.qualifier != .exact
                    || isMultiColumn
                    || hasUnexpectedValueCount

                let field = ParsedNutritionField(
                    key: key,
                    amount: token.amount,
                    unit: token.unit,
                    qualifier: token.qualifier,
                    confidence: line.confidence,
                    rawText: line.text,
                    requiresConfirmation: needsConfirmation
                )

                if let existing = fieldsByColumn[columnIndex][key] {
                    let shouldReplace = field.confidence > existing.confidence
                    if existing.amount != field.amount {
                        warnings.append("\(key.label)识别到多个不同数值，请确认。")
                    }
                    if shouldReplace {
                        fieldsByColumn[columnIndex][key] = fieldRequiringConfirmation(field)
                    } else {
                        fieldsByColumn[columnIndex][key] = fieldRequiringConfirmation(existing)
                    }
                } else {
                    fieldsByColumn[columnIndex][key] = field
                }
            }
        }

        if inferredBasis {
            warnings.append("未识别到明确的营养基准，暂按每份显示，请确认。")
        }
        if isMultiColumn {
            warnings.append("检测到多列营养数据，请确认本次使用哪一列。")
        }
        if fieldsByColumn.allSatisfy({ $0[.energyKcal] == nil }) {
            warnings.append("没有可靠识别到热量，请补充后再保存。")
        }

        let columns = bases.enumerated().map { index, detected in
            let fields = fieldsByColumn[index]
            return ParsedNutritionColumn(
                basis: detected.basis,
                basisConfidence: detected.confidence,
                basisRequiresConfirmation:
                    inferredBasis
                    || isMultiColumn
                    || detected.confidence < automaticAcceptanceConfidence,
                fields: fields,
                values: nutritionValues(from: fields)
            )
        }

        let servingMetadata = parseServingMetadata(in: usableLines)
        return ParsedNutritionLabel(
            columns: columns,
            servingSizeText: servingMetadata.servingSizeText,
            servingGrams: servingMetadata.servingGrams,
            servingMilliliters: servingMetadata.servingMilliliters,
            unitsPerServing: servingMetadata.unitsPerServing,
            servingsPerPackage: servingMetadata.servingsPerPackage,
            rawOCRText: usableLines.map(\.text).joined(separator: "\n"),
            warnings: unique(warnings)
        )
    }
}

private extension NutritionLabelParser {
    struct DetectedBasis {
        let basis: NutritionBasis
        let confidence: Float
        let lineIndex: Int
        let characterOffset: Int
    }

    struct RawValueToken {
        let amount: Decimal
        let unit: RawUnit?
        let qualifier: NutritionValueQualifier
        let range: NSRange
    }

    enum RawUnit {
        case kilocalories
        case kilojoules
        case grams
        case milligrams
        case micrograms
        case milliliters
        case percent
    }

    struct ConvertedValueToken {
        let amount: Decimal
        let unit: NutritionLabelValueUnit
        let qualifier: NutritionValueQualifier
    }

    struct ServingMetadata {
        var servingSizeText: String?
        var servingGrams: ParsedNutritionField?
        var servingMilliliters: ParsedNutritionField?
        var unitsPerServing: ParsedNutritionField?
        var servingsPerPackage: ParsedNutritionField?
    }

    struct IndexedTextLine {
        let originalIndex: Int
        let line: RecognizedNutritionTextLine
    }

    static func mergeSameRowFragments(
        in lines: [RecognizedNutritionTextLine]
    ) -> [RecognizedNutritionTextLine] {
        var groups: [[IndexedTextLine]] = []

        for (index, line) in lines.enumerated() {
            let indexedLine = IndexedTextLine(
                originalIndex: index,
                line: line
            )
            guard hasUsableGeometry(line.boundingBox) else {
                groups.append([indexedLine])
                continue
            }

            if let groupIndex = groups.firstIndex(where: {
                canMerge(line, into: $0)
            }) {
                groups[groupIndex].append(indexedLine)
            } else {
                groups.append([indexedLine])
            }
        }

        return groups
            .sorted {
                ($0.map(\.originalIndex).min() ?? 0)
                    < ($1.map(\.originalIndex).min() ?? 0)
            }
            .map { group in
                guard group.count > 1 else {
                    return group[0].line
                }

                let ordered = group.sorted {
                    $0.line.boundingBox.minX < $1.line.boundingBox.minX
                }
                let first = ordered[0].line
                return RecognizedNutritionTextLine(
                    id: first.id,
                    text: ordered.map(\.line.text).joined(separator: " "),
                    confidence: ordered.map(\.line.confidence).min() ?? 0,
                    boundingBox: ordered.dropFirst().reduce(first.boundingBox) {
                        $0.union($1.line.boundingBox)
                    }
                )
            }
    }

    static func canMerge(
        _ candidate: RecognizedNutritionTextLine,
        into group: [IndexedTextLine]
    ) -> Bool {
        guard !group.isEmpty,
              group.allSatisfy({
                  hasUsableGeometry($0.line.boundingBox)
                      && isHorizontallyDistinct(
                          candidate.boundingBox,
                          $0.line.boundingBox
                      )
              }) else {
            return false
        }

        return group.contains {
            isSameVisualRow(candidate.boundingBox, $0.line.boundingBox)
        }
    }

    static func hasUsableGeometry(_ box: CGRect) -> Bool {
        !box.isNull
            && !box.isInfinite
            && box.width > 0
            && box.height > 0
            && box.minX.isFinite
            && box.minY.isFinite
            && box.maxX.isFinite
            && box.maxY.isFinite
    }

    static func isSameVisualRow(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let overlap = min(lhs.maxY, rhs.maxY) - max(lhs.minY, rhs.minY)
        let shorterHeight = min(lhs.height, rhs.height)
        if overlap > 0, overlap / shorterHeight >= 0.5 {
            return true
        }

        let centerDistance = abs(lhs.midY - rhs.midY)
        return centerDistance <= shorterHeight * 0.35
    }

    static func isHorizontallyDistinct(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let overlap = min(lhs.maxX, rhs.maxX) - max(lhs.minX, rhs.minX)
        guard overlap > 0 else {
            return true
        }
        return overlap / min(lhs.width, rhs.width) <= 0.15
    }

    static func detectedBases(
        in lines: [RecognizedNutritionTextLine]
    ) -> [DetectedBasis] {
        let patterns: [(NutritionBasis, String)] = [
            (.per100Grams, #"(?:per|每)\s*100\s*(?:g|克)"#),
            (.per100Milliliters, #"(?:per|每)\s*100\s*(?:ml|毫升)"#),
            (
                .perServing,
                #"(?:amount\s+)?per\s+serving\b|serving\s+size\b|每\s*份"#
            ),
            (
                .perPackage,
                #"amount\s+per\s+(?:container|package)\b|per\s+(?:container|package)\b|整\s*(?:包|盒)|每\s*(?:包|盒)"#
            ),
            (
                .perUnit,
                #"per\s+(?:unit|piece|bar|bottle)\b|每\s*(?:个|块|片|条|瓶)"#
            )
        ]

        var matches: [DetectedBasis] = []
        for (lineIndex, line) in lines.enumerated() {
            let normalized = normalize(line.text)
            let isServingCountLine =
                regexContains(#"\bservings?\s+per\s+(?:container|package)\b"#, in: normalized)
                || (
                    normalized.contains("份")
                    && (
                        normalized.contains("本包装")
                        || normalized.contains("包装含")
                        || normalized.contains("每包装")
                    )
                )

            for (basis, pattern) in patterns {
                if basis == .perPackage, isServingCountLine {
                    continue
                }
                for range in regexRanges(pattern, in: normalized) {
                    matches.append(
                        DetectedBasis(
                            basis: basis,
                            confidence: line.confidence,
                            lineIndex: lineIndex,
                            characterOffset: range.location
                        )
                    )
                }
            }
        }

        let ordered = matches.sorted {
            if $0.lineIndex != $1.lineIndex {
                return $0.lineIndex < $1.lineIndex
            }
            return $0.characterOffset < $1.characterOffset
        }

        var seen = Set<NutritionBasis>()
        return ordered.filter { seen.insert($0.basis).inserted }
    }

    static func nutrientKey(in line: String) -> NutritionLabelFieldKey? {
        if line.contains("calories from fat")
            || isDailyCalorieReference(line) {
            return nil
        }
        if containsAny(line, ["added sugar", "added sugars", "添加糖"]) {
            return .addedSugarG
        }
        if containsAny(line, ["trans fat", "反式脂肪"]) {
            return .transFatG
        }
        if containsAny(line, ["saturated fat", "饱和脂肪"]) {
            return .saturatedFatG
        }
        if containsAny(line, ["dietary fiber", "dietary fibre", "膳食纤维"]) {
            return .fiberG
        }
        if containsAny(line, ["total carbohydrate", "total carbohydrates", "carbohydrate", "碳水化合物"]) {
            return .carbohydratesG
        }
        if containsAny(line, ["total sugars", "total sugar", "sugars", "总糖"]) {
            return .sugarG
        }
        if containsAny(line, ["total fat", "脂肪"]) {
            return .fatG
        }
        if containsAny(line, ["cholesterol", "胆固醇"]) {
            return .cholesterolMg
        }
        if containsAny(line, ["sodium", "钠"]) {
            return .sodiumMg
        }
        if containsAny(line, ["protein", "蛋白质"]) {
            return .proteinG
        }
        if containsAny(line, ["vitamin d", "维生素d", "维生素 d"]) {
            return .vitaminDMcg
        }
        if containsAny(line, ["calcium", "钙"]) {
            return .calciumMg
        }
        if containsAny(line, ["iron", "铁"]) {
            return .ironMg
        }
        if containsAny(line, ["potassium", "钾"]) {
            return .potassiumMg
        }
        if containsAny(line, ["calories", "energy", "热量", "能量"]) {
            return .energyKcal
        }
        return nil
    }

    static func isDailyCalorieReference(_ line: String) -> Bool {
        regexContains(
            #"\b[0-9][0-9,.]*\s+calories?\s+(?:a|per)\s+day\b"#,
            in: line
        )
    }

    static func nutrientTokens(
        in line: String,
        key: NutritionLabelFieldKey,
        confidence: Float
    ) -> [ConvertedValueToken] {
        let rawTokens = valueTokens(in: line).filter { token in
            token.unit != .percent && !isBasisToken(token, in: line)
        }

        if key == .energyKcal {
            let explicitKcal = rawTokens.compactMap { token -> ConvertedValueToken? in
                guard token.unit == .kilocalories else { return nil }
                return ConvertedValueToken(
                    amount: token.amount,
                    unit: .kilocalories,
                    qualifier: token.qualifier
                )
            }
            if !explicitKcal.isEmpty {
                return explicitKcal
            }

            let kilojoules = rawTokens.compactMap { token -> ConvertedValueToken? in
                guard token.unit == .kilojoules else { return nil }
                return ConvertedValueToken(
                    amount: token.amount / Decimal(string: "4.184")!,
                    unit: .kilocalories,
                    qualifier: token.qualifier
                )
            }
            if !kilojoules.isEmpty {
                return kilojoules
            }

            guard line.contains("calories") || line.contains("热量") else {
                return []
            }
            return rawTokens.compactMap { token in
                guard token.unit == nil else { return nil }
                return ConvertedValueToken(
                    amount: token.amount,
                    unit: .kilocalories,
                    qualifier: token.qualifier
                )
            }
        }

        return rawTokens.compactMap { token in
            convert(token, for: key)
        }
    }

    static func convert(
        _ token: RawValueToken,
        for key: NutritionLabelFieldKey
    ) -> ConvertedValueToken? {
        let target: NutritionLabelValueUnit
        let amount: Decimal

        switch key {
        case .proteinG, .carbohydratesG, .fatG, .saturatedFatG,
             .transFatG, .fiberG, .sugarG, .addedSugarG:
            target = .grams
            switch token.unit {
            case .grams: amount = token.amount
            case .milligrams: amount = token.amount / 1_000
            case .micrograms: amount = token.amount / 1_000_000
            default: return nil
            }

        case .cholesterolMg, .sodiumMg, .calciumMg, .ironMg, .potassiumMg:
            target = .milligrams
            switch token.unit {
            case .grams: amount = token.amount * 1_000
            case .milligrams: amount = token.amount
            case .micrograms: amount = token.amount / 1_000
            default: return nil
            }

        case .vitaminDMcg:
            target = .micrograms
            switch token.unit {
            case .grams: amount = token.amount * 1_000_000
            case .milligrams: amount = token.amount * 1_000
            case .micrograms: amount = token.amount
            default: return nil
            }

        case .energyKcal:
            return nil
        }

        return ConvertedValueToken(
            amount: amount,
            unit: target,
            qualifier: token.qualifier
        )
    }

    static func parseServingMetadata(
        in lines: [RecognizedNutritionTextLine]
    ) -> ServingMetadata {
        var result = ServingMetadata()

        for line in lines {
            let normalized = normalize(line.text)
            let isServingSizeLine =
                normalized.contains("serving size")
                || normalized.contains("每份用量")
                || normalized.contains("每份大小")
                || regexContains(#"每\s*份\s*[0-9]"#, in: normalized)

            if isServingSizeLine {
                if result.servingSizeText == nil {
                    result.servingSizeText = line.text
                }
                let tokens = valueTokens(in: normalized)
                if result.servingGrams == nil,
                   let token = tokens.first(where: { $0.unit == .grams }) {
                    result.servingGrams = metadataField(
                        token: token,
                        unit: .grams,
                        line: line
                    )
                }
                if result.servingMilliliters == nil,
                   let token = tokens.first(where: { $0.unit == .milliliters }) {
                    result.servingMilliliters = metadataField(
                        token: token,
                        unit: .milliliters,
                        line: line
                    )
                }
                if result.unitsPerServing == nil,
                   let count = servingUnitCount(in: normalized) {
                    result.unitsPerServing = ParsedNutritionField(
                        key: nil,
                        amount: count.amount,
                        unit: .count,
                        qualifier: count.qualifier,
                        confidence: line.confidence,
                        rawText: line.text,
                        requiresConfirmation:
                            line.confidence < automaticAcceptanceConfidence
                            || count.qualifier != .exact
                    )
                }
            }

            let isPackageCountLine =
                regexContains(#"\bservings?\s+per\s+(?:container|package)\b"#, in: normalized)
                || (
                    normalized.contains("份")
                    && (
                        normalized.contains("包装")
                        || normalized.contains("本包")
                        || normalized.contains("每包")
                        || normalized.contains("每盒")
                    )
                )
            if result.servingsPerPackage == nil, isPackageCountLine,
               let token = valueTokens(in: normalized).first(where: { $0.unit == nil }) {
                result.servingsPerPackage = ParsedNutritionField(
                    key: nil,
                    amount: token.amount,
                    unit: .count,
                    qualifier: token.qualifier,
                    confidence: line.confidence,
                    rawText: line.text,
                    requiresConfirmation:
                        line.confidence < automaticAcceptanceConfidence
                        || token.qualifier != .exact
                )
            }
        }
        return result
    }

    static func servingUnitCount(
        in line: String
    ) -> (amount: Decimal, qualifier: NutritionValueQualifier)? {
        let pattern = #"(<\s*|less\s+than\s*|约\s*|about\s*|approximately\s*)?([0-9]+(?:[.,][0-9]+)?)\s*(?:pieces?|bars?|bottles?|slices?|capsules?|tablets?|个|块|片|条|瓶|粒)"#
        guard let match = firstRegexMatch(pattern, in: line),
              let numberRange = Range(match.range(at: 2), in: line),
              let amount = decimal(from: String(line[numberRange])) else {
            return nil
        }
        let qualifier: NutritionValueQualifier
        if let qualifierRange = Range(match.range(at: 1), in: line) {
            qualifier = parsedQualifier(String(line[qualifierRange]))
        } else {
            qualifier = .exact
        }
        return (amount, qualifier)
    }

    static func metadataField(
        token: RawValueToken,
        unit: NutritionLabelValueUnit,
        line: RecognizedNutritionTextLine
    ) -> ParsedNutritionField {
        ParsedNutritionField(
            key: nil,
            amount: token.amount,
            unit: unit,
            qualifier: token.qualifier,
            confidence: line.confidence,
            rawText: line.text,
            requiresConfirmation:
                line.confidence < automaticAcceptanceConfidence
                || token.qualifier != .exact
        )
    }

    static func valueTokens(in line: String) -> [RawValueToken] {
        let pattern = #"(<\s*|less\s+than\s*|约\s*|about\s*|approximately\s*)?([0-9]+(?:[.,][0-9]+)?)\s*(kcal|kj|千卡|千焦(?:耳)?|mcg|µg|ug|mg|ml|g|微克|毫克|毫升|克|%)?"#
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return []
        }
        let searchRange = NSRange(line.startIndex..<line.endIndex, in: line)
        return expression.matches(in: line, range: searchRange).compactMap { match in
            guard let numberRange = Range(match.range(at: 2), in: line),
                  let amount = decimal(from: String(line[numberRange])) else {
                return nil
            }
            let qualifier: NutritionValueQualifier
            if let qualifierRange = Range(match.range(at: 1), in: line) {
                qualifier = parsedQualifier(String(line[qualifierRange]))
            } else {
                qualifier = .exact
            }
            let unit: RawUnit?
            if let unitRange = Range(match.range(at: 3), in: line) {
                unit = rawUnit(String(line[unitRange]))
            } else {
                unit = nil
            }
            return RawValueToken(
                amount: amount,
                unit: unit,
                qualifier: qualifier,
                range: match.range
            )
        }
    }

    static func isBasisToken(_ token: RawValueToken, in line: String) -> Bool {
        guard token.amount == 100,
              token.unit == .grams || token.unit == .milliliters,
              let swiftRange = Range(token.range, in: line) else {
            return false
        }
        let prefix = line[..<swiftRange.lowerBound].suffix(8)
        return prefix.contains("per") || prefix.contains("每")
    }

    static func rawUnit(_ text: String) -> RawUnit? {
        switch normalize(text) {
        case "kcal", "千卡": return .kilocalories
        case "kj", "千焦", "千焦耳": return .kilojoules
        case "g", "克": return .grams
        case "mg", "毫克": return .milligrams
        case "mcg", "µg", "ug", "微克": return .micrograms
        case "ml", "毫升": return .milliliters
        case "%": return .percent
        default: return nil
        }
    }

    static func parsedQualifier(_ text: String) -> NutritionValueQualifier {
        let normalized = normalize(text)
        if normalized.contains("<") || normalized.contains("less") {
            return .lessThan
        }
        if containsAny(normalized, ["about", "approximately", "约"]) {
            return .approximate
        }
        return .exact
    }

    static func decimal(from text: String) -> Decimal? {
        var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.contains(","), !normalized.contains(".") {
            let pieces = normalized.split(separator: ",", omittingEmptySubsequences: false)
            if pieces.count == 2, pieces[1].count == 3, pieces[0] != "0" {
                normalized = pieces.joined()
            } else {
                normalized = normalized.replacingOccurrences(of: ",", with: ".")
            }
        } else {
            normalized = normalized.replacingOccurrences(of: ",", with: "")
        }
        return Decimal(
            string: normalized,
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    static func nutritionValues(
        from fields: [NutritionLabelFieldKey: ParsedNutritionField]
    ) -> NutritionValues {
        NutritionValues(
            energyKcal: fields[.energyKcal]?.amount,
            proteinG: fields[.proteinG]?.amount,
            carbohydratesG: fields[.carbohydratesG]?.amount,
            fatG: fields[.fatG]?.amount,
            saturatedFatG: fields[.saturatedFatG]?.amount,
            transFatG: fields[.transFatG]?.amount,
            cholesterolMg: fields[.cholesterolMg]?.amount,
            fiberG: fields[.fiberG]?.amount,
            sugarG: fields[.sugarG]?.amount,
            addedSugarG: fields[.addedSugarG]?.amount,
            sodiumMg: fields[.sodiumMg]?.amount,
            vitaminDMcg: fields[.vitaminDMcg]?.amount,
            calciumMg: fields[.calciumMg]?.amount,
            ironMg: fields[.ironMg]?.amount,
            potassiumMg: fields[.potassiumMg]?.amount
        )
    }

    static func fieldRequiringConfirmation(
        _ field: ParsedNutritionField
    ) -> ParsedNutritionField {
        ParsedNutritionField(
            key: field.key,
            amount: field.amount,
            unit: field.unit,
            qualifier: field.qualifier,
            confidence: field.confidence,
            rawText: field.rawText,
            requiresConfirmation: true
        )
    }

    static func normalize(_ text: String) -> String {
        let halfWidth = text.applyingTransform(.fullwidthToHalfwidth, reverse: false)
            ?? text
        return halfWidth
            .lowercased()
            .replacingOccurrences(of: "μ", with: "µ")
            .replacingOccurrences(of: "\u{00a0}", with: " ")
    }

    static func containsAny(_ value: String, _ needles: [String]) -> Bool {
        needles.contains(where: value.contains)
    }

    static func regexContains(_ pattern: String, in value: String) -> Bool {
        firstRegexMatch(pattern, in: value) != nil
    }

    static func firstRegexMatch(
        _ pattern: String,
        in value: String
    ) -> NSTextCheckingResult? {
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.firstMatch(in: value, range: range)
    }

    static func regexRanges(_ pattern: String, in value: String) -> [NSRange] {
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return []
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.matches(in: value, range: range).map(\.range)
    }

    static func unique(_ strings: [String]) -> [String] {
        var seen = Set<String>()
        return strings.filter { seen.insert($0).inserted }
    }
}
