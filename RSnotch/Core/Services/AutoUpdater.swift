import Observation
import Sparkle

// MARK: - AutoUpdater
//
// Mises a jour hors App Store, via Sparkle (§ project.yml pour la
// justification de cette unique dependance tierce).
//
// CE QUE SPARKLE VERIFIE, ET CE QU'IL NE VERIFIE PAS. La notarisation Apple
// protege l'app qu'on ouvre manuellement ; elle ne dit rien du fichier qu'on
// vient de telecharger avant de l'ouvrir. Sparkle comble cet intervalle :
// chaque mise a jour listee dans l'appcast porte une signature EdDSA
// (generee par `sign_update`, cle privee dans le Trousseau de la machine qui
// publie) que l'app verifie AVANT d'installer quoi que ce soit. Un appcast
// modifie sans la cle privee correspondante est un appcast rejete.
//
// Verification explicite plutot qu'automatique : `checkForUpdates()` est
// invoque depuis le menu ET au demarrage (verification silencieuse, en
// tache de fond) — l'installation, elle, ne se fait jamais sans que l'
// utilisateur ait cliqué « Installer et relancer » dans la fenetre que
// Sparkle affiche lui-meme.

@MainActor
@Observable
final class AutoUpdater {

    static let shared = AutoUpdater()

    private let controller: SPUStandardUpdaterController

    /// Verifications automatiques en tache de fond, activables depuis les
    /// Reglages. Actives par defaut : un correctif de securite ne sert a
    /// rien s'il faut penser a aller le chercher soi-meme.
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }

    var lastUpdateCheckDate: Date? { controller.updater.lastUpdateCheckDate }

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// Verification explicite, avec interface : Sparkle affiche lui-meme la
    /// fenetre de progression puis, si une mise a jour existe, la boite de
    /// dialogue de confirmation. Rien n'est telecharge ni installe avant
    /// que l'utilisateur y ait cliqué.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
