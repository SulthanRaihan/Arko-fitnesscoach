import SwiftUI

// ════════════════════════════════════════════════════════════════════════════
// MARK: - MuscleBrowseView
// Browse exercises by target muscle using ExerciseDB (1300+ exercises w/ GIFs).
// ════════════════════════════════════════════════════════════════════════════

struct MuscleBrowseView: View {
    @State private var selectedTarget = "pectorals"
    @State private var results: [ExerciseDBResult] = []
    @State private var isLoading = false
    @State private var detail: ExerciseDBResult?

    var body: some View {
        VStack(spacing: 14) {
            muscleChips
            if isLoading {
                Spacer()
                ProgressView().tint(Color.arkoLime)
                Text("Loading exercises…").font(.caption).foregroundStyle(Color.arkoTextDim)
                Spacer()
            } else if results.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "dumbbell")
                        .font(.system(size: 32)).foregroundStyle(Color.arkoTextDim)
                    Text("No exercises found").font(.subheadline).foregroundStyle(Color.arkoTextDim)
                }
                Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 10) {
                        ForEach(results, id: \.id) { ex in
                            resultRow(ex)
                        }
                    }
                    .padding(.bottom, 110)
                }
            }
        }
        .task(id: selectedTarget) { await loadTarget() }
        .sheet(item: $detail) { ex in
            ExerciseDBDetailSheet(exercise: ex)
        }
    }

    // MARK: Muscle chips

    private var muscleChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MuscleMapping.browseTargets, id: \.target) { item in
                    Button { selectedTarget = item.target } label: {
                        Text(item.label)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(selectedTarget == item.target
                                        ? Color.arkoLime : Color.arkoCard)
                            .foregroundStyle(selectedTarget == item.target ? .black : .white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: Result row

    private func resultRow(_ ex: ExerciseDBResult) -> some View {
        Button { detail = ex } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Color.white)
                    ExerciseDBGIFView(id: ex.id, resolution: 180).padding(3)
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text(ex.name.capitalized)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("\(ex.target.capitalized) · \(ex.equipment.capitalized)")
                        .font(.caption2).foregroundStyle(Color.arkoTextDim)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.arkoTextDim)
            }
            .padding(10)
            .background(Color.arkoCard)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
    }

    private func loadTarget() async {
        isLoading = true
        results = await ExerciseDBService.shared.exercises(forTarget: selectedTarget, limit: 20)
        isLoading = false
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - ExerciseDB Detail Sheet
// ════════════════════════════════════════════════════════════════════════════

struct ExerciseDBDetailSheet: View {
    let exercise: ExerciseDBResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.arkoBg.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    // GIF
                    ZStack {
                        Color.white
                        ExerciseDBGIFView(id: exercise.id, resolution: 360).padding(20)
                    }
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                    Text(exercise.name.capitalized)
                        .font(.title3.weight(.bold)).foregroundStyle(.white)

                    // Badges
                    HStack(spacing: 8) {
                        badge(exercise.target.capitalized, .arkoLime)
                        badge(exercise.bodyPart.capitalized, .cyan)
                        badge(exercise.equipment.capitalized, .orange)
                    }

                    if !exercise.secondaryMuscles.isEmpty {
                        Text("Also works: \(exercise.secondaryMuscles.map { $0.capitalized }.joined(separator: ", "))")
                            .font(.caption).foregroundStyle(Color.arkoTextDim)
                    }

                    // Instructions
                    if !exercise.instructions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("How to Perform", systemImage: "list.number")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.arkoLime)
                            ForEach(Array(exercise.instructions.enumerated()), id: \.offset) { i, step in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\(i + 1)")
                                        .font(.caption.weight(.bold)).foregroundStyle(.black)
                                        .frame(width: 20, height: 20)
                                        .background(Color.arkoLime).clipShape(Circle())
                                    Text(step).font(.caption).foregroundStyle(.white.opacity(0.85))
                                }
                            }
                        }
                        .padding(16)
                        .background(Color.arkoCard)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
            }

            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 34, height: 34).background(.ultraThinMaterial).clipShape(Circle())
                    }
                    .padding(.trailing, 24).padding(.top, 16)
                }
                Spacer()
            }
        }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(color.opacity(0.12)).clipShape(Capsule())
    }
}

extension ExerciseDBResult: Identifiable {}
