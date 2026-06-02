import SwiftUI

// ════════════════════════════════════════════════════════════════════════════
// MARK: - AuthView (Login + Register)
// ════════════════════════════════════════════════════════════════════════════

struct AuthView: View {
    @StateObject private var auth = AuthManager.shared

    @State private var isRegister = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        ZStack {
            Color.arkoBg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    Spacer(minLength: 60)
                    logo
                    headline
                    formCard
                    dividerOr
                    socialButtons
                    toggleMode
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
            }
        }
    }

    // MARK: Logo

    private var logo: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.arkoLime)
                    .frame(width: 80, height: 80)
                Image(systemName: "figure.run")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.black)
            }
            Text("ARKO")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text("AI Fitness Coach")
                .font(.caption)
                .foregroundStyle(Color.arkoTextDim)
        }
    }

    // MARK: Headline

    private var headline: some View {
        VStack(spacing: 4) {
            Text(isRegister ? "Create Account" : "Welcome Back")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            Text(isRegister ? "Start your fitness journey" : "Login to continue")
                .font(.subheadline)
                .foregroundStyle(Color.arkoTextDim)
        }
    }

    // MARK: Form Card

    private var formCard: some View {
        VStack(spacing: 14) {
            if isRegister {
                inputField(icon: "person.fill", placeholder: "Name", text: $name)
            }
            inputField(icon: "envelope.fill", placeholder: "Email", text: $email,
                       keyboard: .emailAddress)
            inputField(icon: "lock.fill", placeholder: "Password", text: $password,
                       isSecure: true)

            if let error = auth.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                    Text(error)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Submit button
            Button {
                Task { await submit() }
            } label: {
                ZStack {
                    if auth.isLoading {
                        ProgressView().tint(.black)
                    } else {
                        Text(isRegister ? "Create Account" : "Login")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.black)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.arkoLime)
                .clipShape(Capsule())
            }
            .disabled(auth.isLoading || !isFormValid)
            .opacity(isFormValid ? 1 : 0.5)
            .padding(.top, 4)
        }
        .padding(20)
        .background(Color.arkoCard)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private func inputField(icon: String, placeholder: String,
                            text: Binding<String>, isSecure: Bool = false,
                            keyboard: UIKeyboardType = .default) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(Color.arkoLime)
                .frame(width: 20)
            Group {
                if isSecure {
                    SecureField("", text: text, prompt: Text(placeholder).foregroundColor(Color.arkoTextDim))
                } else {
                    TextField("", text: text, prompt: Text(placeholder).foregroundColor(Color.arkoTextDim))
                        .keyboardType(keyboard)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.arkoCard2)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Divider

    private var dividerOr: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
            Text("or").font(.caption).foregroundStyle(Color.arkoTextDim)
            Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
        }
    }

    // MARK: Social Buttons

    private var socialButtons: some View {
        // Google Sign-In
        Button {
            Task { await auth.signInWithGoogle() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "g.circle.fill")
                    .font(.system(size: 18))
                Text("Continue with Google")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color.arkoCard2)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
        }
    }

    // MARK: Toggle Mode

    private var toggleMode: some View {
        HStack(spacing: 4) {
            Text(isRegister ? "Already have an account?" : "Don't have an account?")
                .font(.caption)
                .foregroundStyle(Color.arkoTextDim)
            Button {
                withAnimation { isRegister.toggle(); auth.errorMessage = nil }
            } label: {
                Text(isRegister ? "Login" : "Register")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.arkoLime)
            }
        }
    }

    // MARK: Logic

    private var isFormValid: Bool {
        let baseValid = !email.isEmpty && password.count >= 6
        return isRegister ? (baseValid && !name.isEmpty) : baseValid
    }

    private func submit() async {
        if isRegister {
            await auth.register(email: email, password: password, name: name)
        } else {
            await auth.login(email: email, password: password)
        }
    }
}

struct AuthView_Previews: PreviewProvider {
    static var previews: some View {
        AuthView().preferredColorScheme(.dark)
    }
}
