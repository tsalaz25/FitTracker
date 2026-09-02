//
//  TrainingModels.swift
//  FitTracker
//
//  Created by Tomas Salaz on 8/25/26.
//

import Foundation
import SwiftData

// MARK: - Mode

enum TargetMode: String, Codable, CaseIterable {
    case strength, cardio

    var label: String {
        switch self {
        case .strength: return "Strength"
        case .cardio:   return "Cardio"
        }
    }
}

// MARK: - Set type

enum SetType: String, Codable, CaseIterable {
    case warmup, working, dropset

    var label: String {
        switch self {
        case .warmup:  return "Warm-up"
        case .working: return "Working"
        case .dropset: return "Drop set"
        }
    }

    var symbol: String {
        switch self {
        case .warmup:  return "flame"
        case .working: return "circle"
        case .dropset: return "arrow.down.right"
        }
    }

    /// Warm-ups don't count toward volume or working-set numbering.
    var countsAsWork: Bool { self != .warmup }
}

// MARK: - Formatting helpers

enum TimeFormat {
    /// Hard ceiling for any mm:ss field.
    static let maxSeconds: Double = 99 * 60 + 59

    static func mmss(_ seconds: Double) -> String {
        let t = max(0, Int(min(seconds, maxSeconds).rounded()))
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    static func hms(_ seconds: Double) -> String {
        let t = max(0, Int(seconds))
        return String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
    }

    /// Accepts "8:30" (mm:ss) or "510" (raw seconds). Clamped to 99:59.
    static func parse(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        var total: Double
        if t.contains(":") {
            let parts = t.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                  let m = Double(parts[0]),
                  let s = Double(parts[1]) else { return nil }
            total = m * 60 + min(s, 59)
        } else {
            guard let v = Double(t) else { return nil }
            total = v
        }
        return min(total, maxSeconds)
    }

    static func distance(_ miles: Double) -> String {
        guard miles > 0 else { return "—" }
        if miles < 0.5 {
            return "\(Int((miles * 1609.34).rounded())) m"
        }
        return String(format: "%.2f mi", miles)
    }
}

// MARK: - Plan

@Model
final class PlanDay {
    var weekday: Int = 1              // 1 = Sunday ... 7 = Saturday
    var title: String = ""
    var isRestDay: Bool = false

    /// Free-text warm-up plan. Becomes a single 1×1 block at the top of
    /// the workout when non-empty.
    var warmupNotes: String = ""

    @Relationship(deleteRule: .cascade) var items: [PlanExercise] = []

    init(weekday: Int, title: String, isRestDay: Bool = false) {
        self.weekday = weekday
        self.title = title
        self.isRestDay = isRestDay
        self.items = []
    }

    var sorted: [PlanExercise] { items.sorted { $0.order < $1.order } }

    var hasWarmup: Bool {
        !warmupNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// One planned set: its own rep target and type.
@Model
final class PlanSet {
    var index: Int = 0
    var typeRaw: String = SetType.working.rawValue
    var reps: Int = 8

    var type: SetType {
        get { SetType(rawValue: typeRaw) ?? .working }
        set { typeRaw = newValue.rawValue }
    }

    init(index: Int, reps: Int = 8, type: SetType = .working) {
        self.index = index
        self.reps = reps
        self.typeRaw = type.rawValue
    }
}

@Model
final class PlanExercise {
    var exerciseID: String = ""
    var exerciseName: String = ""
    var order: Int = 0
    var notes: String = ""

    @Relationship(deleteRule: .cascade) var sets: [PlanSet] = []

    // Cardio targets: reps × time @ pace, both mm:ss
    var modeRaw: String = TargetMode.strength.rawValue
    var targetIntervals: Int = 1
    var targetIntervalSeconds: Double = 600
    var targetPaceSecondsPerMile: Double = 510

    var mode: TargetMode {
        get { TargetMode(rawValue: modeRaw) ?? .strength }
        set { modeRaw = newValue.rawValue }
    }

    /// True when the catalog itself classifies this as cardio, in which
    /// case the mode can't be switched to strength.
    var isLockedToCardio: Bool {
        ExerciseCatalog.shared.exercise(id: exerciseID)?.isCardio ?? false
    }

    var sortedSets: [PlanSet] { sets.sorted { $0.index < $1.index } }
    var workingSets: [PlanSet] { sortedSets.filter { $0.type != .warmup } }
    var warmupCount: Int { sortedSets.filter { $0.type == .warmup }.count }

    func displayLabel(for set: PlanSet) -> String {
        if set.type == .warmup { return "W" }
        let ordered = sortedSets.filter { $0.type != .warmup }
        let n = (ordered.firstIndex { $0.persistentModelID == set.persistentModelID } ?? 0) + 1
        return set.type == .dropset ? "\(n)D" : "\(n)"
    }

    /// "3 × 6-10" — collapses a pyramid into a readable range.
    var repSummary: String {
        let work = workingSets
        guard !work.isEmpty else { return "No sets" }
        let reps = work.map(\.reps)
        let lo = reps.min() ?? 0
        let hi = reps.max() ?? 0
        let range = lo == hi ? "\(lo)" : "\(lo)-\(hi)"
        return "\(work.count) × \(range)"
    }

    var targetSummary: String {
        switch mode {
        case .strength:
            var s = repSummary
            if warmupCount > 0 { s += " · \(warmupCount)W" }
            return s
        case .cardio:
            return "\(targetIntervals) × \(TimeFormat.mmss(targetIntervalSeconds)) @ \(TimeFormat.mmss(targetPaceSecondsPerMile))/mi"
        }
    }

    var targetDistancePerIntervalMiles: Double {
        guard targetPaceSecondsPerMile > 0 else { return 0 }
        return targetIntervalSeconds / targetPaceSecondsPerMile
    }

    var targetTotalDistanceMiles: Double {
        targetDistancePerIntervalMiles * Double(targetIntervals)
    }

    init(exerciseID: String,
         exerciseName: String,
         order: Int,
         mode: TargetMode = .strength) {
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.order = order
        self.modeRaw = mode.rawValue
        self.sets = []
    }

    func seedDefaultSets() {
        guard sets.isEmpty, mode == .strength else { return }
        for i in 0..<3 {
            sets.append(PlanSet(index: i, reps: 8, type: .working))
        }
    }

    func reindex() {
        for (i, s) in sortedSets.enumerated() { s.index = i }
    }
}

// MARK: - Performed workout

@Model
final class WorkoutSession {
    var title: String = "Workout"
    var start: Date = Date.now
    var end: Date?
    @Relationship(deleteRule: .cascade) var performed: [PerformedExercise] = []

    init(title: String, start: Date = .now) {
        self.title = title
        self.start = start
        self.performed = []
    }

    var isActive: Bool { end == nil }
    var duration: TimeInterval { (end ?? .now).timeIntervalSince(start) }

    var sortedExercises: [PerformedExercise] {
        performed.sorted { $0.order < $1.order }
    }

    /// Warm-up sets excluded — they aren't training volume.
    var totalVolume: Double {
        performed.flatMap(\.sets)
            .filter { $0.isComplete && $0.type.countsAsWork }
            .reduce(0) { $0 + (Double($1.reps ?? 0) * ($1.weight ?? 0)) }
    }

    var totalMiles: Double {
        performed.flatMap(\.sets)
            .filter(\.isComplete)
            .reduce(0) { $0 + ($1.distanceMiles ?? 0) }
    }
}

@Model
final class PerformedExercise {
    var exerciseID: String = ""
    var exerciseName: String = ""
    var order: Int = 0
    var modeRaw: String = TargetMode.strength.rawValue
    var notes: String = ""

    /// The 1×1 warm-up block generated from the plan day's notes.
    var isWarmupBlock: Bool = false

    @Relationship(deleteRule: .cascade) var sets: [SetLog] = []

    var mode: TargetMode {
        get { TargetMode(rawValue: modeRaw) ?? .strength }
        set { modeRaw = newValue.rawValue }
    }

    init(exerciseID: String,
         exerciseName: String,
         order: Int,
         mode: TargetMode = .strength) {
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.order = order
        self.modeRaw = mode.rawValue
        self.sets = []
    }

    var sortedSets: [SetLog] { sets.sorted { $0.index < $1.index } }

    func displayLabel(for set: SetLog) -> String {
        if set.type == .warmup { return "W" }
        let ordered = sortedSets.filter { $0.type != .warmup }
        let n = (ordered.firstIndex { $0.persistentModelID == set.persistentModelID } ?? 0) + 1
        return set.type == .dropset ? "\(n)D" : "\(n)"
    }

    var totalMiles: Double {
        sets.filter(\.isComplete).reduce(0) { $0 + ($1.distanceMiles ?? 0) }
    }

    var bestPace: Double? {
        sets.filter(\.isComplete).compactMap(\.paceSecondsPerMile).min()
    }

    func reindex() {
        for (i, s) in sortedSets.enumerated() { s.index = i }
    }
}

@Model
final class SetLog {
    var index: Int = 0
    var isComplete: Bool = false
    var typeRaw: String = SetType.working.rawValue

    /// What the plan called for, shown as grey placeholder text.
    var targetReps: Int?

    // Strength
    var reps: Int?
    var weight: Double?

    // Cardio — both mm:ss, capped at 99:59
    var durationSeconds: Double?
    var paceSecondsPerMile: Double?

    var type: SetType {
        get { SetType(rawValue: typeRaw) ?? .working }
        set { typeRaw = newValue.rawValue }
    }

    init(index: Int, type: SetType = .working) {
        self.index = index
        self.isComplete = false
        self.typeRaw = type.rawValue
    }

    /// Derived: time ÷ pace. Not stored.
    var distanceMiles: Double? {
        guard let t = durationSeconds,
              let p = paceSecondsPerMile,
              p > 0 else { return nil }
        return t / p
    }

    var paceString: String? {
        paceSecondsPerMile.map { TimeFormat.mmss($0) + " /mi" }
    }

    var distanceString: String? {
        distanceMiles.map { TimeFormat.distance($0) }
    }
}
