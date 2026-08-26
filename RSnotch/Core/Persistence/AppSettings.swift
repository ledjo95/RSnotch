import Foundation
import Observation
import SwiftUI

// MARK: - AppSettings
//
// Reglages legers, stockes dans UserDefaults (conteneur sandbox de l'app).
// SwiftData est reserve aux donnees a structure et volume — apps epinglees,
// historique du presse-papiers, preferences par Space. Un enum de trois cas
// n'a pas besoin d'un magasin d'objets.
//
// Aucune donnee ne quitte l'appareil.

@MainActor
@Observable
final class AppSettings {

    static let shared = AppSettings()

    private enum Key {
        static let glassIntensity = "panel.glassIntensity"
        static let quoteText = "widget.quote.text"
        static let spaceTint = "panel.space.tint"
        static let clipboardLimit = "clipboard.historyLimit"
        static let panelWidth = "panel.width"
        static let emptyPocketOnLaunch = "pocket.emptyOnLaunch"
        static let panelEnabled = "panel.enabled"
        static let openOnHover = "panel.openOnHover"
        static let hoverDelay = "panel.hoverDelayMilliseconds"
        static let screenPreference = "panel.screenPreference"
        static let showWithoutNotch = "panel.showWithoutNotch"
        static let simulatedBarWidth = "panel.simulatedBarWidth"
        static let expandOnLaunch = "panel.expandOnLaunch"
        static let volumeHUD = "hud.volume"
        static let brightnessHUD = "hud.brightness"
        static let replaceSystemHUD = "hud.replaceSystem"
        static let showLauncherLabels = "launcher.showLabels"
    }

    static let defaultQuote = "Continue, tu fais du bon travail"


    private let defaults: UserDefaults

    // MARK: Reglages

    var glassIntensity: GlassIntensity {
        didSet { defaults.set(glassIntensity.rawValue, forKey: Key.glassIntensity) }
    }

    /// Vide la Pocket a chaque lancement. Actif par defaut : la Pocket est un
    /// sas de transfert, pas un dossier d'archives, et laisser trainer des
    /// copies de fichiers personnels n'est pas un bon defaut.
    var emptyPocketOnLaunch: Bool {
        didSet { defaults.set(emptyPocketOnLaunch, forKey: Key.emptyPocketOnLaunch) }
    }

    /// Largeur du panneau etendu.
    var panelWidth: PanelWidth {
        didSet { defaults.set(panelWidth.rawValue, forKey: Key.panelWidth) }
    }

    /// Nombre d'entrees conservees dans l'historique du presse-papiers.
    /// Les favoris ne sont pas comptes : les epingler, c'est justement les
    /// soustraire a la purge.
    var clipboardLimit: Int {
        didSet { defaults.set(clipboardLimit, forKey: Key.clipboardLimit) }
    }

    /// Texte du widget Citation. Modifiable ici et non dans le panneau : la
    /// fenetre du notch est non activable, elle ne recoit pas le clavier.
    /// Teinte du verre selon le bureau actif (§3.10). Reglable : l'heuristique
    /// de reconnaissance des bureaux est faillible par nature, et certains
    /// preferent une apparence stable.
    var spaceTintEnabled: Bool {
        didSet { defaults.set(spaceTintEnabled, forKey: Key.spaceTint) }
    }

    var quoteText: String {
        didSet { defaults.set(quoteText, forKey: Key.quoteText) }
    }

    // MARK: Encoche active (§3.9)

    /// Coupe le panneau sans quitter l'app : la fenetre est retiree, l'icone de
    /// la barre des menus reste, et tous les services d'ecoute s'arretent.
    /// Utile en presentation ou en plein ecran, ou une bande qui s'ouvre au
    /// survol du haut de l'ecran gene plus qu'elle n'aide.
    var panelEnabled: Bool {
        didSet { defaults.set(panelEnabled, forKey: Key.panelEnabled) }
    }

    /// Ouverture au survol. Desactive, seul un clic sur l'encoche ouvre le
    /// panneau — c'est ce que demandent ceux qui visent souvent la barre des
    /// menus et n'apprecient pas qu'une bande se deploie au passage.
    var openOnHover: Bool {
        didSet { defaults.set(openOnHover, forKey: Key.openOnHover) }
    }

    /// Temps de survol avant ouverture, en millisecondes. Le vrai reglage de
    /// « sensibilite » : trop court, le panneau s'ouvre en traversant ; trop
    /// long, il parait inerte.
    var hoverDelayMilliseconds: Int {
        didSet { defaults.set(hoverDelayMilliseconds, forKey: Key.hoverDelay) }
    }

    /// Ecran qui porte le panneau (§2.6).
    var screenPreference: ScreenPreference {
        didSet { defaults.set(screenPreference.rawValue, forKey: Key.screenPreference) }
    }

    /// Barre simulee sur un ecran sans encoche. Desactive, le panneau ne
    /// s'affiche que sur un ecran a encoche physique.
    var showWithoutNotch: Bool {
        didSet { defaults.set(showWithoutNotch, forKey: Key.showWithoutNotch) }
    }

    /// Largeur de cette barre simulee, en points. Sur un ecran sans encoche,
    /// rien n'impose de gabarit : c'est a l'utilisateur de dire quelle zone du
    /// haut de l'ecran il accepte de reserver.
    var simulatedBarWidth: Double {
        didSet { defaults.set(simulatedBarWidth, forKey: Key.simulatedBarWidth) }
    }

    /// Ouvre le panneau au lancement, au lieu de le laisser replie.
    var expandOnLaunch: Bool {
        didSet { defaults.set(expandOnLaunch, forKey: Key.expandOnLaunch) }
    }

    // MARK: Jauges systeme

    /// Jauge de volume dans l'encoche. Elle ne remplace PAS celle de macOS —
    /// aucune API publique ne permet de masquer le HUD systeme — elle s'y
    /// ajoute. Certains preferent donc n'en garder qu'une.
    var volumeHUDEnabled: Bool {
        didSet { defaults.set(volumeHUDEnabled, forKey: Key.volumeHUD) }
    }

    /// Jauge de luminosite. Repose sur `DisplayServices`, framework prive
    /// isole dans `BrightnessControl` : reglable, et coupee d'office si les
    /// symboles ne peuvent pas etre resolus sur la machine.
    var brightnessHUDEnabled: Bool {
        didSet { defaults.set(brightnessHUDEnabled, forKey: Key.brightnessHUD) }
    }

    /// Remplace les jauges de macOS au lieu de s'y ajouter.
    ///
    /// Actif, RSnotch intercepte les touches son et luminosite avant le
    /// systeme : le HUD natif ne s'affiche plus. Exige l'autorisation
    /// Accessibilite. Inactif — ou autorisation refusee — les deux jauges
    /// cohabitent, ce qui reste un comportement valable.
    var replaceSystemHUD: Bool {
        didSet { defaults.set(replaceSystemHUD, forKey: Key.replaceSystemHUD) }
    }

    // MARK: Apps & dossiers

    /// Nom sous chaque tuile de la grappe. Desactive par defaut : la grappe
    /// vise une rangee compacte, et l'icone seule suffit une fois les apps
    /// reconnues — un survol donne deja le nom (`.help`). Certains preferent
    /// le voir en permanence, notamment avec beaucoup d'icones similaires.
    var showLauncherLabels: Bool {
        didSet { defaults.set(showLauncherLabels, forKey: Key.showLauncherLabels) }
    }

    // MARK: Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: Key.glassIntensity)
        // Defaut « dense » : au repos le panneau doit se confondre avec
        // l'encoche noire, pas se signaler.
        self.glassIntensity = stored.flatMap(GlassIntensity.init(rawValue:)) ?? .dense
        self.spaceTintEnabled = defaults.object(forKey: Key.spaceTint) as? Bool ?? true
        self.quoteText = defaults.string(forKey: Key.quoteText) ?? Self.defaultQuote
        let storedLimit = defaults.integer(forKey: Key.clipboardLimit)
        self.clipboardLimit = storedLimit > 0 ? storedLimit : 200
        self.panelWidth = defaults.string(forKey: Key.panelWidth)
            .flatMap(PanelWidth.init(rawValue:)) ?? .standard
        self.emptyPocketOnLaunch = defaults.object(forKey: Key.emptyPocketOnLaunch) as? Bool ?? true
        self.panelEnabled = defaults.object(forKey: Key.panelEnabled) as? Bool ?? true
        self.openOnHover = defaults.object(forKey: Key.openOnHover) as? Bool ?? true
        let storedDelay = defaults.integer(forKey: Key.hoverDelay)
        self.hoverDelayMilliseconds = storedDelay > 0 ? storedDelay : 180
        self.screenPreference = defaults.string(forKey: Key.screenPreference)
            .flatMap(ScreenPreference.init(rawValue:)) ?? .withNotch
        self.showWithoutNotch = defaults.object(forKey: Key.showWithoutNotch) as? Bool ?? true
        let storedBar = defaults.double(forKey: Key.simulatedBarWidth)
        self.simulatedBarWidth = storedBar > 0 ? storedBar : 190
        self.expandOnLaunch = defaults.object(forKey: Key.expandOnLaunch) as? Bool ?? false
        self.volumeHUDEnabled = defaults.object(forKey: Key.volumeHUD) as? Bool ?? true
        self.brightnessHUDEnabled = defaults.object(forKey: Key.brightnessHUD) as? Bool ?? true
        self.replaceSystemHUD = defaults.object(forKey: Key.replaceSystemHUD) as? Bool ?? true
        self.showLauncherLabels = defaults.object(forKey: Key.showLauncherLabels) as? Bool ?? false
    }

    static let clipboardLimitChoices = [50, 100, 200, 500]
    static let hoverDelayChoices = [0, 120, 180, 300, 500]
}

// MARK: - ScreenPreference
/// Choix de l'ecran hote quand plusieurs sont branches.
enum ScreenPreference: String, CaseIterable, Identifiable, Sendable {
    /// Ecran a encoche s'il y en a un, sinon l'ecran principal.
    case withNotch
    /// Toujours l'ecran principal, meme si un autre porte l'encoche — le cas
    /// du MacBook capot ouvert utilise comme ecran secondaire.
    case primary

    var id: String { rawValue }

    var label: String {
        switch self {
        case .withNotch: "Écran à encoche"
        case .primary: "Écran principal"
        }
    }
}
