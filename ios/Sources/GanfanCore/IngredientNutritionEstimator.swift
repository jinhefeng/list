import Foundation

public struct EstimatedFoodIngredient: Codable, Equatable, Sendable {
    public let name: String
    public let grams: Double

    public init(name: String, grams: Double) {
        self.name = name
        self.grams = grams
    }
}

/// Ingredient quantities are AI estimates, never exact weights.
/// Per-100g reference values are approximate and intended for offline personal tracking.
public enum IngredientNutritionEstimator {
    private struct Values {
        var energy: Double
        var sugar: Double
        var protein: Double
        var fat: Double
        var carbs: Double
    }

    private static let entries: [(terms: [String], value: Values)] = [
        (["米饭", "熟米饭", "白米饭", "rice"], Values(energy: 130, sugar: 0, protein: 2.7, fat: 0.3, carbs: 28)),
        (["面条", "米线", "面", "noodle"], Values(energy: 140, sugar: 0.6, protein: 5, fat: 1.2, carbs: 27)),
        (["鸡蛋", "蛋", "egg"], Values(energy: 145, sugar: 0.4, protein: 13, fat: 10, carbs: 1)),
        (["鸡肉", "鸡丁", "鸡胸", "鸡腿", "chicken"], Values(energy: 165, sugar: 0, protein: 24, fat: 7, carbs: 0)),
        (["牛肉", "beef"], Values(energy: 240, sugar: 0, protein: 25, fat: 16, carbs: 0)),
        (["猪肉", "五花肉", "pork"], Values(energy: 265, sugar: 0, protein: 18, fat: 22, carbs: 0)),
        (["鱼", "fish"], Values(energy: 120, sugar: 0, protein: 20, fat: 4, carbs: 0)),
        (["虾", "shrimp"], Values(energy: 100, sugar: 0, protein: 21, fat: 1.5, carbs: 0)),
        (["豆腐", "tofu"], Values(energy: 85, sugar: 1, protein: 9, fat: 5, carbs: 2)),
        (["花生", "peanut"], Values(energy: 567, sugar: 5, protein: 26, fat: 49, carbs: 16)),
        (["土豆", "马铃薯", "potato"], Values(energy: 77, sugar: 0.8, protein: 2, fat: 0.1, carbs: 17)),
        (["青菜", "蔬菜", "白菜", "菠菜", "西兰花", "生菜", "胡萝卜", "洋葱", "番茄", "黄瓜", "vegetable"], Values(energy: 28, sugar: 2.5, protein: 1.5, fat: 0.3, carbs: 5)),
        (["奶", "milk"], Values(energy: 61, sugar: 5, protein: 3.2, fat: 3.3, carbs: 5)),
        (["糖", "sugar"], Values(energy: 400, sugar: 100, protein: 0, fat: 0, carbs: 100)),
        (["油", "oil"], Values(energy: 900, sugar: 0, protein: 0, fat: 100, carbs: 0))
    ]

    public static func calculate(dishName: String, ingredients: [EstimatedFoodIngredient]) -> NutritionSnapshot {
        let reasonable = ingredients.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty
            && $0.grams.isFinite && (1...2000).contains($0.grams) }
        guard !reasonable.isEmpty, reasonable.count == ingredients.count,
              reasonable.reduce(0, { $0 + $1.grams }) <= 3000 else {
            return RoughNutritionEstimator.dish(name: dishName)
        }
        var totals = Values(energy: 0, sugar: 0, protein: 0, fat: 0, carbs: 0)
        var unknown: [String] = []
        for ingredient in reasonable {
            let name = ingredient.name.lowercased()
            let match = entries.first { entry in entry.terms.contains {
                name.localizedCaseInsensitiveContains($0)
            }}
            let v: Values
            if let match { v = match.value }
            else {
                unknown.append(ingredient.name)
                v = Values(energy: 160, sugar: 3, protein: 7, fat: 7, carbs: 17)
            }
            let k = ingredient.grams / 100
            totals.energy += v.energy * k
            totals.sugar += v.sugar * k
            totals.protein += v.protein * k
            totals.fat += v.fat * k
            totals.carbs += v.carbs * k
        }
        let assumptions = reasonable.map { "\($0.name) \(Int($0.grams))g" }.joined(separator: "、")
            + (unknown.isEmpty ? "" : "；未识别原料使用通用食材粗估：\(unknown.joined(separator: "、"))")
        return NutritionSnapshot(
            energyKcal: (totals.energy / 10).rounded() * 10,
            sugarGrams: (totals.sugar / 5).rounded() * 5,
            caffeineMilligrams: 0,
            confidence: .rough,
            source: "AI 图片推断食材及重量 + 内置食材粗估",
            proteinGrams: totals.protein.rounded(),
            fatGrams: totals.fat.rounded(),
            carbohydrateGrams: totals.carbs.rounded(),
            assumptions: assumptions + "；油脂和调味料可能存在误差"
        )
    }
}
