//
//  FoodSearchView.swift
//  FitTracker
//
//  Created by Tomas Salaz on 8/25/26.
//

import SwiftUI
import SwiftData

struct FoodSearchView: View {
    let meal: String
    var date: Date = .now

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [FoodSearchResult] = []
    @State private var loading = false
    @State private var errorText: String?

    @State private var pending: Food?
    @State private var quantity = "1"
    @State private var chosenServing: ServingOption?

    var body: some View {
        NavigationStack {
            List {
                if loading {
                    HStack { ProgressView(); Text("Searching…") }
                }
                if let errorText {
                    Text(errorText)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
                ForEach(results) { r in
                    Button {
                        Task { await load(r) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.name)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            HStack(spacing: 4) {
                                if let b = r.brand {
                                    Text(b)
                                }
                                if r.dataType == "Branded" {
                                    Text("· label data")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Add to \(meal)")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search foods")
            .onSubmit(of: .search) { Task { await runSearch() } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(item: $pending) { food in
                portionSheet(food)
            }
        }
    }

    // MARK: - Portion sheet

    @ViewBuilder
    private func portionSheet(_ food: Food) -> some View {
        let options = food.servings.isEmpty
            ? [ServingOption(label: "grams", grams: 1)]
            : food.servings
        let serving = options.first { $0 == chosenServing } ?? options[0]
        let qty = Double(quantity) ?? 0
        let grams = qty * serving.grams

        NavigationStack {
            Form {
                Section {
                    Text(food.name).font(.headline)
                    if let b = food.brand {
                        Text(b).font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Portion") {
                    HStack {
                        TextField("Qty", text: $quantity)
                            .keyboardType(.decimalPad)
                            .frame(width: 70)
                            .textFieldStyle(.roundedBorder)

                        Picker("", selection: Binding(
                            get: { serving },
                            set: { chosenServing = $0 }
                        )) {
                            ForEach(options) { opt in
                                Text(opt.label).tag(opt)
                            }
                        }
                        .labelsHidden()
                    }

                    if serving.grams != 1 {
                        Text("= \(Int(grams)) g")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Nutrition") {
                    nutrientRow("Calories", Nutrient.calories, food, grams, 0)
                    nutrientRow("Protein", Nutrient.protein, food, grams, 1)
                    nutrientRow("Carbs", Nutrient.carbs, food, grams, 1)
                    nutrientRow("Fiber", Nutrient.fiber, food, grams, 1)
                    nutrientRow("Fat", Nutrient.fat, food, grams, 1)
                }
            }
            .navigationTitle("Portion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        log(food, serving: serving, qty: qty, grams: grams)
                    }
                    .disabled(grams <= 0)
                    .bold()
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { reset() }
                }
            }
        }
    }

    private func nutrientRow(_ label: String,
                             _ id: Int,
                             _ food: Food,
                             _ grams: Double,
                             _ digits: Int) -> some View {
        LabeledContent(label,
                       value: food.amount(of: id, grams: grams),
                       format: .number.precision(.fractionLength(digits)))
    }

    // MARK: - Actions

    private func log(_ food: Food, serving: ServingOption, qty: Double, grams: Double) {
        guard grams > 0 else { return }

        // Reuse a previously cached Food rather than duplicating it.
        let stored: Food
        if let existing = existingFood(fdcID: food.fdcID) {
            stored = existing
        } else {
            context.insert(food)
            stored = food
        }

        let entry = FoodEntry(food: stored, grams: grams, meal: meal, date: date)
        entry.servingLabel = serving.label
        entry.servingQuantity = qty
        context.insert(entry)

        reset()
        dismiss()
    }

    private func existingFood(fdcID: Int?) -> Food? {
        guard let fdcID else { return nil }
        let all = (try? context.fetch(FetchDescriptor<Food>())) ?? []
        return all.first { $0.fdcID == fdcID }
    }

    private func reset() {
        pending = nil
        chosenServing = nil
        quantity = "1"
    }

    private func runSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        loading = true
        errorText = nil
        defer { loading = false }
        do {
            results = try await USDAService.search(trimmed)
            if results.isEmpty {
                errorText = "No matches for \"\(trimmed)\"."
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func load(_ r: FoodSearchResult) async {
        errorText = nil
        do {
            let food = try await USDAService.details(fdcID: r.id)
            chosenServing = food.servings.first
            quantity = "1"
            pending = food
        } catch {
            errorText = error.localizedDescription
        }
    }
}
