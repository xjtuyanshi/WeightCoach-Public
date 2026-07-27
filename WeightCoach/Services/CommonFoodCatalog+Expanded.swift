import Foundation

extension CommonFoodCatalog {
    /// 第二批 USDA FoodData Central 常见食物。
    /// 所有数值均为每 100 克可食部分；名称和状态避免混用生重、熟重与额外用油。
    static let additionalFoods: [CommonFoodReference] = [
        CommonFoodReference(
            id: "watermelon-raw",
            name: "西瓜",
            aliases: ["西瓜肉", "watermelon"],
            preparation: "生、去皮，可食果肉",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 30,
                proteinG: 0.61,
                carbohydratesG: 7.55,
                fatG: 0.15,
                fiberG: 0.4
            ),
            fdcID: 167765
        ),
        CommonFoodReference(
            id: "strawberry-raw",
            name: "草莓",
            aliases: ["strawberry", "strawberries"],
            preparation: "生、去蒂，可食部分",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 32,
                proteinG: 0.67,
                carbohydratesG: 7.68,
                fatG: 0.3,
                fiberG: 2
            ),
            fdcID: 167762
        ),
        CommonFoodReference(
            id: "blueberry-raw",
            name: "蓝莓",
            aliases: ["blueberry", "blueberries"],
            preparation: "生，可食部分",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 57,
                proteinG: 0.74,
                carbohydratesG: 14.49,
                fatG: 0.33,
                fiberG: 2.4
            ),
            fdcID: 171711
        ),
        CommonFoodReference(
            id: "grapes-raw",
            name: "葡萄",
            aliases: ["提子", "红葡萄", "绿葡萄", "grape", "grapes"],
            preparation: "红或绿葡萄，生、可食部分",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 69,
                proteinG: 0.72,
                carbohydratesG: 18.1,
                fatG: 0.16,
                fiberG: 0.9
            ),
            fdcID: 174683
        ),
        CommonFoodReference(
            id: "orange-raw",
            name: "橙子",
            aliases: ["橙", "甜橙", "orange", "oranges"],
            preparation: "生、去皮，可食部分",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 47,
                proteinG: 0.94,
                carbohydratesG: 11.75,
                fatG: 0.12,
                fiberG: 2.4
            ),
            fdcID: 169097
        ),
        CommonFoodReference(
            id: "pineapple-raw",
            name: "菠萝",
            aliases: ["凤梨", "pineapple"],
            preparation: "生、去皮，可食果肉",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 50,
                proteinG: 0.54,
                carbohydratesG: 13.12,
                fatG: 0.12,
                fiberG: 1.4
            ),
            fdcID: 169124
        ),
        CommonFoodReference(
            id: "mango-raw",
            name: "芒果",
            aliases: ["mango", "mangos"],
            preparation: "生、去皮去核，可食果肉",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 60,
                proteinG: 0.82,
                carbohydratesG: 14.98,
                fatG: 0.38,
                fiberG: 1.6
            ),
            fdcID: 169910
        ),
        CommonFoodReference(
            id: "sweet-potato-baked",
            name: "烤红薯",
            aliases: ["红薯", "地瓜", "甘薯", "sweet potato", "baked sweet potato"],
            preparation: "连皮烤熟后取果肉、无盐，不含额外用油",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 90,
                proteinG: 2.01,
                carbohydratesG: 20.71,
                fatG: 0.15,
                fiberG: 3.3
            ),
            fdcID: 168483
        ),
        CommonFoodReference(
            id: "potato-baked",
            name: "烤土豆",
            aliases: ["土豆", "马铃薯", "baked potato", "potato"],
            preparation: "带皮烤熟、无盐，不含额外用油",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 93,
                proteinG: 2.5,
                carbohydratesG: 21.15,
                fatG: 0.13,
                fiberG: 2.2
            ),
            fdcID: 170093
        ),
        CommonFoodReference(
            id: "sweet-corn-cooked",
            name: "甜玉米",
            aliases: ["玉米", "玉米粒", "sweet corn", "corn"],
            preparation: "黄甜玉米、煮熟沥干、无盐，不含额外用油",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 96,
                proteinG: 3.41,
                carbohydratesG: 20.98,
                fatG: 1.5,
                fiberG: 2.4
            ),
            fdcID: 169999
        ),
        CommonFoodReference(
            id: "oatmeal-cooked",
            name: "燕麦粥",
            aliases: ["燕麦", "麦片粥", "oatmeal", "cooked oats"],
            preparation: "普通或快熟燕麦、加水煮熟、无盐",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 71,
                proteinG: 2.54,
                carbohydratesG: 12,
                fatG: 1.52,
                fiberG: 1.7
            ),
            fdcID: 173905
        ),
        CommonFoodReference(
            id: "quinoa-cooked",
            name: "熟藜麦",
            aliases: ["藜麦", "quinoa", "cooked quinoa"],
            preparation: "水煮熟，不含额外用油",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 120,
                proteinG: 4.4,
                carbohydratesG: 21.3,
                fatG: 1.92,
                fiberG: 2.8
            ),
            fdcID: 168917
        ),
        CommonFoodReference(
            id: "brown-rice-cooked",
            name: "糙米饭",
            aliases: ["糙米", "brown rice", "cooked brown rice"],
            preparation: "长粒糙米、熟，不含额外用油",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 123,
                proteinG: 2.74,
                carbohydratesG: 25.58,
                fatG: 0.97,
                fiberG: 1.6
            ),
            fdcID: 169704
        ),
        CommonFoodReference(
            id: "black-beans-cooked",
            name: "熟黑豆",
            aliases: ["黑豆", "black beans", "cooked black beans"],
            preparation: "干黑豆煮熟、无盐",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 132,
                proteinG: 8.86,
                carbohydratesG: 23.71,
                fatG: 0.54,
                fiberG: 8.7
            ),
            fdcID: 173735
        ),
        CommonFoodReference(
            id: "lentils-cooked",
            name: "熟扁豆",
            aliases: ["扁豆", "兵豆", "lentils", "cooked lentils"],
            preparation: "成熟扁豆煮熟、无盐",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 116,
                proteinG: 9.02,
                carbohydratesG: 20.13,
                fatG: 0.38,
                fiberG: 7.9
            ),
            fdcID: 172421
        ),
        CommonFoodReference(
            id: "chickpeas-cooked",
            name: "熟鹰嘴豆",
            aliases: ["鹰嘴豆", "鸡豆", "chickpeas", "garbanzo beans"],
            preparation: "煮熟、无盐",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 164,
                proteinG: 8.86,
                carbohydratesG: 27.42,
                fatG: 2.59,
                fiberG: 7.6
            ),
            fdcID: 173757
        ),
        CommonFoodReference(
            id: "edamame-cooked",
            name: "毛豆仁",
            aliases: ["毛豆", "青大豆", "edamame", "green soybeans"],
            preparation: "青大豆煮熟沥干、无盐，不含豆荚",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 141,
                proteinG: 12.35,
                carbohydratesG: 11.05,
                fatG: 6.4,
                fiberG: 4.2
            ),
            fdcID: 169283
        ),
        CommonFoodReference(
            id: "asparagus-cooked",
            name: "熟芦笋",
            aliases: ["芦笋", "asparagus", "cooked asparagus"],
            preparation: "煮熟沥干，不含额外用油",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 22,
                proteinG: 2.4,
                carbohydratesG: 4.11,
                fatG: 0.22,
                fiberG: 2
            ),
            fdcID: 168390
        ),
        CommonFoodReference(
            id: "green-beans-cooked",
            name: "熟四季豆",
            aliases: ["四季豆", "青豆角", "菜豆", "green beans", "string beans"],
            preparation: "煮熟沥干、无盐，不含额外用油",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 35,
                proteinG: 1.89,
                carbohydratesG: 7.88,
                fatG: 0.28,
                fiberG: 3.2
            ),
            fdcID: 169141
        ),
        CommonFoodReference(
            id: "cabbage-raw",
            name: "卷心菜",
            aliases: ["包菜", "圆白菜", "高丽菜", "cabbage"],
            preparation: "生，可食部分",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 25,
                proteinG: 1.28,
                carbohydratesG: 5.8,
                fatG: 0.1,
                fiberG: 2.5
            ),
            fdcID: 169975
        ),
        CommonFoodReference(
            id: "cucumber-raw",
            name: "黄瓜",
            aliases: ["青瓜", "cucumber"],
            preparation: "生、带皮，可食部分",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 15,
                proteinG: 0.65,
                carbohydratesG: 3.63,
                fatG: 0.11,
                fiberG: 0.5
            ),
            fdcID: 168409
        ),
        CommonFoodReference(
            id: "tomato-raw",
            name: "西红柿",
            aliases: ["番茄", "tomato", "tomatoes"],
            preparation: "红色成熟番茄，生、可食部分",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 18,
                proteinG: 0.88,
                carbohydratesG: 3.89,
                fatG: 0.2,
                fiberG: 1.2
            ),
            fdcID: 170457
        ),
        CommonFoodReference(
            id: "white-mushroom-cooked",
            name: "熟白蘑菇",
            aliases: ["蘑菇", "口蘑", "白蘑菇", "white mushroom", "button mushroom"],
            preparation: "煮熟沥干、无盐，不含额外用油",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 28,
                proteinG: 2.17,
                carbohydratesG: 5.29,
                fatG: 0.47,
                fiberG: 2.2
            ),
            fdcID: 169252
        ),
        CommonFoodReference(
            id: "cauliflower-cooked",
            name: "熟花椰菜",
            aliases: ["菜花", "白花椰菜", "cauliflower"],
            preparation: "煮熟沥干、无盐，不含额外用油",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 23,
                proteinG: 1.84,
                carbohydratesG: 4.11,
                fatG: 0.45,
                fiberG: 2.3
            ),
            fdcID: 170397
        ),
        CommonFoodReference(
            id: "red-bell-pepper-raw",
            name: "红甜椒",
            aliases: ["红彩椒", "红椒", "red bell pepper", "sweet red pepper"],
            preparation: "生，可食部分",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 26,
                proteinG: 0.99,
                carbohydratesG: 6.03,
                fatG: 0.3,
                fiberG: 2.1
            ),
            fdcID: 170108
        ),
        CommonFoodReference(
            id: "ground-turkey-cooked",
            name: "熟火鸡肉末",
            aliases: ["火鸡肉馅", "火鸡碎肉", "ground turkey", "cooked ground turkey"],
            preparation: "肉末熟制，不含额外用油",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 203,
                proteinG: 27.37,
                carbohydratesG: 0,
                fatG: 10.4,
                fiberG: 0
            ),
            fdcID: 171506
        ),
        CommonFoodReference(
            id: "ground-beef-93-cooked",
            name: "93% 瘦牛肉饼",
            aliases: ["瘦牛肉末", "牛肉饼", "93 lean beef", "ground beef"],
            preparation: "93% 瘦、7% 脂，烤熟，不含额外用油",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 193,
                proteinG: 26.22,
                carbohydratesG: 0,
                fatG: 8.94,
                fiberG: 0
            ),
            fdcID: 174752
        ),
        CommonFoodReference(
            id: "pork-tenderloin-roasted",
            name: "烤猪里脊",
            aliases: ["猪里脊", "猪柳", "pork tenderloin", "roasted pork tenderloin"],
            preparation: "可分离纯瘦肉、烤熟，不含额外用油",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 143,
                proteinG: 26.17,
                carbohydratesG: 0,
                fatG: 3.51,
                fiberG: 0
            ),
            fdcID: 168250
        ),
        CommonFoodReference(
            id: "tuna-water-canned",
            name: "水浸金枪鱼",
            aliases: ["金枪鱼罐头", "吞拿鱼", "水浸吞拿鱼", "canned tuna", "tuna in water"],
            preparation: "淡金枪鱼罐头、水浸、无盐、沥干固形物",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 116,
                proteinG: 25.51,
                carbohydratesG: 0,
                fatG: 0.82,
                fiberG: 0
            ),
            fdcID: 171986
        ),
        CommonFoodReference(
            id: "tilapia-cooked",
            name: "熟罗非鱼",
            aliases: ["罗非鱼", "吴郭鱼", "tilapia", "cooked tilapia"],
            preparation: "干热熟制，不含额外用油",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 128,
                proteinG: 26.15,
                carbohydratesG: 0,
                fatG: 2.65,
                fiberG: 0
            ),
            fdcID: 175177
        ),
        CommonFoodReference(
            id: "pasta-cooked",
            name: "熟面条",
            aliases: ["面条", "意大利面", "pasta", "cooked pasta", "noodles"],
            preparation: "强化小麦面食、煮熟、无盐，不含额外用油或酱汁",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 158,
                proteinG: 5.8,
                carbohydratesG: 30.9,
                fatG: 0.93,
                fiberG: 1.8
            ),
            fdcID: 169737
        ),
        CommonFoodReference(
            id: "whole-wheat-bread",
            name: "全麦面包",
            aliases: ["全麦吐司", "whole wheat bread", "whole-wheat bread"],
            preparation: "市售成品，按实际可食重量",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 252,
                proteinG: 12.4,
                carbohydratesG: 42.7,
                fatG: 3.5,
                fiberG: 6
            ),
            fdcID: 172688
        ),
        CommonFoodReference(
            id: "whole-milk",
            name: "全脂牛奶",
            aliases: ["牛奶", "全脂奶", "whole milk"],
            preparation: "3.25% 乳脂、添加维生素 D，按实际重量",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 61,
                proteinG: 3.15,
                carbohydratesG: 4.8,
                fatG: 3.25,
                fiberG: 0
            ),
            fdcID: 171265
        ),
        CommonFoodReference(
            id: "cola-regular",
            name: "普通可乐",
            aliases: ["可乐", "含糖可乐", "cola", "regular cola"],
            preparation: "含糖碳酸饮料，按实际重量；品牌配方可能不同",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 42,
                proteinG: 0,
                carbohydratesG: 10.4,
                fatG: 0.25,
                fiberG: 0
            ),
            fdcID: 174852
        ),
        CommonFoodReference(
            id: "latte-hot-2-percent-unsweetened",
            name: "无糖热拿铁（2% 牛奶）",
            aliases: ["拿铁", "无糖拿铁", "热拿铁", "latte", "cafe latte"],
            preparation: "2 份浓缩咖啡加 10 液盎司 2% 牛奶，不含糖浆",
            nutritionPer100Grams: NutritionValues(
                energyKcal: 43,
                proteinG: 2.81,
                carbohydratesG: 4.35,
                fatG: 1.61,
                fiberG: 0
            ),
            fdcID: 2710386
        )
    ]
}
