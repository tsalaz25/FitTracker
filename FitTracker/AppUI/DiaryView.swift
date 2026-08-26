//
//  DiaryView.swift
//  FitTracker
//
//  Created by Tomas Salaz on 8/25/26.
//

import SwiftUI
import SwiftData

struct DiaryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FoodEntry.date) private var allEntries: [FoodEntry]

    @State private var addingTo: String?
    @State private var day = Date.now
    @State private var showMicros = false

    private let meals = ["Breakfast", "Lunch", "Dinner", "Snacks"]

    private var entries: [FoodEntry] {
        allEntries.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
    }

    private func total(_ id: Int) -> Double {
        entries.reduce(0) { $0 + ($1.food?.amount(of: id, grams: $1.grams) ?? 0) }
    }

    var body: some View {
        NavigationStack {
            List {
                dayNavigator

                Section("Totals") {
                    macroRow("Calories", Nutrient.calories, digits: 0)
                    macroRow("Protein", Nutrient.protein, digits: 1)
                    macroRow("Carbs", Nutrient.carbs, digits: 1)
                    macroRow("Fat", Nutrient.fat, digits: 1)
                }

                Section {
                    DisclosureGroup("Micronutrients", isExpanded: $showMicros) {
                        MicroPanel(entries: entries)
                    }
                }

                ForEach(meals, id: \.self) { meal in
                    mealSection(meal)
                }
            }
            .navigationTitle("Diary")
            .sheet(item: $addingTo) { meal in
                FoodSearchView(meal: meal, date: day)
            }
        }
    }

    // MARK: - Pieces

    private var dayNavigator: some View {
        Section {
            HStack {
                Button { shift(-1) } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)

                Spacer()

                Text(Calendar.current.isDateInToday(day)
                     ? "Today"
                     : day.formatted(.dateTime.weekday(.abbreviated).month().day()))
                    .font(.headline)

                Spacer()

                Button { shift(1) } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
                .disabled(Calendar.current.isDateInToday(day))
            }
        }
    }

    private func macroRow(_ label: String, _ id: Int, digits: Int) -> some View {
        LabeledContent(label,
                       value: total(id),
                       format: .number.precision(.fractionLength(digits)))
    }

    private func mealSection(_ meal: String) -> some View {
        let items = entries.filter { $0.meal == meal }

        return Section {
            ForEach(items) { e in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.food?.name ?? "—").lineLimit(1)
                        Text(portionText(e))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(calories(e), format: .number.precision(.fractionLength(0)))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .onDelete { idx in
                for i in idx { context.delete(items[i]) }
            }

            Button("Add food") { addingTo = meal }
                .font(.callout)
        } header: {
            HStack {
                Text(meal)
                Spacer()
                if !items.isEmpty {
                    Text(items.reduce(0) { $0 + calories($1) },
                         format: .number.precision(.fractionLength(0)))
                        .font(.caption.monospacedDigit())
                }
            }
        }
    }

    // MARK: - Helpers

    private func calories(_ e: FoodEntry) -> Double {
        e.food?.amount(of: Nutrient.calories, grams: e.grams) ?? 0
    }

    private func portionText(_ e: FoodEntry) -> String {
        if let label = e.servingLabel, label != "grams", let q = e.servingQuantity {
            let qty = q.formatted(.number.precision(.fractionLength(0...2)))
            return "\(qty) × \(label)"
        }
        return "\(Int(e.grams))g"
    }

    private func shift(_ days: Int) {
        if let d = Calendar.current.date(byAdding: .day, value: days, to: day) {
            day = d
        }
    }
}

// Lets `sheet(item:)` take a meal name directly.
extension String: @retroactive Identifiable {
    public var id: String { self }
}
