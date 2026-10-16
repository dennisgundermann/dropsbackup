import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import SwiftUI
import UIKit

// MARK: - Google Sign In Manager

class GoogleSignInManager: NSObject, ObservableObject {

    @Published var isLoading = false
    @Published var errorMessage: String? = nil

    /// Wird gesetzt wenn die Google-E-Mail bereits unter einem anderen Provider
    /// (z.B. Apple) existiert — UI zeigt dann den Linking-Dialog.
    @Published var pendingLinkEmail: String? = nil

    /// Gespeichertes Google-Credential, das nach dem Apple-Re-Login verknüpft wird.
    private var pendingGoogleCredential: AuthCredential? = nil

    /// E-Mail des eingeloggten Google-Accounts (nur nach erfolgreichem Sign-In verfügbar)
    private(set) var lastGoogleEmail: String? = nil

    func signIn(completion: @escaping (Bool, Bool) -> Void) {
        isLoading = true
        errorMessage = nil

        guard let clientID = FirebaseApp.app()?.options.clientID else {
            DispatchQueue.main.async {
                self.isLoading = false
                self.errorMessage = "Google Sign-In konnte nicht initialisiert werden."
                completion(false, false)
            }
            return
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        guard let rootVC = topViewController() else {
            DispatchQueue.main.async {
                self.isLoading = false
                self.errorMessage = "Kein aktives Fenster gefunden."
                completion(false, false)
            }
            return
        }

        GIDSignIn.sharedInstance.signIn(withPresenting: rootVC) { [weak self] result, error in
            guard let self else { return }

            if let error = error {
                let nsError = error as NSError
                DispatchQueue.main.async {
                    self.isLoading = false
                    if nsError.code != GIDSignInError.canceled.rawValue {
                        self.errorMessage = "Google Sign-In fehlgeschlagen. Bitte nochmal versuchen."
                    }
                    completion(false, false)
                }
                return
            }

            guard let user = result?.user,
                  let idToken = user.idToken?.tokenString else {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = "Google Sign-In fehlgeschlagen. Bitte nochmal versuchen."
                    completion(false, false)
                }
                return
            }

            self.lastGoogleEmail = user.profile?.email

            if let given = user.profile?.givenName, !given.isEmpty {
                UserDefaults.standard.set(given, forKey: "ud_appleGivenName")
            }

            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: user.accessToken.tokenString
            )

            Task {
                do {
                    if Auth.auth().currentUser != nil {
                        try? Auth.auth().signOut()
                    }
                    let authResult = try await Auth.auth().signIn(with: credential)
                    let isNew = authResult.additionalUserInfo?.isNewUser ?? false
                    await MainActor.run {
                        self.isLoading = false
                        completion(true, isNew)
                    }
                } catch let error as NSError {
                    // ── Account-Linking: E-Mail existiert bereits unter Apple/anderem Provider ──
                    if error.code == AuthErrorCode.accountExistsWithDifferentCredential.rawValue,
                       let email = error.userInfo[AuthErrorUserInfoEmailKey] as? String {
                        await MainActor.run {
                            self.isLoading = false
                            self.pendingGoogleCredential = credential
                            self.pendingLinkEmail = email
                            completion(false, false)
                        }
                    } else {
                        await MainActor.run {
                            self.isLoading = false
                            self.errorMessage = "Google Login fehlgeschlagen. Bitte nochmal versuchen."
                            completion(false, false)
                        }
                    }
                }
            }
        }
    }

    /// Wird nach erfolgreichem Apple-Sign-In aufgerufen.
    /// Der User ist jetzt mit seinem Apple-Account eingeloggt (inklusive alter Daten).
    /// Diese Funktion verknüpft das gespeicherte Google-Credential mit diesem Account.
    func completeLinkingAfterAppleSignIn(completion: @escaping (Bool) -> Void) {
        guard let googleCredential = pendingGoogleCredential else {
            completion(false)
            return
        }
        isLoading = true
        Task {
            do {
                guard let user = Auth.auth().currentUser else {
                    throw NSError(domain: "Drops.GoogleLinking", code: -1)
                }
                try await user.link(with: googleCredential)
                await MainActor.run {
                    self.isLoading = false
                    self.pendingGoogleCredential = nil
                    self.pendingLinkEmail = nil
                    completion(true)
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = "Verknüpfung fehlgeschlagen. Bitte nochmal versuchen."
                    completion(false)
                }
            }
        }
    }

    func cancelLinking() {
        pendingGoogleCredential = nil
        pendingLinkEmail = nil
    }

    private func topViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let root = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { return nil }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        return top
    }
}

// MARK: - Google G Logo

/// Offizielles Google-G SVG aus dem Asset-Catalog. Punkt.
struct GoogleGLogo: View {
    let size: CGFloat
    var body: some View {
        Image("google_g")
            .resizable()
            .renderingMode(.original)
            .frame(width: size, height: size)
    }
}
