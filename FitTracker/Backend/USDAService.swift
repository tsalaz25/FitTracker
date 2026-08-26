//
//  USDAService.swift
//  FitTracker
//
//  Created by Tomas Salaz on 8/25/26.
//

import Foundation

// MARK: - Nutrient IDs

enum Nutrient {
    // Macros
    static let calories = 1008
    static let protein  = 1003
    static let fat      = 1004
    static let carbs    = 1005
    static let fiber    = 1079
    static let sugars   = 2000

    // Minerals
    static let calcium   = 1087
    static let iron      = 1089
    static let magnesium = 1090
    static let phosphorus = 1091
    static let potassium = 1092
    static let sodium    = 1093
    static let zinc      = 1095

    // Vitamins
    static let vitaminA  = 1106
    static let vitaminC  = 1162
    static let vitaminD  = 1114
    static let vitaminE  = 1109
    static let vitaminK  = 1185
    static let thiamin   = 1165
    static let riboflavin = 1166
    static let niacin    = 1167
    static let b6        = 1175
    static let folate    = 1177
    static let b12       = 1178
    static let choline   = 1180
}

// MARK: - Errors

enum USDAError: Error, LocalizedError {
    case badResponse(Int)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .badResponse(let code):
            switch code {
            case 403: return "Bad API key — check API.usdaAPIKey."
            case 429: return "Rate limited. Wait an hour and try again."
            default:  return "USDA returned status \(code)."
            }
        case .decoding(let detail):
            return "Couldn't read response: \(detail)"
        }
    }
}

private func describe(_ error: Error) -> String {
    guard let e = error as? DecodingError else { return error.localizedDescription }
    func path(_ ctx: DecodingError.Context) -> String {
        ctx.codingPath.map(\.stringValue).joined(separator: ".")
    }
    switch e {
    case .keyNotFound(let key, let ctx):
        return "missing '\(key.stringValue)' at [\(path(ctx))]"
    case .typeMismatch(let type, let ctx):
        return "expected \(type) at [\(path(ctx))]"
    case .valueNotFound(let type, let ctx):
        return "null \(type) at [\(path(ctx))]"
    case .dataCorrupted(let ctx):
        return "corrupted at [\(path(ctx))]"
    @unknown default:
        return String(describing: e)
    }
}

// MARK: - Wire format

private struct SearchResponse: Decodable {
    let foods: [SearchFood]?
}

private struct SearchFood: Decodable {
    let fdcId: Int
    let description: String?
    let brandName: String?
    let brandOwner: String?
    let dataType: String?
}

private struct DetailFood: Decodable {
    let fdcId: Int?
    let description: String?
    let brandName: String?
    let foodNutrients: [FlexNutrient]?
    let servingSize: Double?
    let servingSizeUnit: String?
    let householdServingFullText: String?
    let foodPortions: [FoodPortion]?
}

private struct FoodPortion: Decodable {
    struct MeasureUnit: Decodable { let name: String? }
    let amount: Double?
    let modifier: String?
    let gramWeight: Double?
    let measureUnit: MeasureUnit?
}

/// USDA returns nutrients in more than one shape depending on data type.
/// Handles both {"nutrient":{"id":1008},"amount":52}
/// and         {"nutrientId":1008,"value":52}
private struct FlexNutrient: Decodable {
    let id: Int?
    let value: Double?

    private struct Inner: Decodable {
        let id: Int?
        let number: String?
    }

    private enum Keys: String, CodingKey {
        case nutrient, amount, nutrientId, value
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let inner = try? c.decodeIfPresent(Inner.self, forKey: .nutrient)

        var resolvedID: Int? = inner?.id
        if resolvedID == nil {
            resolvedID = try? c.decodeIfPresent(Int.self, forKey: .nutrientId)
        }
        if resolvedID == nil, let num = inner?.number {
            resolvedID = Int(num)
        }
        id = resolvedID

        var resolvedValue = try? c.decodeIfPresent(Double.self, forKey: .amount)
        if resolvedValue == nil {
            resolvedValue = try? c.decodeIfPresent(Double.self, forKey: .value)
        }
        value = resolvedValue
    }
}

// MARK: - UI-facing search result

struct FoodSearchResult: Identifiable, Hashable {
    let id: Int
    let name: String
    let brand: String?
    let dataType: String?
}

// MARK: - Service

struct USDAService {
    private static let base = "https://api.nal.usda.gov/fdc/v1"

    static func search(_ query: String) async throws -> [FoodSearchResult] {
        var comps = URLComponents(string: "\(base)/foods/search")!
        comps.queryItems = [
            .init(name: "api_key", value: API.usdaAPIKey),
            .init(name: "query", value: query),
            .init(name: "pageSize", value: "30"),
            .init(name: "dataType", value: "Foundation,SR Legacy,Branded")
        ]

        let (data, resp) = try await URLSession.shared.data(from: comps.url!)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard code == 200 else { throw USDAError.badResponse(code) }

        let decoded: SearchResponse
        do {
            decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        } catch {
            throw USDAError.decoding(describe(error))
        }

        return (decoded.foods ?? []).map {
            FoodSearchResult(id: $0.fdcId,
                             name: ($0.description ?? "Unknown").capitalized,
                             brand: $0.brandName ?? $0.brandOwner,
                             dataType: $0.dataType)
        }
    }

    static func details(fdcID: Int) async throws -> Food {
        var comps = URLComponents(string: "\(base)/food/\(fdcID)")!
        comps.queryItems = [
            .init(name: "api_key", value: API.usdaAPIKey),
            .init(name: "format", value: "full")
        ]

        let (data, resp) = try await URLSession.shared.data(from: comps.url!)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard code == 200 else { throw USDAError.badResponse(code) }

        let d: DetailFood
        do {
            d = try JSONDecoder().decode(DetailFood.self, from: data)
        } catch {
            throw USDAError.decoding(describe(error))
        }

        // Nutrients
        let values: [NutrientValue] = (d.foodNutrients ?? []).compactMap { n in
            guard let id = n.id, let v = n.value, v > 0, id != 1062 else { return nil }
            return NutrientValue(nutrientID: id, amountPer100g: v)
        }

        // Servings
        var servings: [ServingOption] = []

        if let ss = d.servingSize, ss > 0 {
            let unit = (d.servingSizeUnit ?? "g").lowercased()
            if unit == "g" || unit == "ml" {
                let raw = d.householdServingFullText?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                let label = raw.isEmpty ? "1 serving" : raw.capitalized
                servings.append(ServingOption(label: "\(label) (\(Int(ss))g)", grams: ss))
            }
        }

        for p in d.foodPortions ?? [] {
            guard let g = p.gramWeight, g > 0 else { continue }

            let unitName = p.measureUnit?.name
            let unit = (unitName == nil || unitName == "undetermined") ? nil : unitName

            let amountText: String? = p.amount.map { amt in
                amt == amt.rounded() ? String(Int(amt)) : String(format: "%.2g", amt)
            }

            let label = [amountText, unit, p.modifier]
                .compactMap { $0 }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)

            guard !label.isEmpty else { continue }
            servings.append(ServingOption(label: "\(label) (\(Int(g))g)", grams: g))
        }

        var seen = Set<String>()
        servings = servings.filter { seen.insert($0.label).inserted }
        if servings.count > 12 { servings = Array(servings.prefix(12)) }

        // Raw grams always available.
        servings.append(ServingOption(label: "grams", grams: 1))

        return Food(name: (d.description ?? "Unknown").capitalized,
                    brand: d.brandName,
                    fdcID: d.fdcId ?? fdcID,
                    nutrients: values,
                    servings: servings)
    }
}
