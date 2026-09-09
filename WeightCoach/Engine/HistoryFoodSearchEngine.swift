import Foundation

/// 搜索历史快照时补充参考库的三语名称与别名，不改写旧记录或猜测自定义食物。
struct HistoryFoodSearchEngine {
    private let query: String

    init(query: String) {
        self.query = Self.normalized(query)
    }

    var isEmpty: Bool { query.isEmpty }

    func matches(
        name: String,
        portionText: String? = nil,
        mealLabel: String = "",
        sourceLabel: String = ""
    ) -> Bool {
        guard !query.isEmpty else { return true }

        let originalFields = [name, portionText ?? "", mealLabel, sourceLabel]
        if originalFields.contains(where: { Self.normalized($0).contains(query) }) {
            return true
        }

        // 只给可精确恢复身份的参考库快照扩展搜索词，避免把自定义名称中的
        // 「虾仁炒饭」等片段误当成参考库的「虾仁」。
        guard let referenceID = CommonFoodCatalog.referenceID(forStoredName: name),
              let terms = Self.referenceTerms[referenceID] else {
            return false
        }
        return terms.contains { $0.contains(query) }
    }

    /// 语言资源和别名随版本固定，输入每个字符时不再遍历所有食物做本地化。
    private static let referenceTerms: [String: [String]] = {
        let locales = [
            Locale(identifier: "zh-Hans"),
            Locale(identifier: "zh-Hant-TW"),
            Locale(identifier: "en-US"),
        ]
        return Dictionary(uniqueKeysWithValues: CommonFoodCatalog.foods.map { food in
            let names = [food.name, food.displayName] + food.aliases
                + locales.flatMap { locale in
                    [
                        food.localizedName(locale: locale),
                        food.localizedDisplayName(locale: locale),
                    ]
                }
            return (food.id, Array(Set(names.map(normalized))))
        })
    }()

    private static func normalized(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
    }
}
