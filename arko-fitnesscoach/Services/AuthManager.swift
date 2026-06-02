import Foundation
import FirebaseAuth
import GoogleSignIn

// ════════════════════════════════════════════════════════════════════════════
// MARK: - AuthManager (Firebase Email/Password)
// ════════════════════════════════════════════════════════════════════════════

@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published var user: User?
    @Published var isAuthenticated = false
    @Published var errorMessage: String?
    @Published var isLoading = false

    private var handle: AuthStateDidChangeListenerHandle?

    private init() {
        // Listen perubahan auth state (auto login kalau sudah pernah)
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.user = user
                self?.isAuthenticated = (user != nil)
            }
        }
    }

    // MARK: Register

    func register(email: String, password: String, name: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            // Set display name
            let change = result.user.createProfileChangeRequest()
            change.displayName = name
            try await change.commitChanges()
            await MainActor.run {
                self.user = result.user
                self.isAuthenticated = true
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = Self.friendlyMessage(error)
                self.isLoading = false
            }
        }
    }

    // MARK: Login

    func login(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            await MainActor.run {
                self.user = result.user
                self.isAuthenticated = true
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = Self.friendlyMessage(error)
                self.isLoading = false
            }
        }
    }

    // MARK: Google Sign-In

    func signInWithGoogle() async {
        isLoading = true
        errorMessage = nil
        do {
            try await SocialAuth.signInWithGoogle()
            await MainActor.run { self.isLoading = false }
        } catch {
            await MainActor.run {
                // User cancel tidak perlu tampil error
                let nsError = error as NSError
                if nsError.code != GIDSignInError.canceled.rawValue {
                    self.errorMessage = Self.friendlyMessage(error)
                }
                self.isLoading = false
            }
        }
    }

    // MARK: Logout

    func logout() {
        do {
            try Auth.auth().signOut()
            user = nil
            isAuthenticated = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Helpers

    var displayName: String {
        user?.displayName ?? user?.email?.components(separatedBy: "@").first ?? "Athlete"
    }

    var email: String {
        user?.email ?? ""
    }

    /// Ubah error code Firebase jadi pesan yang ramah
    private static func friendlyMessage(_ error: Error) -> String {
        guard let code = AuthErrorCode.Code(rawValue: (error as NSError).code) else {
            return error.localizedDescription
        }
        switch code {
        case .invalidEmail:        return "Email format is not valid."
        case .emailAlreadyInUse:   return "This email is already registered. Try logging in."
        case .weakPassword:        return "Password must be at least 6 characters."
        case .wrongPassword:       return "Incorrect password. Please try again."
        case .userNotFound:        return "No account found with this email."
        case .networkError:        return "Network error. Check your connection."
        default:                   return error.localizedDescription
        }
    }
}
