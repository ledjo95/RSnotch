import SwiftUI

// MARK: - RSnotchApp
//
// Le cycle de vie SwiftUI ne sert qu'a heberger la scene Reglages ; toute la
// fenetre du notch est pilotee par l'AppDelegate, qui a besoin du controle
// AppKit fin (niveau de fenetre, non-activation, hit-testing).

@main
struct RSnotchApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // La scene est volontairement vide : les reglages vivent dans une NSWindow
    // (cf. SettingsWindowController). Une scene `Settings` peuplee ne s'ouvrirait
    // que par `SettingsLink`, inaccessible depuis un NSMenu de barre des menus.
    // SwiftUI exige neanmoins au moins une scene pour compiler l'App.
    var body: some Scene {
        Settings { EmptyView() }
    }
}
