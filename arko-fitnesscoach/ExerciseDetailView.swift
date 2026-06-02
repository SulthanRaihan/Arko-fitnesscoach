import SwiftUI

// ════════════════════════════════════════════════════════════════════════════
// MARK: - ExerciseDetailView
// Shows exercise info + image fetched from WGER API.
// ════════════════════════════════════════════════════════════════════════════

struct ExerciseDetailView: View {
    let exercise: Exercise
    @Environment(\.dismiss) private var dismiss

    @State private var imageURL: URL?
    @State private var imageLoaded = false

    var body: some View {
        ZStack {
            Color.arkoBg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    imageHeader
                    VStack(spacing: 16) {
                        infoCard
                        instructionsCard
                        muscleCard
                        Spacer(minLength: 60)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }

            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .padding(.trailing, 20)
                    .padding(.top, 56)
                }
                Spacer()
            }
        }
        .ignoresSafeArea(edges: .top)
        .task { await loadImage() }
    }

    // MARK: - Image header

    private var imageHeader: some View {
        ZStack {
            // Background gradient placeholder
            LinearGradient(
                colors: [Color.arkoCard, Color.arkoCard2],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: 280)

            if let url = imageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(height: 280)
                            .clipped()
                            .transition(.opacity)
                    case .failure:
                        exercisePlaceholder
                    case .empty:
                        ProgressView().tint(Color.arkoLime)
                    @unknown default:
                        exercisePlaceholder
                    }
                }
                .frame(height: 280)
            } else if imageLoaded {
                exercisePlaceholder
            } else {
                ProgressView().tint(Color.arkoLime)
            }

            // Gradient overlay at bottom for title readability
            VStack {
                Spacer()
                LinearGradient(
                    colors: [.clear, Color.arkoBg],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 100)
            }
        }
        .frame(height: 280)
    }

    private var exercisePlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: exercise.icon)
                .font(.system(size: 56))
                .foregroundStyle(Color.arkoLime.opacity(0.6))
            Text("No image available")
                .font(.caption)
                .foregroundStyle(Color.arkoTextDim)
        }
    }

    // MARK: - Info card

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.name)
                        .font(.title3.weight(.bold))
                    Text(exercise.primaryMuscle.rawValue.capitalized)
                        .font(.subheadline)
                        .foregroundStyle(Color.arkoTextDim)
                }
                Spacer()
                // Type badge
                Text(exercise.type.rawValue.capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.arkoLime)
                    .clipShape(Capsule())
            }

            HStack(spacing: 16) {
                infoBadge(icon: "figure.arms.open",
                          label: exercise.primaryMuscle.rawValue.capitalized,
                          color: Color.arkoLime)
                if exercise.supportsFormCheck {
                    infoBadge(icon: "camera.fill", label: "Form Check", color: .orange)
                }
            }
        }
        .arkoCard()
    }

    private func infoBadge(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Instructions card

    private var instructionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("How to Perform", systemImage: "list.number")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.arkoLime)

            Text(exercise.instructions.isEmpty
                 ? "No instructions available."
                 : exercise.instructions)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .lineSpacing(4)
        }
        .arkoCard()
    }

    // MARK: - Muscle card

    private var muscleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Targeted Muscles", systemImage: "figure.arms.open")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.arkoLime)

            BodyMapView(muscleLastTrained: [exercise.primaryMuscle.rawValue: Date()])
                .frame(maxWidth: .infinity)
        }
        .arkoCard()
    }

    // MARK: - Data loading

    private func loadImage() async {
        imageURL = await WGERService.shared.imageURL(for: exercise.name)
        imageLoaded = true
    }
}

struct ExerciseDetailView_Previews: PreviewProvider {
    static var previews: some View {
        ExerciseDetailView(exercise: ExerciseLibrary.all.first!)
            .preferredColorScheme(.dark)
    }
}
