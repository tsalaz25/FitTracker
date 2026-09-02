//
//  Models.swift
//  FitTracker
//
//  Created by Tomas Salaz on 8/25/26.
//

import Foundation
import SwiftData

// MARK: - Value types

/// One nutrient reading, keyed by USDA nutrient ID.
struct NutrientValue: Codable, Hashable {
    var nutrientID: Int
    var amountPer100g: Double
}

/// A named portion, e.g. "1 Bar (55g)".
struct ServingOption: Codable, Hashable, Identifiable {
    var label: String
    var grams: Double
    var id: String { "\(label)|\(grams)" }
}

// MARK: - Food

@Model
final class Food {
    var name: String = ""
    var brand: String?
    var fdcID: Int?
    var nutrients: [NutrientValue] = []
    var servings: [ServingOption] = []
    var dateCached: Date = Date.now

    /// Created by hand from a nutrition label rather than pulled from an API.
    var isCustom: Bool = false

    /// Pinned to the top of the food list.
    var isFavorite: Bool = false

    /// Drives the "Recent" list so common foods need no search.
    var lastUsed: Date?
    var useCount: Int = 0

    init(name: String,
         brand: String? = nil,
         fdcID: Int? = nil,
         nutrients: [NutrientValue] = [],
         servings: [ServingOption] = [],
         isCustom: Bool = false) {
        self.name = name
        self.brand = brand
        self.fdcID = fdcID
        self.nutrients = nutrients
        self.servings = servings
        self.isCustom = isCustom
        self.dateCached = .now
    }

    /// Scaled amount of a nutrient for a given gram weight.
    func amount(of nutrientID: Int, grams: Double) -> Double {
        let per100 = nutrients.first { $0.nutrientID == nutrientID }?.amountPer100g ?? 0
        return per100 * grams / 100.0
    }

    /// Sets a nutrient, replacing any existing value for that ID.
    func setNutrient(_ id: Int, per100g: Double) {
        nutrients.removeAll { $0.nutrientID == id }
        guard per100g > 0 else { return }
        nutrients.append(NutrientValue(nutrientID: id, amountPer100g: per100g))
    }

    func per100g(_ id: Int) -> Double {
        nutrients.first { $0.nutrientID == id }?.amountPer100g ?? 0
    }

    func markUsed() {
        lastUsed = .now
        useCount += 1
    }

    var subtitle: String {
        var parts: [String] = []
        if let brand, !brand.isEmpty { parts.append(brand) }
        if isCustom { parts.append("Custom") }
        let kcal = per100g(Nutrient.calories)
        if kcal > 0 { parts.append("\(Int(kcal)) kcal/100g") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Diary entry

@Model
final class FoodEntry {
    var food: Food?
    var grams: Double = 0
    var meal: String = "Breakfast"
    var date: Date = Date.now

    /// Display-only. Grams remains the source of truth for nutrition.
    var servingLabel: String?
    var servingQuantity: Double?

    init(food: Food, grams: Double, meal: String, date: Date = .now) {
        self.food = food
        self.grams = grams
        self.meal = meal
        self.date = date
    }
}

// MARK: - Weight

@Model
final class WeightEntry {
    var pounds: Double = 0
    var date: Date = Date.now

    init(pounds: Double, date: Date = .now) {
        self.pounds = pounds
        self.date = date
    }
}
