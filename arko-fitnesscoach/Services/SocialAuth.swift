import Foundation
import FirebaseAuth
import GoogleSignIn
import FirebaseCore
import UIKit

// ════════════════════════════════════════════════════════════════════════════
// MARK: - Social Auth Helper (Google → Firebase)
// ════════════════════════════════════════════════════════════════════════════

enum SocialAuth {

    // MARK: Google → Firebase

    @MainActor
    static func signInWithGoogle() async throws {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw NSError(domain: "ARKO", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Missing Firebase client ID."])
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        guard let rootVC = Self.rootViewController() else {
            throw NSError(domain: "ARKO", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No root view controller."])
        }

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)
        guard let idToken = result.user.idToken?.tokenString else {
            throw NSError(domain: "ARKO", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Google ID token missing."])
        }
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )
        _ = try await Auth.auth().signIn(with: credential)
    }

    // MARK: Helper — get root VC

    @MainActor
    private static func rootViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) else {
            return nil
        }
        return window.rootViewController
    }
}
