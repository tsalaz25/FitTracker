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

    @Query private var savedFoods: [Food]

    @State private var query = ""
    @State private var results: [FoodSearchResult] = []
    @State private var loading = false
    @State private var errorText: String?
    @State private var searched = false

    @State private var pending: Food?
    @State private var quantity = "1"
    @State private var chosenServing: ServingOption?
    @State private var creatingCustom = false

    // MARK: - Local lists

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    private var localMatches: [Food] {
        let q = trimmedQuery.lowercased()
        guard !q.isEmpty else { return [] }
        return savedFoods
            .filter { $0.name.lowercased().contains(q)
                   || ($0.brand?.lowercased().contains(q) ?? false) }
            .sorted { $0.useCount > $1.useCount }
    }

    private var favorites: [Food] {
        savedFoods.filter(\.isFavorite)
            .sorted { $0.name < $1.name }
    }

    private var recents: [Food] {
        savedFoods
            .filter { $0.lastUsed != nil && !$0.isFavorite }
            .sorted { ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast) }
            .prefix(12)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorText {
                    Text(errorText)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }

                if trimmedQuery.isEmpty {
                    if !favorites.isEmpty {
                        Section("Favorites") {
                            ForEach(favorites) { f in localRow(f) }
                        }
                    }
                    if !recents.isEmpty {
                        Section("Recent") {
                            ForEach(recents) { f in localRow(f) }
                        }
                    }
                    Section {
                        Button {
                            creatingCustom = true
                        } label: {
                            Label("Create custom food", systemImage: "plus")
                        }
                    } footer: {
                        if favorites.isEmpty && recents.isEmpty {
                            Text("Search for a food, or build one by hand from a nutrition label.")
                        }
                    }
                } else {
                    if !localMatches.isEmpty {
                        Section("My foods") {
                            ForEach(localMatches) { f in localRow(f) }
                        }
                    }

                    Section {
                        if loading {
                            HStack { ProgressView(); Text("Searching…") }
                        }
                        ForEach(results) { r in
                            Button {
                                Task { await load(r) }
                            } label: {
                                remoteRow(r)
                            }
                        }
                        if searched && !loading && results.isEmpty {
                            Button {
                                creatingCustom = true
                            } label: {
                                Label("Create it manually", systemImage: "plus")
                            }
                        }
                    } header: {
                        Text(searched ? "Database" : "Press return to search")
                    }
                }
            }
            .navigationTitle("Add to \(meal)")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search foods")
            .keyboardDoneBar()
            .onSubmit(of: .search) { Task { await runSearch() } }
            .onChange(of: query) { _, newValue in
                if newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                    results = []
                    searched = false
                    errorText = nil
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        creatingCustom = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $pending) { food in
                portionSheet(food)
            }
            .sheet(isPresented: $creatingCustom) {
                CustomFoodEditor { food in
                    // Jump straight to logging the food just created.
                    chosenServing = food.servings.first
                    quantity = "1"
                    pending = food
                }
            }
        }
    }

    // MARK: - Rows

    private func localRow(_ f: Food) -> some View {
        Button {
            chosenServing = f.servings.first
            quantity = "1"
            pending = f
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(f.name)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(f.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if f.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                f.isFavorite.toggle()
            } label: {
                Label("Favorite", systemImage: f.isFavorite ? "star.slash" : "star")
            }
            .tint(.yellow)
        }
    }

    private func remoteRow(_ r: FoodSearchResult) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(r.name)
                .foregroundStyle(.primary)
                .lineLimit(2)
            HStack(spacing: 4) {
                if let b = r.brand, !b.isEmpty {
                    Text(b)
                }
                if let kcal = r.caloriesPer100g, kcal > 0 {
                    if r.brand != nil { Text("·") }
                    Text("\(Int(kcal)) kcal/100g")
                }
                if r.dataType == "Branded" {
                    Text("· label")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
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
            .keyboardDoneBar()
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

        // Reuse a cached copy rather than duplicating the food.
        let stored: Food
        if let existing = existingFood(matching: food) {
            stored = existing
        } else {
            if food.modelContext == nil { context.insert(food) }
            stored = food
        }

        stored.markUsed()

        let entry = FoodEntry(food: stored, grams: grams, meal: meal, date: date)
        entry.servingLabel = serving.label
        entry.servingQuantity = qty
        context.insert(entry)

        reset()
        dismiss()
    }

    private func existingFood(matching food: Food) -> Food? {
        if food.modelContext != nil { return food }   // already saved
        guard let id = food.fdcID else { return nil }
        return savedFoods.first { $0.fdcID == id }
    }

    private func reset() {
        pending = nil
        chosenServing = nil
        quantity = "1"
    }

    private func runSearch() async {
        let trimmed = trimmedQuery
        guard !trimmed.isEmpty else { return }
        loading = true
        errorText = nil
        defer { loading = false; searched = true }
        do {
            results = try await USDAService.search(trimmed)
        } catch {
            errorText = error.localizedDescription
            results = []
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
