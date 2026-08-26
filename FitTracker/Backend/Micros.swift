//
//  Micros.swift
//  FitTracker
//
//  Created by Tomas Salaz on 8/25/26.
//

import SwiftUI

struct MicroTarget: Identifiable {
    let id: Int          // USDA nutrient ID
    let name: String
    let unit: String
    let rda: Double
    var isCeiling: Bool = false   // true = stay under (e.g. sodium)
}

enum Micros {
    static let tracked: [MicroTarget] = [
        .init(id: Nutrient.fiber,      name: "Fiber",       unit: "g",  rda: 38),
        .init(id: Nutrient.calcium,    name: "Calcium",     unit: "mg", rda: 1000),
        .init(id: Nutrient.iron,       name: "Iron",        unit: "mg", rda: 8),
        .init(id: Nutrient.magnesium,  name: "Magnesium",   unit: "mg", rda: 400),
        .init(id: Nutrient.potassium,  name: "Potassium",   unit: "mg", rda: 3400),
        .init(id: Nutrient.zinc,       name: "Zinc",        unit: "mg", rda: 11),
        .init(id: Nutrient.sodium,     name: "Sodium",      unit: "mg", rda: 2300, isCeiling: true),
        .init(id: Nutrient.vitaminC,   name: "Vitamin C",   unit: "mg", rda: 90),
        .init(id: Nutrient.vitaminD,   name: "Vitamin D",   unit: "µg", rda: 20),
        .init(id: Nutrient.vitaminA,   name: "Vitamin A",   unit: "µg", rda: 900),
        .init(id: Nutrient.b6,         name: "Vitamin B6",  unit: "mg", rda: 1.3),
        .init(id: Nutrient.b12,        name: "Vitamin B12", unit: "µg", rda: 2.4),
        .init(id: Nutrient.folate,     name: "Folate",      unit: "µg", rda: 400),
        .init(id: Nutrient.choline,    name: "Choline",     unit: "mg", rda: 550)
    ]
}

struct MicroPanel: View {
    let entries: [FoodEntry]

    private func total(_ id: Int) -> Double {
        entries.reduce(0) { $0 + ($1.food?.amount(of: id, grams: $1.grams) ?? 0) }
    }

    var body: some View {
        ForEach(Micros.tracked) { t in
            let amount = total(t.id)
            let pct = t.rda > 0 ? amount / t.rda : 0

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(t.name)
                        .font(.callout)
                    Spacer()
                    Text(format(amount) + t.unit)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("\(Int(pct * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 46, alignment: .trailing)
                }
                ProgressView(value: min(pct, 1.0))
                    .tint(color(for: t, pct: pct))
            }
            .padding(.vertical, 2)
        }
    }

    private func format(_ v: Double) -> String {
        v < 10
            ? String(format: "%.1f", v)
            : String(Int(v.rounded()))
    }

    private func color(for t: MicroTarget, pct: Double) -> Color {
        if t.isCeiling { return pct > 1.0 ? .red : .green }
        switch pct {
        case ..<0.5: return .red
        case ..<0.9: return .orange
        default:     return .green
        }
    }
}
