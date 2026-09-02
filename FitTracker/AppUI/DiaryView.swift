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
    @Query(sort: \MacroGoal.weekday) private var goals: [MacroGoal]

    @State private var addingTo: String?
    @State private var day = Date.now
    @State private var showMicros = false

    private let meals = ["Breakfast", "Lunch", "Dinner", "Snacks"]

    private var entries: [FoodEntry] {
        allEntries.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
    }

    /// Goal for the displayed day's weekday, not necessarily today's.
    private var goal: MacroGoal? {
        Goals.goal(for: day, in: goals)
    }

    private func total(_ id: Int) -> Double {
        entries.reduce(0) { $0 + ($1.food?.amount(of: id, grams: $1.grams) ?? 0) }
    }

    var body: some View {
        NavigationStack {
            List {
                dayNavigator

                if let goal, goal.isSet {
                    goalSection(goal)
                } else {
                    Section("Totals") {
                        macroRow("Calories", Nutrient.calories, digits: 0)
                        macroRow("Protein", Nutrient.protein, digits: 1)
                        macroRow("Carbs", Nutrient.carbs, digits: 1)
                        macroRow("Fat", Nutrient.fat, digits: 1)
                    }
                    Section {
                        NavigationLink {
                            GoalsEditorView()
                        } label: {
                            Label("Set macro goals", systemImage: "target")
                        }
                    }
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
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        MyFoodsView()
                    } label: {
                        Image(systemName: "list.bullet.rectangle")
                    }
                }
            }
            .sheet(item: $addingTo) { meal in
                FoodSearchView(meal: meal, date: day)
            }
            .task { Goals.seedIfNeeded(goals, context: context) }
        }
    }

    // MARK: - Goal section

    private func goalSection(_ goal: MacroGoal) -> some View {
        let kcal = total(Nutrient.calories)
        let remaining = goal.calories - kcal

        return Section {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Int(kcal))")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("of \(Int(goal.calories)) kcal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(remaining >= 0 ? "\(Int(remaining))" : "+\(Int(-remaining))")
                        .font(.title2.monospacedDigit().bold())
                        .foregroundStyle(remaining >= 0 ? Color.primary : Color.orange)
                    Text(remaining >= 0 ? "remaining" : "over")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

            GoalProgressRow(label: "Carbs",
                            consumed: total(Nutrient.carbs),
                            target: goal.carbs,
                            unit: "g",
                            tint: .blue)
            GoalProgressRow(label: "Protein",
                            consumed: total(Nutrient.protein),
                            target: goal.protein,
                            unit: "g",
                            tint: .green)
            GoalProgressRow(label: "Fat",
                            consumed: total(Nutrient.fat),
                            target: goal.fat,
                            unit: "g",
                            tint: .orange)
        } header: {
            HStack {
                Text("\(PlanWeekView.names[goal.weekday]) target")
                Spacer()
                NavigationLink {
                    GoalDayEditor(goal: goal)
                } label: {
                    Text("Edit").font(.caption)
                }
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
