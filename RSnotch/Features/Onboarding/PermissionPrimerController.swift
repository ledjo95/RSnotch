import AppKit
import SwiftUI

// MARK: - PermissionPrimerController
//
// Presente l'invite de premiere ouverture, au plus une fois, et seulement si
// elle a un sens : la fonction est demandee, la permission manque encore.

@MainActor
final class PermissionPrimerController {

    /// Marqueur d'invite deja montree. Meme forme que `AppContainer.migrationKey` :
    /// une cle brute plutot qu'un reglage utilisateur, car ce n'est pas un choix
    /// mais un jalon d'installation.
    private static let shownKey = "onboarding.hudPrimerShown"

    private var window: NSWindow?

    /// Montre l'invite si — et seulement si — les trois conditions tiennent :
    /// premiere fois, remplacement du HUD active, Accessibilite pas encore
    /// accordee. Sinon ne fait rien.
    func presentIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.shownKey) else { return }
        guard AppSettings.shared.replaceSystemHUD else { return }
        guard !MediaKeyInterceptor.shared.isTrusted else {
            // Deja autorise (rare, mais possible si l'utilisateur avait deja
            // accorde l'acces a un build precedent) : rien a expliquer. On pose
            // quand meme le marqueur pour ne pas reevaluer a chaque lancement.
            defaults.set(true, forKey: Self.shownKey)
            return
        }

        defaults.set(true, forKey: Self.shownKey)
        present()
    }

    #if DEBUG
    /// Montre l'invite sans condition, pour l'eprouver visuellement.
    func presentForDebug() { present() }
    #endif

    private func present() {
        let view = PermissionPrimerView(
            onAuthorize: { [weak self] in
                // Declenche la vraie boite systeme sur l'instance PARTAGEE :
                // c'est elle que le controleur ecoute pour armer le tap.
                MediaKeyInterceptor.shared.requestTrust()
                self?.close()
            },
            onDismiss: { [weak self] in self?.close() }
        )

        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "RSnotch"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func close() {
        window?.close()
        window = nil
    }
}
