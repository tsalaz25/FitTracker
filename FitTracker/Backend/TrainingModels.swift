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

// MARK: - Formatting helpers

enum TimeFormat {
    /// 510 -> "8:30"
    static func mmss(_ seconds: Double) -> String {
        let t = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    /// 3725 -> "1:02:05"
    static func hms(_ seconds: Double) -> String {
        let t = max(0, Int(seconds))
        return String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
    }

    /// Accepts "8:30" (mm:ss) or "510" (raw seconds).
    static func parse(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        if t.contains(":") {
            let parts = t.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                  let m = Double(parts[0]),
                  let s = Double(parts[1]) else { return nil }
            return m * 60 + s
        }
        return Double(t)
    }

    /// Miles, shown as meters when short.
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
    @Relationship(deleteRule: .cascade) var items: [PlanExercise] = []

    init(weekday: Int, title: String, isRestDay: Bool = false) {
        self.weekday = weekday
        self.title = title
        self.isRestDay = isRestDay
        self.items = []
    }

    var sorted: [PlanExercise] { items.sorted { $0.order < $1.order } }
}

@Model
final class PlanExercise {
    var exerciseID: String = ""
    var exerciseName: String = ""
    var order: Int = 0

    // Strength targets
    var targetSets: Int = 3
    var targetReps: Int = 8

    // Cardio targets: reps × time @ pace
    var modeRaw: String = TargetMode.strength.rawValue
    var targetIntervals: Int = 1
    var targetIntervalSeconds: Double = 600      // per rep
    var targetPaceSecondsPerMile: Double = 510   // 8:30 /mi

    var mode: TargetMode {
        get { TargetMode(rawValue: modeRaw) ?? .strength }
        set { modeRaw = newValue.rawValue }
    }

    /// Derived, never entered.
    var targetDistancePerIntervalMiles: Double {
        guard targetPaceSecondsPerMile > 0 else { return 0 }
        return targetIntervalSeconds / targetPaceSecondsPerMile
    }

    var targetTotalDistanceMiles: Double {
        targetDistancePerIntervalMiles * Double(targetIntervals)
    }

    var targetSummary: String {
        switch mode {
        case .strength:
            return "\(targetSets) × \(targetReps)"
        case .cardio:
            return "\(targetIntervals) × \(TimeFormat.mmss(targetIntervalSeconds)) @ \(TimeFormat.mmss(targetPaceSecondsPerMile))/mi"
        }
    }

    init(exerciseID: String,
         exerciseName: String,
         order: Int,
         targetSets: Int = 3,
         targetReps: Int = 8,
         mode: TargetMode = .strength) {
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.order = order
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.modeRaw = mode.rawValue
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

    /// Sum of reps × weight across completed strength sets.
    var totalVolume: Double {
        performed.flatMap(\.sets)
            .filter(\.isComplete)
            .reduce(0) { $0 + (Double($1.reps ?? 0) * ($1.weight ?? 0)) }
    }

    /// Sum of derived distance across completed cardio intervals.
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

    var totalMiles: Double {
        sets.filter(\.isComplete).reduce(0) { $0 + ($1.distanceMiles ?? 0) }
    }

    var bestPace: Double? {
        sets.filter(\.isComplete).compactMap(\.paceSecondsPerMile).min()
    }
}

@Model
final class SetLog {
    var index: Int = 0
    var isComplete: Bool = false

    // Strength
    var reps: Int?
    var weight: Double?

    // Cardio — entered
    var durationSeconds: Double?
    var paceSecondsPerMile: Double?

    init(index: Int) {
        self.index = index
        self.isComplete = false
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
