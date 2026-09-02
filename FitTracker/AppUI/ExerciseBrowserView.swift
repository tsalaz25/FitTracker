//
//  ExerciseBrowserView.swift
//  FitTracker
//
//  Created by Tomas Salaz on 8/25/26.
//

import SwiftUI

// MARK: - Filter bar

struct FilterBar: View {
    @Binding var filters: ExerciseFilters
    private let catalog = ExerciseCatalog.shared

    var body: some View {
        Section {
            DisclosureGroup {
                picker("Muscle", options: catalog.allMuscles, selection: $filters.muscle)
                picker("Equipment", options: catalog.allEquipment, selection: $filters.equipment)
                picker("Type", options: catalog.allKinds, selection: $filters.kind)

                if filters.isActive {
                    Button("Clear all", role: .destructive) {
                        filters.clear()
                    }
                    .font(.caption)
                }
            } label: {
                HStack {
                    Label("Filters", systemImage: filters.isActive
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                    Spacer()
                    if filters.isActive {
                        Text(filters.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private func picker(_ title: String,
                        options: [String],
                        selection: Binding<String?>) -> some View {
        Picker(title, selection: selection) {
            Text("All").tag(String?.none)
            ForEach(options, id: \.self) { o in
                Text(o.capitalized).tag(String?.some(o))
            }
        }
    }
}

// MARK: - Quick muscle chips

struct MuscleChips: View {
    @Binding var selection: String?
    private let catalog = ExerciseCatalog.shared

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", value: nil)
                ForEach(catalog.allMuscles, id: \.self) { m in
                    chip(m, value: m)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func chip(_ label: String, value: String?) -> some View {
        let isOn = selection == value
        return Button {
            selection = value
        } label: {
            Text(label)
                .font(.caption.weight(isOn ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isOn ? Color.accentColor : Color.secondary.opacity(0.15))
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Row

struct ExerciseRow: View {
    let exercise: Exercise

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(exercise.name)
                    .lineLimit(1)
                if exercise.isCardio {
                    Image(systemName: "figure.run")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text(exercise.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Browser

struct ExerciseBrowserView: View {
    private let catalog = ExerciseCatalog.shared
    @State private var query = ""
    @State private var muscle: String?
    @State private var equipment: String?

    private var results: [Exercise] {
        var f = ExerciseFilters()
        f.muscle = muscle
        f.equipment = equipment
        return catalog.search(query, filters: f)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let err = catalog.loadError {
                    ContentUnavailableView("Couldn't load exercises",
                                           systemImage: "exclamationmark.triangle",
                                           description: Text(err))
                } else {
                    List {
                        Section {
                            MuscleChips(selection: $muscle)
                                .listRowInsets(EdgeInsets(top: 4, leading: 12,
                                                          bottom: 4, trailing: 12))
                            Picker("Equipment", selection: $equipment) {
                                Text("All equipment").tag(String?.none)
                                ForEach(catalog.allEquipment, id: \.self) { e in
                                    Text(e).tag(String?.some(e))
                                }
                            }
                        }

                        ForEach(catalog.grouped(results), id: \.muscle) { group in
                            Section {
                                ForEach(group.items) { ex in
                                    NavigationLink {
                                        ExerciseDetailView(exercise: ex)
                                    } label: {
                                        ExerciseRow(exercise: ex)
                                    }
                                }
                            } header: {
                                HStack {
                                    Text(group.muscle)
                                    Spacer()
                                    Text("\(group.items.count)")
                                }
                            }
                        }

                        if results.isEmpty {
                            Text("No matches").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Exercises")
            .searchable(text: $query, prompt: "Search exercises")
        }
    }
}

// MARK: - Detail

struct ExerciseDetailView: View {
    let exercise: Exercise

    var body: some View {
        List {
            Section {
                LabeledContent("Muscle", value: exercise.muscle)
                LabeledContent("Equipment", value: exercise.equipment)
                LabeledContent("Type", value: exercise.kind.capitalized)
                if !exercise.secondary.isEmpty {
                    LabeledContent("Also works",
                                   value: exercise.secondary.joined(separator: ", "))
                }
                if exercise.unilateral {
                    LabeledContent("Logging", value: "One side at a time")
                }
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
