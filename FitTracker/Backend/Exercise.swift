//
//  Exercise.swift
//  FitTracker
//
//  Created by Tomas Salaz on 8/25/26.
//

import Foundation

struct Exercise: Identifiable, Hashable, Decodable {
    let id: String
    let name: String
    let force: String?
    let level: String?
    let mechanic: String?
    let equipment: String?
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let instructions: [String]
    let category: String?

    private enum Keys: String, CodingKey {
        case id, name, force, level, mechanic, equipment
        case primaryMuscles, secondaryMuscles, instructions, category
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id   = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? c.decode(String.self, forKey: .name)) ?? "Unnamed"
        force     = try? c.decodeIfPresent(String.self, forKey: .force)
        level     = try? c.decodeIfPresent(String.self, forKey: .level)
        mechanic  = try? c.decodeIfPresent(String.self, forKey: .mechanic)
        equipment = try? c.decodeIfPresent(String.self, forKey: .equipment)
        primaryMuscles   = (try? c.decode([String].self, forKey: .primaryMuscles)) ?? []
        secondaryMuscles = (try? c.decode([String].self, forKey: .secondaryMuscles)) ?? []
        instructions     = (try? c.decode([String].self, forKey: .instructions)) ?? []
        category  = try? c.decodeIfPresent(String.self, forKey: .category)
    }

    var subtitle: String {
        [equipment, primaryMuscles.first]
            .compactMap { $0 }
            .map { $0.capitalized }
            .joined(separator: " · ")
    }

    var isCardio: Bool { category == "cardio" }
}

// MARK: - Filters

struct ExerciseFilters: Equatable {
    var muscle: String?
    var equipment: String?
    var category: String?
    var level: String?

    var isActive: Bool {
        muscle != nil || equipment != nil || category != nil || level != nil
    }

    mutating func clear() {
        muscle = nil
        equipment = nil
        category = nil
        level = nil
    }

    var summary: String {
        [muscle, equipment, category, level]
            .compactMap { $0?.capitalized }
            .joined(separator: " · ")
    }
}

// MARK: - Catalog

@Observable
final class ExerciseCatalog {
    static let shared = ExerciseCatalog()

    private(set) var all: [Exercise] = []
    private(set) var loadError: String?

    private init() { load() }

    private func load() {
        guard let url = Bundle.main.url(forResource: "exercises", withExtension: "json") else {
            loadError = "exercises.json not found in the app bundle. Select the file in Xcode and check Target Membership."
            return
        }
        do {
            let data = try Data(contentsOf: url)
            all = try JSONDecoder()
                .decode([Exercise].self, from: data)
                .sorted { $0.name < $1.name }
        } catch {
            loadError = "Couldn't decode exercises.json: \(error)"
        }
    }

    func search(_ query: String, filters: ExerciseFilters = ExerciseFilters()) -> [Exercise] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return all.filter { ex in
            let matchesText = q.isEmpty
                || ex.name.lowercased().contains(q)
                || ex.primaryMuscles.contains { $0.contains(q) }
                || (ex.equipment?.contains(q) ?? false)

            let mMuscle = filters.muscle == nil || ex.primaryMuscles.contains(filters.muscle!)
            let mEquip  = filters.equipment == nil || ex.equipment == filters.equipment
            let mCat    = filters.category == nil || ex.category == filters.category
            let mLevel  = filters.level == nil || ex.level == filters.level

            return matchesText && mMuscle && mEquip && mCat && mLevel
        }
    }

    func exercise(id: String) -> Exercise? {
        all.first { $0.id == id }
    }

    var allEquipment: [String]  { Set(all.compactMap(\.equipment)).sorted() }
    var allMuscles: [String]    { Set(all.flatMap(\.primaryMuscles)).sorted() }
    var allCategories: [String] { Set(all.compactMap(\.category)).sorted() }
    var allLevels: [String] {
        ["beginner", "intermediate", "expert"].filter { lvl in
            all.contains { $0.level == lvl }
        }
    }
}
