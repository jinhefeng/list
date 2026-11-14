import Foundation

/// Offline, intentionally broad estimates. These are NOT measured brand recipes.
/// Values are per 100 ml (drinks) or per 100 g (foods), rounded when displayed.
public enum RoughNutritionEstimator {
    private struct Profile {
        let label: String
        let energy: Double
        let sugar: Double
        let caffeine: Double
        let protein: Double
        let fat: Double
        let carbohydrate: Double
    }

    private static func drinkProfile(name: String, category: String) -> Profile {
        let text = (name + " " + category).lowercased()
        if matches(text, ["矿泉水", "纯净水", "白开水", "饮用水", "无糖气泡水", "water"]) {
            return Profile(label: "无糖饮用水", energy: 0, sugar: 0, caffeine: 0, protein: 0, fat: 0, carbohydrate: 0)
        }
        if matches(text, ["无糖可乐", "零度可乐", "零糖可乐", "zero cola", "coke zero", "无糖雪碧"]) {
            return Profile(label: "无糖汽水", energy: 1, sugar: 0, caffeine: 8, protein: 0, fat: 0, carbohydrate: 0)
        }
        if matches(text, ["可乐", "汽水", "雪碧", "芬达", "sprite", "cola"]) {
            return Profile(label: "含糖汽水", energy: 40, sugar: 10, caffeine: 0, protein: 0, fat: 0, carbohydrate: 10)
        }
        if matches(text, ["美式", "冷萃", "浓缩", "黑咖啡", "americano", "espresso", "black coffee"]) {
            return Profile(label: "黑咖啡", energy: 2, sugar: 0, caffeine: 35, protein: 0.2, fat: 0, carbohydrate: 0.2)
        }
        if matches(text, ["拿铁", "卡布奇诺", "摩卡", "馥芮白", "奶咖", "latte", "cappuccino"]) {
            return Profile(label: "奶咖", energy: 55, sugar: 5, caffeine: 20, protein: 2.3, fat: 2.4, carbohydrate: 6)
        }
        if matches(text, ["咖啡", "coffee"]) {
            return Profile(label: "普通咖啡", energy: 5, sugar: 0, caffeine: 30, protein: 0.3, fat: 0, carbohydrate: 0.6)
        }
        if matches(text, ["奶茶", "鲜奶", "厚乳", "牛乳", "椰奶", "奶绿", "奶盖", "珍珠", "芋泥"]) {
            return Profile(label: "奶茶类", energy: 65, sugar: 7, caffeine: 12, protein: 1.5, fat: 2.5, carbohydrate: 9)
        }
        if matches(text, ["果茶", "果汁", "葡萄", "柠檬", "百香果", "桃", "橙", "芒果", "草莓"]) {
            return Profile(label: "果茶/果汁类", energy: 42, sugar: 9, caffeine: 5, protein: 0.2, fat: 0.1, carbohydrate: 10)
        }
        if matches(text, ["奶昔", "冰沙", "果昔", "酸奶", "smoothie"]) {
            return Profile(label: "奶昔/酸奶类", energy: 85, sugar: 10, caffeine: 0, protein: 2, fat: 3, carbohydrate: 13)
        }
        if matches(text, ["绿茶", "红茶", "乌龙", "茉莉", "纯茶", "普洱", "茶"]) {
            return Profile(label: "纯茶类", energy: 2, sugar: 0, caffeine: 15, protein: 0, fat: 0, carbohydrate: 0.2)
        }
        return Profile(label: "未明确分类的饮品", energy: 45, sugar: 6, caffeine: 8, protein: 1, fat: 1, carbohydrate: 8)
    }

    /// Sweetness labels are NOT standardized between brands. This modifies only
    /// estimated ADDED sugar; intrinsic sugar remains, so 无糖 does not imply 0g total sugar.
    private static func addedSugarFactor(_ value: String) -> Double {
        if matches(value, ["不加糖", "无糖", "零糖", "0糖"]) { return 0 }
        if matches(value, ["三分", "少糖", "微糖"]) { return 0.3 }
        if matches(value, ["五分", "半糖"]) { return 0.5 }
        if matches(value, ["七分"]) { return 0.7 }
        if matches(value, ["全糖", "正常糖", "标准糖"]) { return 1 }
        return 0.5
    }

    private static func matches(_ text: String, _ terms: [String]) -> Bool {
        terms.contains(where: { text.localizedCaseInsensitiveContains($0) })
    }

    public static func drink(
        name: String,
        category: String = "",
        sizeML: Int? = nil,
        cupType: String = "",
        sweetness: String = "",
        temperature: String = "",
        ice: String = ""
    ) -> NutritionSnapshot {
        let profile = drinkProfile(name: name, category: category)
        let guessedSize: Int
        if let sizeML, (50...3000).contains(sizeML) {
            guessedSize = sizeML
        } else if cupType.contains("超大") { guessedSize = 700 }
        else if cupType.contains("大") { guessedSize = 600 }
        else if cupType.contains("小") { guessedSize = 350 }
        else { guessedSize = 500 }

        let intrinsicallyUnsweetened = ["黑咖啡", "普通咖啡", "纯茶类"].contains(profile.label)
        let fixedFormula = ["无糖饮用水", "无糖汽水", "含糖汽水"].contains(profile.label)
        let defaultAddedSugar = (!fixedFormula && !intrinsicallyUnsweetened) ? 2.5 : 0
        let addedSugar = fixedFormula ? 0
            : ((intrinsicallyUnsweetened && sweetness.isEmpty) ? 0 : 5 * addedSugarFactor(sweetness))
        let multiplier = Double(guessedSize) / 100
        let sugar = max(0, profile.sugar + addedSugar - defaultAddedSugar)
        let energy = max(0, profile.energy + 4 * (addedSugar - defaultAddedSugar))
        let sweetnessAssumption = sweetness.isEmpty
            ? (intrinsicallyUnsweetened ? "默认不额外加糖" : "甜度按五分糖")
            : "甜度按用户选择（各品牌比例不一致）"
        let assumptions = "\(profile.label)类比；\(guessedSize) ml\(sizeML == nil ? "（容量假定）" : "")；\(sweetnessAssumption)；冰量不用于直接缩放营养"
        return NutritionSnapshot(
            energyKcal: rounded(energy * multiplier, to: 10),
            sugarGrams: rounded(sugar * multiplier, to: 5),
            caffeineMilligrams: rounded(profile.caffeine * multiplier, to: 10),
            confidence: .rough,
            source: "离线饮品分类粗估（非品牌配方）",
            proteinGrams: rounded(profile.protein * multiplier, to: 1),
            fatGrams: rounded(profile.fat * multiplier, to: 1),
            carbohydrateGrams: rounded(max(0, profile.carbohydrate + addedSugar - defaultAddedSugar) * multiplier, to: 1),
            assumptions: assumptions
        )
    }

    /// Food category heuristics use a plausible default serving and are never official.
    public static func dish(name: String, estimatedGrams: Double? = nil) -> NutritionSnapshot {
        let text = name.lowercased()
        let profile: Profile
        let defaultGrams: Double
        if matches(text, ["米饭", "白饭", "炒饭", "盖饭", "便当"]) {
            profile = Profile(label: "米饭/盖饭", energy: 170, sugar: 1, caffeine: 0, protein: 4.5, fat: 4, carbohydrate: 29)
            defaultGrams = 350
        } else if matches(text, ["面条", "拉面", "拌面", "炒面", "意面", "米线"]) {
            profile = Profile(label: "面食", energy: 160, sugar: 2, caffeine: 0, protein: 6, fat: 4, carbohydrate: 26)
            defaultGrams = 350
        } else if matches(text, ["饺子", "馄饨", "包子", "烧卖"]) {
            profile = Profile(label: "带馅面食", energy: 210, sugar: 2, caffeine: 0, protein: 8, fat: 8, carbohydrate: 27)
            defaultGrams = 250
        } else if matches(text, ["汤", "粥", "羹"]) {
            profile = Profile(label: "汤/粥", energy: 65, sugar: 1, caffeine: 0, protein: 3, fat: 2, carbohydrate: 9)
            defaultGrams = 350
        } else if matches(text, ["沙拉", "青菜", "蔬菜", "西兰花"]) {
            profile = Profile(label: "蔬菜菜品", energy: 70, sugar: 2, caffeine: 0, protein: 2, fat: 5, carbohydrate: 6)
            defaultGrams = 250
        } else if matches(text, ["蛋糕", "甜点", "甜品", "面包"]) {
            profile = Profile(label: "烘焙甜品", energy: 310, sugar: 22, caffeine: 0, protein: 5, fat: 15, carbohydrate: 39)
            defaultGrams = 130
        } else if matches(text, ["鸡", "鸭", "牛肉", "猪", "排骨", "鱼", "虾", "肉"]) {
            profile = Profile(label: "肉类菜品", energy: 205, sugar: 3, caffeine: 0, protein: 18, fat: 12, carbohydrate: 5)
            defaultGrams = 250
        } else {
            profile = Profile(label: "常见混合菜品", energy: 170, sugar: 4, caffeine: 0, protein: 8, fat: 8, carbohydrate: 17)
            defaultGrams = 250
        }
        let grams = (estimatedGrams != nil && (20...3000).contains(estimatedGrams!)) ? estimatedGrams! : defaultGrams
        let factor = grams / 100
        return NutritionSnapshot(
            energyKcal: rounded(profile.energy * factor, to: 10),
            sugarGrams: rounded(profile.sugar * factor, to: 5),
            caffeineMilligrams: rounded(profile.caffeine * factor, to: 10),
            confidence: .rough,
            source: "离线菜品分类粗估（非实测）",
            proteinGrams: rounded(profile.protein * factor, to: 1),
            fatGrams: rounded(profile.fat * factor, to: 1),
            carbohydrateGrams: rounded(profile.carbohydrate * factor, to: 1),
            assumptions: "\(profile.label)；\(Int(grams)) g\(estimatedGrams == nil ? "（默认份量）" : "（估计份量）")；烹调用油及配料不确定"
        )
    }

    private static func rounded(_ value: Double, to step: Double) -> Double {
        (value / step).rounded() * step
    }
}
