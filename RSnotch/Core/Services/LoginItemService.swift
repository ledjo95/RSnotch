import Observation
import OSLog
import ServiceManagement

private let loginLog = Logger(subsystem: "com.varicube.RSnotch", category: "login")

// MARK: - LoginItemService
//
// Lancement au demarrage de session.
//
// `SMAppService.mainApp` est l'API publique prevue pour ca depuis macOS 13, et
// la seule utilisable depuis le bac a sable : elle enregistre l'app elle-meme
// comme element d'ouverture, sans helper prive ni ecriture dans
// ~/Library/LaunchAgents (interdite en sandbox). Aucun entitlement requis.
//
// L'etat n'est PAS duplique dans UserDefaults : c'est le systeme qui fait foi.
// L'utilisateur peut retirer l'element depuis Reglages Systeme > Ouverture, et
// un booleen local se desynchroniserait sans jamais s'en apercevoir.

@MainActor
@Observable
final class LoginItemService {

    /// Vrai si l'app est enregistree ET active.
    private(set) var isEnabled: Bool = false
    /// Vrai quand l'utilisateur a refuse l'element depuis Reglages Systeme :
    /// l'app ne peut pas passer outre, il faut le dire au lieu de laisser
    /// l'interrupteur revenir en arriere sans explication.
    private(set) var requiresApproval = false
    private(set) var lastError: String?

    private let service = SMAppService.mainApp

    init() {
        refresh()
    }

    func refresh() {
        let status = service.status
        isEnabled = status == .enabled
        requiresApproval = status == .requiresApproval
        loginLog.notice("statut élément d'ouverture : \(String(describing: status))")
    }

    func setEnabled(_ enabled: Bool) {
        lastError = nil
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            // Cas courant hors App Store : une app lancee depuis un dossier
            // temporaire (DerivedData, quarantaine) est refusee. Le message
            // systeme est plus utile qu'un echec muet.
            lastError = error.localizedDescription
            loginLog.error("bascule refusée : \(error.localizedDescription, privacy: .public)")
        }
        refresh()
    }

    /// Ouvre le volet « Ouverture et extensions » des Reglages Systeme, ou
    /// l'utilisateur peut approuver un element mis en attente.
    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
