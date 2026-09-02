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
    let muscle: String          // Chest, Back, Quads, Cardio, ...
    let equipment: String       // Barbell, Dumbbell, Cable, Machine, ...
    let kind: String            // compound, isolation, cardio
    let secondary: [String]
    let unilateral: Bool

    private enum Keys: String, CodingKey {
        case id, name, muscle, equipment, kind, secondary, unilateral
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id        = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        name      = (try? c.decode(String.self, forKey: .name)) ?? "Unnamed"
        muscle    = (try? c.decode(String.self, forKey: .muscle)) ?? "Other"
        equipment = (try? c.decode(String.self, forKey: .equipment)) ?? "Other"
        kind      = (try? c.decode(String.self, forKey: .kind)) ?? "compound"
        secondary = (try? c.decode([String].self, forKey: .secondary)) ?? []
        unilateral = (try? c.decode(Bool.self, forKey: .unilateral)) ?? false
    }

    var isCardio: Bool { kind == "cardio" }

    /// "Barbell · Compound" — the line under the name in lists.
    var subtitle: String {
        var parts = [equipment]
        if !isCardio { parts.append(kind.capitalized) }
        if unilateral { parts.append("Per side") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Filters

struct ExerciseFilters: Equatable {
    var muscle: String?
    var equipment: String?
    var kind: String?

    var isActive: Bool {
        muscle != nil || equipment != nil || kind != nil
    }

    mutating func clear() {
        muscle = nil
        equipment = nil
        kind = nil
    }

    var summary: String {
        [muscle, equipment, kind?.capitalized]
            .compactMap { $0 }
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
                || ex.muscle.lowercased().contains(q)
                || ex.equipment.lowercased().contains(q)

            let mMuscle = filters.muscle == nil || ex.muscle == filters.muscle!
            let mEquip  = filters.equipment == nil || ex.equipment == filters.equipment!
            let mKind   = filters.kind == nil || ex.kind == filters.kind!

            return matchesText && mMuscle && mEquip && mKind
        }
    }

    func exercise(id: String) -> Exercise? {
        all.first { $0.id == id }
    }

    /// Muscle groups in training order rather than alphabetical.
    var allMuscles: [String] {
        let order = ["Chest", "Back", "Shoulders", "Biceps", "Triceps",
                     "Forearms", "Traps", "Quads", "Hamstrings", "Glutes",
                     "Calves", "Abs", "Cardio"]
        let present = Set(all.map(\.muscle))
        var result = order.filter { present.contains($0) }
        result.append(contentsOf: present.subtracting(order).sorted())
        return result
    }

    var allEquipment: [String] { Set(all.map(\.equipment)).sorted() }
    var allKinds: [String] {
        ["compound", "isolation", "cardio"].filter { k in
            all.contains { $0.kind == k }
        }
    }

    /// Grouped for the browser's section list.
    func grouped(_ exercises: [Exercise]) -> [(muscle: String, items: [Exercise])] {
        let dict = Dictionary(grouping: exercises, by: \.muscle)
        return allMuscles.compactMap { m in
            guard let items = dict[m], !items.isEmpty else { return nil }
            return (muscle: m, items: items.sorted { $0.name < $1.name })
        }
    }
}
