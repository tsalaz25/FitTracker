//
//  PlanView.swift
//  FitTracker
//
//  Created by Tomas Salaz on 8/25/26.
//

import SwiftUI
import SwiftData

// MARK: - Week overview

struct PlanWeekView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PlanDay.weekday) private var days: [PlanDay]

    static let names = ["", "Sunday", "Monday", "Tuesday",
                        "Wednesday", "Thursday", "Friday", "Saturday"]

    var body: some View {
        NavigationStack {
            List {
                ForEach(days) { day in
                    NavigationLink {
                        PlanDayEditor(day: day)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Self.names[day.weekday])
                                    .font(.headline)
                                Text(day.isRestDay
                                     ? "Rest"
                                     : (day.title.isEmpty ? "Untitled" : day.title))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if !day.isRestDay {
                                Text("\(day.items.count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            if isToday(day.weekday) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 7))
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Weekly Plan")
            .task { seedIfNeeded() }
        }
    }

    private func isToday(_ weekday: Int) -> Bool {
        Calendar.current.component(.weekday, from: .now) == weekday
    }

    /// Creates the seven days once, on first launch.
    private func seedIfNeeded() {
        guard days.isEmpty else { return }
        for wd in 1...7 {
            let isRest = (wd == 1)   // Sunday rest by default
            context.insert(PlanDay(weekday: wd,
                                   title: isRest ? "Rest" : "",
                                   isRestDay: isRest))
        }
    }
}

// MARK: - Day editor

struct PlanDayEditor: View {
    @Bindable var day: PlanDay
    @Environment(\.modelContext) private var context
    @State private var picking = false

    var body: some View {
        List {
            Section {
                TextField("Title (e.g. Push Day)", text: $day.title)
                Toggle("Rest day", isOn: $day.isRestDay)
            }

            if !day.isRestDay {
                Section {
                    ForEach(day.sorted) { item in
                        PlanRow(item: item)
                    }
                    .onDelete(perform: delete)
                    .onMove(perform: move)

                    if day.items.count < 10 {
                        Button {
                            picking = true
                        } label: {
                            Label("Add exercise", systemImage: "plus")
                        }
                    } else {
                        Text("10 exercise limit reached")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Exercises (\(day.items.count)/10)")
                }
            }
        }
        .navigationTitle(PlanWeekView.names[day.weekday])
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .sheet(isPresented: $picking) {
            ExercisePicker { add($0) }
        }
    }

    private func add(_ ex: Exercise) {
        guard day.items.count < 10 else { return }
        let item = PlanExercise(exerciseID: ex.id,
                                exerciseName: ex.name,
                                order: day.items.count,
                                mode: ex.isCardio ? .cardio : .strength)
        day.items.append(item)
    }

    private func delete(_ offsets: IndexSet) {
        let list = day.sorted
        for i in offsets {
            if let idx = day.items.firstIndex(where: { $0.id == list[i].id }) {
                let removed = day.items.remove(at: idx)
                context.delete(removed)
            }
        }
        for (i, item) in day.sorted.enumerated() { item.order = i }
    }

    private func move(_ offsets: IndexSet, _ dest: Int) {
        var list = day.sorted
        list.move(fromOffsets: offsets, toOffset: dest)
        for (i, item) in list.enumerated() { item.order = i }
    }
}

// MARK: - Plan row

struct PlanRow: View {
    @Bindable var item: PlanExercise

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.exerciseName)

            Picker("", selection: Binding(
                get: { item.mode },
                set: { item.mode = $0 }
            )) {
                ForEach(TargetMode.allCases, id: \.self) { m in
                    Text(m.label).tag(m)
                }
            }
            .pickerStyle(.segmented)

            if item.mode == .strength {
                HStack(spacing: 16) {
                    Stepper("\(item.targetSets) sets",
                            value: $item.targetSets, in: 1...10)
                    Stepper("\(item.targetReps) reps",
                            value: $item.targetReps, in: 1...50)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    Stepper("\(item.targetIntervals) reps",
                            value: $item.targetIntervals, in: 1...30)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text("Time each")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        TimeFieldRequired(seconds: $item.targetIntervalSeconds)
                    }

                    HStack {
                        Text("Pace")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        TimeFieldRequired(seconds: $item.targetPaceSecondsPerMile)
                        Text("/mi")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Spacer()
                        Text("\(TimeFormat.distance(item.targetDistancePerIntervalMiles)) each · \(TimeFormat.distance(item.targetTotalDistanceMiles)) total")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Picker

struct ExercisePicker: View {
    let onPick: (Exercise) -> Void

    @Environment(\.dismiss) private var dismiss
    private let catalog = ExerciseCatalog.shared
    @State private var query = ""
    @State private var filters = ExerciseFilters()

    private var results: [Exercise] {
        catalog.search(query, filters: filters)
    }

    var body: some View {
        NavigationStack {
            List {
                FilterBar(filters: $filters)

                Section {
                    if results.isEmpty {
                        Text("No matches").foregroundStyle(.secondary)
                    }
                    ForEach(results) { ex in
                        Button {
                            onPick(ex)
                            dismiss()
                        } label: {
                            ExerciseRow(exercise: ex)
                                .foregroundStyle(.primary)
                        }
                    }
                } header: {
                    Text("\(results.count) exercises")
                }
            }
            .navigationTitle("Pick Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search exercises")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
