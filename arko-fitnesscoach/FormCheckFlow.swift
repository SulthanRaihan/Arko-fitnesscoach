import SwiftUI

// ════════════════════════════════════════════════════════════════════════════
// MARK: - Form Check trackable exercises
// 5 gerakan yang punya konfigurasi deteksi (ExerciseConfig). Struktur ini
// gampang ditambah: tinggal tambah entry + ExerciseConfig.all.
// ════════════════════════════════════════════════════════════════════════════

struct FormCheckExercise: Identifiable {
    let id = UUID()
    let key: String          // cocok dengan ExerciseConfig.all
    let icon: String
    let isTimeBased: Bool
    let defaultTarget: Int   // reps, atau detik (plank)

    /// Exercise dari library untuk GIF + instruksi
    var libraryExercise: Exercise? { ExerciseLibrary.all.first { $0.name == key } }

    static let all: [FormCheckExercise] = [
        FormCheckExercise(key: "Squat",    icon: "figure.strengthtraining.functional", isTimeBased: false, defaultTarget: 15),
        FormCheckExercise(key: "Push-up",  icon: "figure.strengthtraining.traditional", isTimeBased: false, defaultTarget: 12),
        FormCheckExercise(key: "Deadlift", icon: "dumbbell.fill",                        isTimeBased: false, defaultTarget: 10),
        FormCheckExercise(key: "Lunge",    icon: "figure.walk",                          isTimeBased: false, defaultTarget: 12),
        FormCheckExercise(key: "Plank",    icon: "figure.core.training",                 isTimeBased: true,  defaultTarget: 45),
    ]
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - FormCheckTabView (entry point — pilih gerakan dulu)
// ════════════════════════════════════════════════════════════════════════════

struct FormCheckTabView: View {
    private let cols = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.arkoBg.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        LazyVGrid(columns: cols, spacing: 14) {
                            ForEach(FormCheckExercise.all) { ex in
                                NavigationLink(value: ex.key) {
                                    exerciseCard(ex)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Spacer(minLength: 110)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                }
            }
            .navigationDestination(for: String.self) { key in
                if let ex = FormCheckExercise.all.first(where: { $0.key == key }) {
                    FormSetupView(formExercise: ex)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("AI Camera").font(.caption).foregroundStyle(Color.arkoTextDim)
            Text("Form Check").font(.title2.weight(.bold)).foregroundStyle(.white)
            Text("Pick a movement — we'll count reps and check your form live.")
                .font(.caption).foregroundStyle(Color.arkoTextDim)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private func exerciseCard(_ ex: FormCheckExercise) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Color.white)
                if let lib = ex.libraryExercise {
                    // Card = gambar statis (ringan). GIF animasi hanya di detail.
                    ExerciseGIFView(exercise: lib, resolution: 180, animated: false).padding(6)
                } else {
                    Image(systemName: ex.icon).font(.system(size: 34)).foregroundStyle(Color.arkoTeal)
                }
            }
            .frame(height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            Text(ex.key).font(.subheadline.weight(.bold)).foregroundStyle(.white)
            HStack(spacing: 5) {
                Image(systemName: ex.isTimeBased ? "clock.fill" : "number")
                    .font(.system(size: 10))
                Text(ex.isTimeBased ? "Timed hold" : "Reps tracked")
                    .font(.caption2)
            }
            .foregroundStyle(Color.arkoLime)
        }
        .padding(12)
        .background(Color.arkoCard)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - FormSetupView (detail + GIF + atur target → Start)
// ════════════════════════════════════════════════════════════════════════════

struct FormSetupView: View {
    let formExercise: FormCheckExercise
    @State private var target: Int = 0
    @State private var showCamera = false

    private var lib: Exercise? { formExercise.libraryExercise }

    var body: some View {
        ZStack {
            Color.arkoBg.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    // GIF
                    ZStack {
                        Color.white
                        if let lib { ExerciseGIFView(exercise: lib, resolution: 360).padding(20) }
                    }
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                    // Title + muscle
                    VStack(alignment: .leading, spacing: 4) {
                        Text(formExercise.key).font(.title2.weight(.bold)).foregroundStyle(.white)
                        if let lib {
                            Text(lib.primaryMuscle.rawValue.capitalized)
                                .font(.subheadline).foregroundStyle(Color.arkoTextDim)
                        }
                    }

                    // Instructions
                    if let lib, !lib.instructions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("How to Perform", systemImage: "list.number")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Color.arkoLime)
                            Text(lib.instructions)
                                .font(.subheadline).foregroundStyle(.white.opacity(0.85)).lineSpacing(4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16).background(Color.arkoCard)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    targetCard
                    // ruang agar konten tidak ketutup tombol + tab bar
                    Spacer(minLength: 150)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
            }

            // Sticky Start button — diangkat di atas floating tab bar
            VStack {
                Spacer()
                Button { showCamera = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                        Text("Start with Camera")
                    }
                    .font(.subheadline.weight(.bold)).foregroundStyle(.black)
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .background(Color.arkoLime).clipShape(Capsule())
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 110)   // clear the custom tab bar
            }
        }
        .navigationTitle("Setup")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if target == 0 { target = formExercise.defaultTarget } }
        .fullScreenCover(isPresented: $showCamera) {
            FormCheckView(
                presetExercise: formExercise.key,
                repTarget: target,
                onFinish: { _ in showCamera = false }
            )
        }
    }

    // MARK: Target stepper

    private var targetCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(formExercise.isTimeBased ? "Target Duration" : "Target Reps",
                  systemImage: formExercise.isTimeBased ? "clock.fill" : "number")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Color.arkoLime)

            HStack(spacing: 20) {
                stepButton("minus") { adjust(-1) }
                Spacer()
                Text(formExercise.isTimeBased
                     ? String(format: "%d:%02d", target / 60, target % 60)
                     : "\(target)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.white).monospacedDigit()
                Text(formExercise.isTimeBased ? "min:sec" : "reps")
                    .font(.caption).foregroundStyle(Color.arkoTextDim)
                Spacer()
                stepButton("plus") { adjust(1) }
            }

            // Quick presets
            HStack(spacing: 8) {
                ForEach(presets, id: \.self) { p in
                    Button { target = p } label: {
                        Text(formExercise.isTimeBased ? "\(p)s" : "\(p)")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(target == p ? Color.arkoLime : Color.arkoCard2)
                            .foregroundStyle(target == p ? .black : .white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16).background(Color.arkoCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var presets: [Int] {
        formExercise.isTimeBased ? [30, 45, 60, 90] : [8, 10, 12, 15, 20]
    }

    private func stepButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(Color.arkoCard2).clipShape(Circle())
        }
    }

    private func adjust(_ delta: Int) {
        if formExercise.isTimeBased {
            target = max(15, min(300, target + delta * 15))
        } else {
            target = max(1, min(100, target + delta))
        }
    }
}
