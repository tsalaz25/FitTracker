//
//  CustomFoodEditor.swift
//  FitTracker
//
//  Created by Tomas Salaz on 8/27/26.
//

import SwiftUI
import SwiftData

struct CustomFoodEditor: View {
    /// Pass an existing food to edit it; nil creates a new one.
    var editing: Food?
    /// Called with the saved food, so the caller can log it immediately.
    var onSave: ((Food) -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    // Identity
    @State private var name = ""
    @State private var brand = ""

    // Serving
    @State private var servingLabel = "1 serving"
    @State private var servingGrams = "100"

    // Macros, per serving
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fiber = ""
    @State private var sugars = ""
    @State private var fat = ""

    // Micros, per serving. Keyed by USDA nutrient ID.
    @State private var micros: [Int: String] = [:]
    @State private var showMicros = false

    private var grams: Double { Double(servingGrams) ?? 0 }
    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && grams > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Food") {
                    TextField("Name (required)", text: $name)
                    TextField("Brand (optional)", text: $brand)
                }

                Section {
                    TextField("Serving name", text: $servingLabel)
                    HStack {
                        Text("Weight per serving")
                        Spacer()
                        TextField("grams", text: $servingGrams)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .textFieldStyle(.roundedBorder)
                        Text("g").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Serving size")
                } footer: {
                    Text("Enter the serving from the label, e.g. \"1 bar\" and 55 g. All values below are per this serving.")
                }

                Section("Nutrition per serving") {
                    labelRow("Calories", $calories, "kcal")
                    labelRow("Protein", $protein, "g")
                    labelRow("Total carbs", $carbs, "g")
                    labelRow("Fiber", $fiber, "g")
                    labelRow("Sugars", $sugars, "g")
                    labelRow("Total fat", $fat, "g")
                }

                Section {
                    DisclosureGroup("Vitamins & minerals", isExpanded: $showMicros) {
                        ForEach(Micros.tracked) { t in
                            microRow(t)
                        }
                    }
                } footer: {
                    Text("Optional. Most labels only list a few of these — leave the rest blank.")
                }

                if grams > 0, let kcal = Double(calories), kcal > 0 {
                    Section("Computed") {
                        LabeledContent("Per 100 g",
                                       value: "\(Int(kcal / grams * 100)) kcal")
                    }
                }
            }
            .navigationTitle(editing == nil ? "New Food" : "Edit Food")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneBar()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                        .bold()
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { loadIfEditing() }
        }
    }

    // MARK: - Rows

    private func labelRow(_ title: String,
                          _ binding: Binding<String>,
                          _ unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: binding)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .textFieldStyle(.roundedBorder)
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .leading)
        }
    }

    private func microRow(_ t: MicroTarget) -> some View {
        HStack {
            Text(t.name)
                .font(.callout)
            Spacer()
            TextField("0", text: Binding(
                get: { micros[t.id] ?? "" },
                set: { micros[t.id] = $0 }
            ))
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 80)
            .textFieldStyle(.roundedBorder)
            Text(t.unit)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .leading)
        }
    }

    // MARK: - Load / save

    private func loadIfEditing() {
        guard let f = editing else { return }
        name = f.name
        brand = f.brand ?? ""

        // Recover the serving the food was built with, if any.
        if let s = f.servings.first(where: { $0.label != "grams" }) {
            servingLabel = s.label
            servingGrams = String(Int(s.grams))
        }

        let g = Double(servingGrams) ?? 100
        func perServing(_ id: Int) -> String {
            let v = f.amount(of: id, grams: g)
            return v > 0 ? trimmed(v) : ""
        }

        calories = perServing(Nutrient.calories)
        protein  = perServing(Nutrient.protein)
        carbs    = perServing(Nutrient.carbs)
        fiber    = perServing(Nutrient.fiber)
        sugars   = perServing(Nutrient.sugars)
        fat      = perServing(Nutrient.fat)

        for t in Micros.tracked {
            let v = f.amount(of: t.id, grams: g)
            if v > 0 { micros[t.id] = trimmed(v) }
        }
    }

    private func trimmed(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
    }

    private func save() {
        guard grams > 0 else { return }

        let food = editing ?? Food(name: "", isCustom: true)
        food.name = name.trimmingCharacters(in: .whitespaces)
        food.brand = brand.trimmingCharacters(in: .whitespaces).isEmpty
            ? nil
            : brand.trimmingCharacters(in: .whitespaces)
        food.isCustom = true

        // Label values are per serving; store per 100 g.
        func scale(_ text: String) -> Double {
            guard let v = Double(text), v > 0 else { return 0 }
            return v / grams * 100.0
        }

        food.setNutrient(Nutrient.calories, per100g: scale(calories))
        food.setNutrient(Nutrient.protein,  per100g: scale(protein))
        food.setNutrient(Nutrient.carbs,    per100g: scale(carbs))
        food.setNutrient(Nutrient.fiber,    per100g: scale(fiber))
        food.setNutrient(Nutrient.sugars,   per100g: scale(sugars))
        food.setNutrient(Nutrient.fat,      per100g: scale(fat))

        for t in Micros.tracked {
            food.setNutrient(t.id, per100g: scale(micros[t.id] ?? ""))
        }

        let cleanLabel = servingLabel.trimmingCharacters(in: .whitespaces)
        let label = cleanLabel.isEmpty ? "1 serving" : cleanLabel
        food.servings = [
            ServingOption(label: "\(label) (\(Int(grams))g)", grams: grams),
            ServingOption(label: "grams", grams: 1)
        ]

        if editing == nil {
            context.insert(food)
        }

        onSave?(food)
        dismiss()
    }
}

// MARK: - Manage saved custom foods

struct MyFoodsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Food.name) private var allFoods: [Food]

    @State private var creating = false
    @State private var editingFood: Food?

    private var customFoods: [Food] { allFoods.filter(\.isCustom) }

    var body: some View {
        List {
            Section {
                Button {
                    creating = true
                } label: {
                    Label("New custom food", systemImage: "plus")
                }
            }

            Section("Saved (\(customFoods.count))") {
                if customFoods.isEmpty {
                    Text("Nothing yet. Create a food from a nutrition label and it'll be reusable forever.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(customFoods) { f in
                    Button {
                        editingFood = f
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.name).foregroundStyle(.primary)
                            Text(f.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { idx in
                    for i in idx { context.delete(customFoods[i]) }
                }
            }
        }
        .navigationTitle("My Foods")
        .sheet(isPresented: $creating) {
            CustomFoodEditor()
        }
        .sheet(item: $editingFood) { f in
            CustomFoodEditor(editing: f)
        }
    }
}
