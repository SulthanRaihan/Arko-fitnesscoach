import SwiftUI

// ════════════════════════════════════════════════════════════════════════════
// MARK: - ChatView (ARKO Coach)
// Context-aware fitness/nutrition chatbot. Sends the user's real data
// (goal, streak, workouts, muscles) as context so answers are personalized.
// Scope is guarded server-side (fitness/nutrition only).
// ════════════════════════════════════════════════════════════════════════════

private struct ChatMessage: Identifiable {
    let id = UUID()
    let role: String      // "user" | "assistant"
    let content: String
}

struct ChatView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var auth = AuthManager.shared
    @StateObject private var healthKit = HealthKitManager.shared
    @StateObject private var historyStore = FirestoreWorkoutHistoryStore.shared

    @State private var messages: [ChatMessage] = [
        ChatMessage(role: "assistant",
                    content: "Hey! I'm your ARKO Coach 💪 Ask me about workouts, exercise form, nutrition, or your progress.")
    ]
    @State private var input = ""
    @State private var isSending = false

    private let suggestions = [
        "What should I eat to hit my goal?",
        "Which muscle should I train next?",
        "How many rest days do I need?",
        "Give me a quick home workout"
    ]

    var body: some View {
        ZStack {
            Color.arkoBg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                messagesList
                if messages.count <= 1 { suggestionChips }
                inputBar
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.arkoLime).frame(width: 40, height: 40)
                Image(systemName: "sparkles").foregroundStyle(.black)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("ARKO Coach").font(.headline).foregroundStyle(.white)
                Text("Fitness & nutrition assistant")
                    .font(.caption2).foregroundStyle(Color.arkoTextDim)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 34, height: 34).background(Color.arkoCard).clipShape(Circle())
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(Color.arkoBg)
    }

    // MARK: Messages

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(messages) { msg in
                        bubble(msg).id(msg.id)
                    }
                    if isSending {
                        HStack {
                            typingIndicator
                            Spacer()
                        }
                        .id("typing")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .onChange(of: messages.count) { _ in
                if let last = messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private func bubble(_ msg: ChatMessage) -> some View {
        let isUser = msg.role == "user"
        return HStack {
            if isUser { Spacer(minLength: 40) }
            Text(msg.content)
                .font(.subheadline)
                .foregroundStyle(isUser ? .black : .white)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(isUser ? Color.arkoLime : Color.arkoCard)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            if !isUser { Spacer(minLength: 40) }
        }
    }

    private var typingIndicator: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle().fill(Color.arkoTextDim).frame(width: 7, height: 7)
                    .opacity(0.5)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color.arkoCard).clipShape(RoundedRectangle(cornerRadius: 18))
    }

    // MARK: Suggestions

    private var suggestionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { s in
                    Button { send(s) } label: {
                        Text(s)
                            .font(.caption).foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color.arkoCard).clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 8)
        }
    }

    // MARK: Input bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask your coach…", text: $input, axis: .vertical)
                .lineLimit(1...4)
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color.arkoCard).clipShape(RoundedRectangle(cornerRadius: 20))

            Button { send(input) } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(.black)
                    .frame(width: 40, height: 40)
                    .background(canSend ? Color.arkoLime : Color.arkoCard2)
                    .clipShape(Circle())
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    // MARK: Send

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }
        messages.append(ChatMessage(role: "user", content: trimmed))
        input = ""
        isSending = true

        let payload = messages.map { ["role": $0.role, "content": $0.content] }
        let ctx = buildContext()

        Task {
            let reply: String
            do {
                reply = try await ARKOAPIService.shared.sendChat(messages: payload, context: ctx)
            } catch {
                reply = "I'm having trouble connecting right now. Make sure the coach is online and try again!"
            }
            await MainActor.run {
                messages.append(ChatMessage(role: "assistant", content: reply))
                isSending = false
            }
        }
    }

    // MARK: Build user context

    private func buildContext() -> [String: Any] {
        let profile = UserProfile.load()
        let cal = Calendar.current

        // Recent workout names
        let recent = historyStore.sessions.prefix(5).map { $0.name }

        // Muscles trained last 7 days
        let weekAgo = cal.date(byAdding: .day, value: -7, to: Date())!
        var muscleCounts: [String: Int] = [:]
        for s in historyStore.sessions where s.startedAt >= weekAgo {
            for b in s.exercises {
                muscleCounts[b.exercise.primaryMuscle.rawValue, default: 0] += 1
            }
        }
        let musclesStr = muscleCounts.map { "\($0.key): \($0.value)×" }.joined(separator: ", ")

        return [
            "name": auth.displayName,
            "fitness_level": profile.fitnessLevel,
            "calorie_goal": profile.calorieGoal,
            "active_energy": Int(healthKit.activeEnergy),
            "steps": healthKit.steps,
            "streak_days": currentStreak,
            "recent_workouts": Array(recent),
            "muscles_trained_7d": musclesStr.isEmpty ? "none yet" : musclesStr
        ]
    }

    private var currentStreak: Int {
        let cal = Calendar.current
        let completed = historyStore.sessions.filter { $0.isCompleted }
        var streak = 0
        var checkDate = Date()
        while completed.contains(where: { cal.isDate($0.startedAt, inSameDayAs: checkDate) }) {
            streak += 1
            checkDate = cal.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
        }
        return streak
    }
}

struct ChatView_Previews: PreviewProvider {
    static var previews: some View {
        ChatView().preferredColorScheme(.dark)
    }
}
