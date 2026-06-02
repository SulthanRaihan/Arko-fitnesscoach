import SwiftUI
import FirebaseCore
import GoogleSignIn

// MARK: - Firebase AppDelegate

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        return true
    }

    // Handle Google Sign-In callback URL
    func application(_ app: UIApplication, open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        return GIDSignIn.sharedInstance.handle(url)
    }
}

// MARK: - ARKO Design System
// Defined here so it compiles before any View file

extension Color {
    // Dark theme + neon lime accent (MuseFit-inspired)
    static let arkoBg      = Color(red: 0.07, green: 0.07, blue: 0.08)   // near black
    static let arkoCard    = Color(red: 0.13, green: 0.13, blue: 0.15)   // dark card
    static let arkoCard2   = Color(red: 0.18, green: 0.18, blue: 0.20)   // lighter card
    static let arkoLime    = Color(red: 0.80, green: 0.95, blue: 0.25)   // neon lime (primary)
    static let arkoTeal    = Color(red: 0.80, green: 0.95, blue: 0.25)   // alias → lime
    static let arkoGreen   = Color(red: 0.55, green: 0.85, blue: 0.35)   // green
    static let arkoTabBar  = Color(red: 0.07, green: 0.07, blue: 0.08)
    static let arkoText    = Color.white
    static let arkoTextDim = Color.white.opacity(0.55)
}

extension View {
    func arkoCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(Color.arkoCard)
            .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

// MARK: - App Entry Point

@main
struct arko_fitnesscoachApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - RootView (gate: auth → main app)

struct RootView: View {
    @StateObject private var auth = AuthManager.shared

    var body: some View {
        Group {
            if auth.isAuthenticated {
                ContentView()
                    .task { await WGERSyncService.shared.loadOrSync() }
            } else {
                AuthView()
            }
        }
    }
}
