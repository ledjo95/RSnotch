import AppKit
import Foundation

// MARK: - AppLauncher
//
// Ouverture d'une application systeme depuis un widget.
//
// Sandbox : `NSWorkspace.openApplication` n'exige AUCUN entitlement — lancer
// une autre app n'est pas un acces a ses donnees. Aucune permission n'est donc
// ajoutee pour rendre les widgets cliquables.
//
// Les identifiants sont resolus par LaunchServices, jamais par un chemin en
// dur : `Calendrier.app` ne vit pas au meme endroit selon la version de macOS,
// et l'utilisateur peut avoir remplace l'app par defaut.

@MainActor
enum AppLauncher {

    /// Applications systeme visees par les widgets.
    enum Target {
        case calendar
        case weather
        case music

        var bundleIdentifier: String {
            switch self {
            case .calendar: "com.apple.iCal"
            case .weather: "com.apple.weather"
            case .music: "com.apple.Music"
            }
        }
    }

    static func isInstalled(_ target: Target) -> Bool {
        url(for: target) != nil
    }

    /// Rend `false` quand l'application n'existe pas sur la machine — le widget
    /// doit alors se taire plutot que de faire semblant de repondre.
    @discardableResult
    static func open(_ target: Target) -> Bool {
        guard let url = url(for: target) else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        return true
    }

    private static func url(for target: Target) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundleIdentifier)
    }
}
