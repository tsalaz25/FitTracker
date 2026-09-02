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
                        dayRow(day)
                    }
                }
            }
            .navigationTitle("Weekly Plan")
            .task { seedIfNeeded() }
        }
    }

    private func dayRow(_ day: PlanDay) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.names[day.weekday]).font(.headline)
                Text(day.isRestDay
                     ? "Rest"
                     : (day.title.isEmpty ? "Untitled" : day.title))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !day.isRestDay && day.hasWarmup {
                Image(systemName: "flame.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            if !day.isRestDay && !day.items.isEmpty {
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

    private func isToday(_ weekday: Int) -> Bool {
        Calendar.current.component(.weekday, from: .now) == weekday
    }

    private func seedIfNeeded() {
        guard days.isEmpty else { return }
        for wd in 1...7 {
            let isRest = (wd == 1)
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
                warmupSection

                ForEach(day.sorted) { item in
                    PlanExerciseSection(item: item, onDelete: { remove(item) })
                }

                Section {
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
                } footer: {
                    Text("\(day.items.count)/10 exercises")
                }
            }
        }
        .navigationTitle(PlanWeekView.names[day.weekday])
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneBar()
        .sheet(isPresented: $picking) {
            ExercisePicker { add($0) }
        }
    }

    @ViewBuilder
    private var warmupSection: some View {
        Section {
            TextField("e.g. 5 min bike, band pull-aparts, 2 ramp sets",
                      text: $day.warmupNotes,
                      axis: .vertical)
                .lineLimit(2...6)
                .font(.callout)
        } header: {
            HStack {
                Label("Warm-Up", systemImage: "flame")
                    .textCase(nil)
                Spacer()
                if day.hasWarmup {
                    Text("1 × 1")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }
        } footer: {
            Text(day.hasWarmup
                 ? "Appears as a single check-off item at the top of the workout."
                 : "Leave blank to skip the warm-up block entirely.")
        }
    }

    private func add(_ ex: Exercise) {
        guard day.items.count < 10 else { return }
        let item = PlanExercise(exerciseID: ex.id,
                                exerciseName: ex.name,
                                order: day.items.count,
                                mode: ex.isCardio ? .cardio : .strength)
        context.insert(item)
        item.seedDefaultSets()
        day.items.append(item)
    }

    private func remove(_ item: PlanExercise) {
        if let idx = day.items.firstIndex(where: {
            $0.persistentModelID == item.persistentModelID
        }) {
            let removed = day.items.remove(at: idx)
            context.delete(removed)
        }
        for (i, it) in day.sorted.enumerated() { it.order = i }
    }
}

// MARK: - One exercise, with its set table

struct PlanExerciseSection: View {
    @Bindable var item: PlanExercise
    let onDelete: () -> Void

    @Environment(\.modelContext) private var context
    @State private var showNotes = false

    var body: some View {
        Section {
            if item.mode == .strength {
                setHeader
                ForEach(item.sortedSets) { planSet in
                    PlanSetRow(item: item, planSet: planSet)
                }
                .onDelete(perform: deleteSets)
                addButtons
            } else {
                CardioTargetEditor(item: item)
            }

            if showNotes {
                TextField("Notes (cues, tempo, etc.)",
                          text: $item.notes,
                          axis: .vertical)
                    .lineLimit(1...4)
                    .font(.callout)
            }
        } header: {
            header
        }
    }

    private var header: some View {
        HStack {
            Text(item.exerciseName)
                .textCase(nil)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(item.targetSummary)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .textCase(nil)
            Menu {
                if !item.isLockedToCardio {
                    Picker("Mode", selection: modeBinding) {
                        ForEach(TargetMode.allCases, id: \.self) { m in
                            Text(m.label).tag(m)
                        }
                    }
                }
                Button {
                    showNotes.toggle()
                } label: {
                    Label(showNotes ? "Hide notes" : "Add notes",
                          systemImage: "note.text")
                }
                Divider()
                Button(role: .destructive, action: onDelete) {
                    Label("Remove exercise", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var modeBinding: Binding<TargetMode> {
        Binding(
            get: { item.mode },
            set: { newMode in
                item.mode = newMode
                if newMode == .strength && item.sets.isEmpty {
                    item.seedDefaultSets()
                }
            }
        )
    }

    private var setHeader: some View {
        HStack(spacing: 12) {
            Text("SET").frame(width: 40, alignment: .leading)
            Text("REPS").frame(width: 54)
            Spacer()
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private var addButtons: some View {
        HStack(spacing: 8) {
            Button { addSet(.warmup) } label: {
                Label("Warm-up", systemImage: "flame").font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(.orange)

            Button { addSet(.working) } label: {
                Label("Set", systemImage: "plus").font(.caption)
            }
            .buttonStyle(.bordered)

            Button { addSet(.dropset) } label: {
                Label("Drop", systemImage: "arrow.down.right").font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(.purple)
        }
        .padding(.vertical, 2)
    }

    private func addSet(_ type: SetType) {
        let reps: Int
        switch type {
        case .warmup:
            reps = item.workingSets.first.map { max(1, $0.reps + 4) } ?? 10
        case .dropset:
            reps = item.workingSets.last.map { max(1, $0.reps + 4) } ?? 12
        case .working:
            reps = item.workingSets.last?.reps ?? 8
        }

        let newSet = PlanSet(index: item.sets.count, reps: reps, type: type)
        context.insert(newSet)
        item.sets.append(newSet)

        if type == .warmup {
            let warmups = item.sortedSets.filter { $0.type == .warmup }
            let rest = item.sortedSets.filter { $0.type != .warmup }
            for (i, x) in (warmups + rest).enumerated() { x.index = i }
        } else {
            item.reindex()
        }
    }

    private func deleteSets(_ offsets: IndexSet) {
        let list = item.sortedSets
        for i in offsets {
            if let idx = item.sets.firstIndex(where: {
                $0.persistentModelID == list[i].persistentModelID
            }) {
                let removed = item.sets.remove(at: idx)
                context.delete(removed)
            }
        }
        item.reindex()
    }
}

// MARK: - One set row

struct PlanSetRow: View {
    @Bindable var item: PlanExercise
    @Bindable var planSet: PlanSet

    var body: some View {
        HStack(spacing: 12) {
            Menu {
                Picker("Type", selection: typeBinding) {
                    ForEach(SetType.allCases, id: \.self) { t in
                        Label(t.label, systemImage: t.symbol).tag(t)
                    }
                }
            } label: {
                Text(item.displayLabel(for: planSet))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(color)
                    .frame(width: 40, alignment: .leading)
            }

            RepsField(value: $planSet.reps)

            Spacer()

            if planSet.type != .working {
                Text(planSet.type.label)
                    .font(.caption2)
                    .foregroundStyle(color)
            }
        }
    }

    private var typeBinding: Binding<SetType> {
        Binding(
            get: { planSet.type },
            set: { newType in
                planSet.type = newType
                item.reindex()
            }
        )
    }

    private var color: Color {
        switch planSet.type {
        case .warmup:  return .orange
        case .dropset: return .purple
        case .working: return .primary
        }
    }
}

// MARK: - Cardio target editor

struct CardioTargetEditor: View {
    @Bindable var item: PlanExercise

    var body: some View {
        VStack(spacing: 8) {
            Stepper("\(item.targetIntervals) reps",
                    value: $item.targetIntervals, in: 1...30)
                .font(.callout)

            HStack {
                Text("Time each").font(.callout)
                Spacer()
                TimeField(seconds: intervalBinding)
            }

            HStack {
                Text("Pace").font(.callout)
                Spacer()
                TimeField(seconds: paceBinding)
                Text("/mi").font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Text("\(TimeFormat.distance(item.targetDistancePerIntervalMiles)) each · \(TimeFormat.distance(item.targetTotalDistanceMiles)) total")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var intervalBinding: Binding<Double?> {
        Binding(
            get: { item.targetIntervalSeconds },
            set: { newValue in
                if let v = newValue, v > 0 {
                    item.targetIntervalSeconds = min(v, TimeFormat.maxSeconds)
                }
            }
        )
    }

    private var paceBinding: Binding<Double?> {
        Binding(
            get: { item.targetPaceSecondsPerMile },
            set: { newValue in
                if let v = newValue, v > 0 {
                    item.targetPaceSecondsPerMile = min(v, TimeFormat.maxSeconds)
                }
            }
        )
    }
}

// MARK: - Picker

struct ExercisePicker: View {
    let onPick: (Exercise) -> Void

    @Environment(\.dismiss) private var dismiss
    private let catalog = ExerciseCatalog.shared
    @State private var query = ""
    @State private var muscle: String?

    private var results: [Exercise] {
        var f = ExerciseFilters()
        f.muscle = muscle
        return catalog.search(query, filters: f)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    MuscleChips(selection: $muscle)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12,
                                                  bottom: 4, trailing: 12))
                }

                ForEach(catalog.grouped(results), id: \.muscle) { group in
                    Section(group.muscle) {
                        ForEach(group.items) { ex in
                            Button {
                                onPick(ex)
                                dismiss()
                            } label: {
                                ExerciseRow(exercise: ex)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }

                if results.isEmpty {
                    Text("No matches").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add Exercise")
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
