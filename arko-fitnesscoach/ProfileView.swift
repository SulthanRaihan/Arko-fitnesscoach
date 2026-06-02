import SwiftUI

struct ProfileView: View {
    @State private var profile = UserProfile.load()
    @StateObject private var notifications = NotificationService.shared
    @ObservedObject private var auth = AuthManager.shared
    @StateObject private var historyStore = FirestoreWorkoutHistoryStore.shared

    var body: some View {
        ZStack {
            Color.arkoBg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    avatarHeader
                    goalsCard
                    settingsCard
                    aboutCard
                    logoutButton
                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
        }
        .task { _ = await historyStore.loadAllSessions() }
    }

    // MARK: - Streak calculation

    private var currentStreak: Int {
        let cal = Calendar.current
        let completed = historyStore.sessions.filter { $0.isCompleted }
        var streak = 0
        var checkDate = Date()
        while true {
            let hasSession = completed.contains { cal.isDate($0.startedAt, inSameDayAs: checkDate) }
            if hasSession {
                streak += 1
                checkDate = cal.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
            } else {
                break
            }
        }
        return streak
    }

    private var logoutButton: some View {
        Button {
            auth.logout()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                Text("Log Out")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.arkoCard)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Avatar Header

    private var avatarHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.arkoLime)
                    .frame(width: 80, height: 80)
                Text(String(auth.displayName.prefix(1)).uppercased())
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.black)
            }

            Text(auth.displayName)
                .font(.title3.weight(.bold))
            Text(auth.email.isEmpty ? "ARKO Member" : auth.email)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 24) {
                statBadge(value: "\(profile.calorieGoal)", label: "kcal Goal")
                Divider().frame(height: 30)
                statBadge(value: profile.fitnessLevel.capitalized, label: "Level")
                Divider().frame(height: 30)
                statBadge(value: "\(currentStreak)", label: "Day Streak")
            }
            .arkoCard(padding: 16)
        }
        .frame(maxWidth: .infinity)
        .arkoCard(padding: 20)
    }

    private func statBadge(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.arkoTeal)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Goals Card

    private var goalsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Goals", systemImage: "target")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.arkoTeal)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Daily Calorie Goal", systemImage: "flame.fill")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(Int(profile.calorieGoal)) kcal")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.arkoTeal)
                }

                Slider(value: Binding(
                    get: { Double(profile.calorieGoal) },
                    set: {
                        profile.calorieGoal = Int($0)
                        profile.save()
                    }
                ), in: 200...1000, step: 50)
                .tint(Color.arkoTeal)

                HStack {
                    Text("200")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("1000")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack {
                Text("Fitness Level")
                    .font(.subheadline)
                Spacer()
                Picker("", selection: Binding(
                    get: { profile.fitnessLevel },
                    set: {
                        profile.fitnessLevel = $0
                        profile.save()
                    }
                )) {
                    Text("Beginner").tag("beginner")
                    Text("Intermediate").tag("intermediate")
                    Text("Advanced").tag("advanced")
                }
                .pickerStyle(.menu)
                .tint(Color.arkoTeal)
            }
        }
        .arkoCard()
    }

    // MARK: - Settings Card

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Settings", systemImage: "gearshape.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.arkoTeal)
                .padding(.bottom, 14)

            settingsRow(icon: "bell.fill", color: .orange, title: "Workout Reminders") {
                Toggle("", isOn: Binding(
                    get: { notifications.isAuthorized },
                    set: { enabled in
                        if enabled {
                            Task { await notifications.requestAuthorization() }
                        } else {
                            notifications.cancelAll()
                        }
                    }
                ))
                .tint(Color.arkoTeal)
            }

            Divider().padding(.vertical, 8)

            settingsRow(icon: "heart.fill", color: .red, title: "Apple Health") {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider().padding(.vertical, 8)

            settingsRow(icon: "sparkles", color: Color.arkoTeal, title: "AI Coach Settings") {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .arkoCard()
    }

    private func settingsRow<T: View>(icon: String, color: Color, title: String, @ViewBuilder trailing: () -> T) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(color)
            }
            Text(title)
                .font(.subheadline)
            Spacer()
            trailing()
        }
    }

    // MARK: - About Card

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("About ARKO", systemImage: "info.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.arkoTeal)

            HStack {
                Text("Version")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("1.0.0")
                    .font(.subheadline.weight(.medium))
            }
            Divider()
            HStack {
                Text("AI Model")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Llama 3.3 via Groq")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.arkoTeal)
            }

            Text("ARKO uses on-device AI for form analysis. Always consult a professional before starting a new fitness routine.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .arkoCard()
    }
}

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView()
    }
}
