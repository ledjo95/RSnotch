import AppKit
import SwiftUI

// MARK: - SettingsWindowController
//
// Fenetre de reglages, pilotee en AppKit.
//
// La scene SwiftUI `Settings` n'est pas utilisable ici : depuis macOS 14, elle
// ne s'ouvre plus que par `SettingsLink`, une vue SwiftUI. RSnotch est une app
// accessoire dont le seul point d'entree est un NSMenu de la barre des menus —
// il n'existe aucune vue SwiftUI d'ou emettre ce lien. On heberge donc la meme
// `SettingsView` dans une NSWindow que l'on ouvre soi-meme.
//
// Effet de bord bienvenu : l'app etant `.accessory`, il faut de toute facon
// activer explicitement le processus pour que la fenetre passe au premier plan
// et recoive le clavier.

@MainActor
final class SettingsWindowController {

    private var window: NSWindow?

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Réglages RSnotch"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
