//
//  ExerciseBrowserView.swift
//  FitTracker
//
//  Created by Tomas Salaz on 8/25/26.
//

import SwiftUI

// MARK: - Reusable filter bar

struct FilterBar: View {
    @Binding var filters: ExerciseFilters
    private let catalog = ExerciseCatalog.shared

    var body: some View {
        Section {
            DisclosureGroup {
                picker("Muscle", options: catalog.allMuscles, selection: $filters.muscle)
                picker("Equipment", options: catalog.allEquipment, selection: $filters.equipment)
                picker("Category", options: catalog.allCategories, selection: $filters.category)
                picker("Level", options: catalog.allLevels, selection: $filters.level)

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

// MARK: - Row

struct ExerciseRow: View {
    let exercise: Exercise

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(exercise.name)
                    .lineLimit(2)
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
    @State private var filters = ExerciseFilters()

    private var results: [Exercise] {
        catalog.search(query, filters: filters)
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
                        FilterBar(filters: $filters)

                        Section {
                            if results.isEmpty {
                                Text("No matches").foregroundStyle(.secondary)
                            }
                            ForEach(results) { ex in
                                NavigationLink {
                                    ExerciseDetailView(exercise: ex)
                                } label: {
                                    ExerciseRow(exercise: ex)
                                }
                            }
                        } header: {
                            Text("\(results.count) exercises")
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
            Section("About") {
                LabeledContent("Equipment", value: exercise.equipment?.capitalized ?? "—")
                LabeledContent("Level", value: exercise.level?.capitalized ?? "—")
                LabeledContent("Type", value: exercise.mechanic?.capitalized ?? "—")
                LabeledContent("Category", value: exercise.category?.capitalized ?? "—")
                LabeledContent("Primary", value: exercise.primaryMuscles
                    .map(\.capitalized).joined(separator: ", "))
                if !exercise.secondaryMuscles.isEmpty {
                    LabeledContent("Secondary", value: exercise.secondaryMuscles
                        .map(\.capitalized).joined(separator: ", "))
                }
            }

            if !exercise.instructions.isEmpty {
                Section("Instructions") {
                    ForEach(Array(exercise.instructions.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(i + 1).")
                                .foregroundStyle(.secondary)
                            Text(step)
                        }
                        .font(.callout)
                    }
                }
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
