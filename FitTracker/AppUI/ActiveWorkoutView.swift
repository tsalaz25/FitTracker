//
//  ActiveWorkoutView.swift
//  FitTracker
//
//  Created by Tomas Salaz on 8/25/26.
//

import SwiftUI
import SwiftData
import Combine

struct ActiveWorkoutView: View {
    @Bindable var session: WorkoutSession

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var rest = RestTimer()
    @State private var picking = false
    @State private var confirmFinish = false
    @State private var now = Date.now

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            List {
                summarySection
                ForEach(session.sortedExercises) { pe in
                    if pe.isWarmupBlock {
                        WarmupBlockSection(performed: pe)
                    } else {
                        ActiveExerciseSection(performed: pe,
                                              session: session,
                                              rest: rest)
                    }
                }
                addSection
            }
            .navigationTitle(session.title)
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneBar()
            .safeAreaInset(edge: .bottom) {
                if rest.isRunning { restBar }
            }
            .toolbar { toolbarContent }
            .sheet(isPresented: $picking) {
                ExercisePicker { addExercise($0) }
            }
            .confirmationDialog("Finish this workout?",
                                isPresented: $confirmFinish,
                                titleVisibility: .visible) {
                Button("Finish") { finish() }
                Button("Keep going", role: .cancel) { }
            }
            .onReceive(tick) { now = $0 }
        }
        .interactiveDismissDisabled()
    }

    // MARK: Sections

    @ViewBuilder
    private var summarySection: some View {
        Section {
            HStack {
                Label(TimeFormat.hms(now.timeIntervalSince(session.start)),
                      systemImage: "clock")
                    .monospacedDigit()
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if session.totalVolume > 0 {
                        Text("\(Int(session.totalVolume)) lb")
                            .font(.caption.monospacedDigit())
                    }
                    if session.totalMiles > 0 {
                        Text(TimeFormat.distance(session.totalMiles))
                            .font(.caption.monospacedDigit())
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var addSection: some View {
        Section {
            Button {
                picking = true
            } label: {
                Label("Add exercise", systemImage: "plus")
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Finish") { confirmFinish = true }
                .bold()
        }
        ToolbarItem(placement: .cancellationAction) {
            Button("Discard", role: .destructive) {
                rest.stop()
                context.delete(session)
                dismiss()
            }
        }
    }

    private var restBar: some View {
        HStack {
            Text(rest.display)
                .font(.title2.monospacedDigit().bold())
            Spacer()
            Button("-15") { rest.add(-15) }
            Button("+15") { rest.add(15) }
            Button("Skip") { rest.stop() }
        }
        .buttonStyle(.bordered)
        .padding()
        .background(.regularMaterial)
    }

    // MARK: Actions

    private func addExercise(_ ex: Exercise) {
        let pe = PerformedExercise(exerciseID: ex.id,
                                   exerciseName: ex.name,
                                   order: session.performed.count,
                                   mode: ex.isCardio ? .cardio : .strength)
        context.insert(pe)
        let s = SetLog(index: 0)
        context.insert(s)
        pe.sets.append(s)
        session.performed.append(pe)
    }

    private func finish() {
        for pe in session.performed {
            let incomplete = pe.sets.filter { !$0.isComplete }
            for s in incomplete {
                if let idx = pe.sets.firstIndex(where: {
                    $0.persistentModelID == s.persistentModelID
                }) {
                    context.delete(pe.sets.remove(at: idx))
                }
            }
        }

        let empties = session.performed.filter { $0.sets.isEmpty }
        for pe in empties {
            if let idx = session.performed.firstIndex(where: {
                $0.persistentModelID == pe.persistentModelID
            }) {
                context.delete(session.performed.remove(at: idx))
            }
        }

        session.end = .now
        rest.stop()
        dismiss()
    }
}

// MARK: - Warm-up block (1 × 1)

struct WarmupBlockSection: View {
    @Bindable var performed: PerformedExercise

    private var theSet: SetLog? { performed.sortedSets.first }

    var body: some View {
        Section {
            if !performed.notes.isEmpty {
                Text(performed.notes)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let s = theSet {
                Button {
                    s.isComplete.toggle()
                } label: {
                    HStack {
                        Image(systemName: s.isComplete
                              ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(s.isComplete ? .green : .secondary)
                        Text(s.isComplete ? "Warm-up done" : "Mark warm-up complete")
                            .font(.callout)
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(s.isComplete
                                   ? Color.orange.opacity(0.10)
                                   : Color.clear)
            }
        } header: {
            HStack {
                Label("Warm-Up", systemImage: "flame")
                    .textCase(nil)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                Spacer()
                Text("1 × 1")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
        }
    }
}

// MARK: - One exercise block

struct ActiveExerciseSection: View {
    @Bindable var performed: PerformedExercise
    let session: WorkoutSession
    let rest: RestTimer

    @Environment(\.modelContext) private var context
    @State private var last: SetLog?

    private var isCardio: Bool { performed.mode == .cardio }

    var body: some View {
        Section {
            columnHeader

            ForEach(performed.sortedSets) { setLog in
                ActiveSetRow(performed: performed,
                             setLog: setLog,
                             isCardio: isCardio,
                             rest: rest)
            }
            .onDelete(perform: deleteSet)

            if !performed.notes.isEmpty {
                Text(performed.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            addButtons
        } header: {
            HStack {
                Text(performed.exerciseName)
                    .textCase(nil)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                headerDetail
            }
        }
        .task {
            last = WorkoutEngine.lastPerformance(exerciseID: performed.exerciseID,
                                                 excluding: session,
                                                 context: context)
        }
    }

    @ViewBuilder
    private var columnHeader: some View {
        HStack(spacing: 10) {
            Text("SET").frame(width: 36, alignment: .leading)
            if isCardio {
                Text("TIME").frame(width: 72)
                Text("PACE").frame(width: 72)
            } else {
                Text("LB").frame(width: 66)
                Text("REPS").frame(width: 54)
            }
            Spacer()
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var headerDetail: some View {
        if isCardio {
            if performed.totalMiles > 0 {
                Text(TimeFormat.distance(performed.totalMiles))
                    .font(.caption2).foregroundStyle(.secondary).textCase(nil)
            } else if let p = last?.paceString {
                Text("best: \(p)")
                    .font(.caption2).foregroundStyle(.secondary).textCase(nil)
            }
        } else if let last, let w = last.weight, let r = last.reps {
            Text("last: \(Int(w))×\(r)")
                .font(.caption2).foregroundStyle(.secondary).textCase(nil)
        }
    }

    @ViewBuilder
    private var addButtons: some View {
        if isCardio {
            Button { addSet(.working) } label: {
                Label("Add rep", systemImage: "plus.circle").font(.caption)
            }
        } else {
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
    }

    private func addSet(_ type: SetType) {
        let next = SetLog(index: performed.sets.count, type: type)
        context.insert(next)
        if let prev = performed.sortedSets.last {
            next.weight = prev.weight
            next.reps = prev.reps
            next.durationSeconds = prev.durationSeconds
            next.paceSecondsPerMile = prev.paceSecondsPerMile
            if type == .dropset, let w = prev.weight {
                next.weight = (w * 0.7).rounded()
            }
        }
        performed.sets.append(next)
        performed.reindex()
    }

    private func deleteSet(_ offsets: IndexSet) {
        let list = performed.sortedSets
        for i in offsets {
            if let idx = performed.sets.firstIndex(where: {
                $0.persistentModelID == list[i].persistentModelID
            }) {
                context.delete(performed.sets.remove(at: idx))
            }
        }
        performed.reindex()
    }
}

// MARK: - One set row

struct ActiveSetRow: View {
    @Bindable var performed: PerformedExercise
    @Bindable var setLog: SetLog
    let isCardio: Bool
    let rest: RestTimer

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                Picker("Type", selection: typeBinding) {
                    ForEach(SetType.allCases, id: \.self) { t in
                        Label(t.label, systemImage: t.symbol).tag(t)
                    }
                }
            } label: {
                Text(performed.displayLabel(for: setLog))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(color)
                    .frame(width: 36, alignment: .leading)
            }

            if isCardio {
                TimeField(seconds: $setLog.durationSeconds, placeholder: "--:--")
                TimeField(seconds: $setLog.paceSecondsPerMile, placeholder: "--:--")
                if let d = setLog.distanceString {
                    Text(d)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else {
                WeightField(value: $setLog.weight)
                RepsField(value: repsBinding, placeholder: targetPlaceholder)
            }

            Spacer()

            Button {
                setLog.isComplete.toggle()
                if setLog.isComplete && setLog.type != .warmup {
                    rest.start()
                }
            } label: {
                Image(systemName: setLog.isComplete
                      ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(setLog.isComplete ? .green : .secondary)
            }
            .buttonStyle(.plain)
        }
        .listRowBackground(setLog.isComplete
                           ? Color.green.opacity(0.10)
                           : Color.clear)
    }

    private var typeBinding: Binding<SetType> {
        Binding(
            get: { setLog.type },
            set: { newType in
                setLog.type = newType
                performed.reindex()
            }
        )
    }

    private var repsBinding: Binding<Int> {
        Binding(
            get: { setLog.reps ?? 0 },
            set: { newReps in
                setLog.reps = newReps > 0 ? newReps : nil
            }
        )
    }

    private var targetPlaceholder: String {
        if let t = setLog.targetReps, t > 0 { return String(t) }
        return "—"
    }

    private var color: Color {
        switch setLog.type {
        case .warmup:  return .orange
        case .dropset: return .purple
        case .working: return .primary
        }
    }
}
