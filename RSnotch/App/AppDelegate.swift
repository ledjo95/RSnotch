import AppKit
import SwiftUI

// MARK: - AppDelegate
//
// RSnotch est une app accessoire (LSUIElement) : pas d'icone Dock, pas de
// fenetre principale. Le delegate n'a donc que deux responsabilites — faire
// vivre le panneau du notch, et offrir un point d'entree dans la barre des menus.

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let notchController = NotchWindowController()
    private let settingsWindow = SettingsWindowController.shared
    private let permissionPrimer = PermissionPrimerController()
    private var statusItem: NSStatusItem?
    #if DEBUG
    private var galleryWindow: NSWindow?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // AVANT TOUT LE RESTE. Le retrait du bac a sable a rendu l'ancien
        // conteneur invisible : preferences, applications epinglees, historique
        // et Pocket etaient toujours sur le disque, mais l'app repartait d'une
        // ardoise vierge. La reprise doit se faire avant que quiconque lise une
        // donnee — en particulier avant que SwiftData ne cree une base vide,
        // qui prendrait la place de celle qu'on veut restaurer.
        AppContainer.migrateFromSandboxContainer()
        notchController.start()
        installStatusItem()
        installDebugHooks()

        // APRES `notchController.start()` : celui-ci arme l'interception, ce qui
        // met a jour l'etat d'autorisation de l'instance partagee. L'invite peut
        // alors decider en connaissance de cause si elle a lieu d'etre.
        permissionPrimer.presentIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        notchController.stop()
    }

    // MARK: Barre des menus

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "rectangle.topthird.inset.filled",
            accessibilityDescription: "RSnotch"
        )
        item.button?.image?.isTemplate = true

        let menu = NSMenu()
        menu.addItem(
            withTitle: "Ouvrir le panneau",
            action: #selector(openPanel),
            keyEquivalent: ""
        ).target = self
        menu.addItem(
            withTitle: "Tester une notification",
            action: #selector(testIsland),
            keyEquivalent: ""
        ).target = self
        #if DEBUG
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Planche du design system",
            action: #selector(openGallery),
            keyEquivalent: ""
        ).target = self
        #endif
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Réglages…",
            action: #selector(openSettings),
            keyEquivalent: ","
        ).target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quitter RSnotch",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        item.menu = menu
        statusItem = item
    }

    // MARK: Actions

    @objc private func openPanel() {
        notchController.model?.expand()
    }

    /// Verifie a l'oeil le chemin « island » avant que les vrais evenements
    /// systeme (batterie, Bluetooth, lecture) n'arrivent en Phase 8.
    @objc private func testIsland() {
        notchController.model?.present(
            CompactIslandPayload(
                symbolName: "bolt.fill",
                title: "RSnotch prêt",
                detail: "Phase 0"
            )
        )
    }

    // MARK: Pilotage de developpement
    //
    // Pendant le developpement, le panneau doit pouvoir etre ouvert sans passer
    // par le survol : la zone du notch est etroite et souvent disputee par
    // d'autres utilitaires. Compile uniquement en Debug — rien de ce code ne
    // part en production, donc rien a justifier en App Review.

    private func installDebugHooks() {
        #if DEBUG
        // Ouverture immediate au lancement : RSNOTCH_DEBUG_STATE=expanded|island
        switch ProcessInfo.processInfo.environment["RSNOTCH_DEBUG_STATE"] {
        case "expanded": notchController.model?.expand()
        case "island": testIsland()
        case "gallery": openGallery()
        default: break
        }

        // Teinte de bureau : RSNOTCH_DEBUG_SPACE=2
        if let raw = ProcessInfo.processInfo.environment["RSNOTCH_DEBUG_SPACE"],
           let index = Int(raw) {
            notchController.forceDebugSpace(index)
        }

        // Annonce compacte reelle :
        // RSNOTCH_DEBUG_ISLAND=battery|plugged|bluetooth|timer|volume|muted|brightness
        if let kind = ProcessInfo.processInfo.environment["RSNOTCH_DEBUG_ISLAND"] {
            notchController.fireDebugIsland(kind)
        }

        if let raw = ProcessInfo.processInfo.environment["RSNOTCH_DEBUG_WIDTH"],
           let width = PanelWidth(rawValue: raw) {
            AppSettings.shared.panelWidth = width
        }

        if let raw = ProcessInfo.processInfo.environment["RSNOTCH_DEBUG_TIMER"],
           let seconds = Int(raw) {
            notchController.startDebugTimer(seconds: seconds)
        }

        // Coupe puis rallume l'encoche active, pour eprouver le chemin
        // « reglage modifie a chaud » sans piloter la fenetre de reglages :
        // RSNOTCH_DEBUG_PANEL_OFF=3 (secondes avant coupure).
        if let raw = ProcessInfo.processInfo.environment["RSNOTCH_DEBUG_PANEL_OFF"],
           let delay = Int(raw) {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                NSLog("[debug] encoche coupée")
                AppSettings.shared.panelEnabled = false
                try? await Task.sleep(for: .seconds(delay))
                NSLog("[debug] encoche rallumée")
                AppSettings.shared.panelEnabled = true
            }
        }

        // Ouvre la fenetre de reglages au lancement : RSNOTCH_DEBUG_SETTINGS=1
        if ProcessInfo.processInfo.environment["RSNOTCH_DEBUG_SETTINGS"] == "1" {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                self.openSettings()
            }
        }

        // Force l'invite de priming, autorisation deja accordee ou non :
        // RSNOTCH_DEBUG_PRIMER=1
        if ProcessInfo.processInfo.environment["RSNOTCH_DEBUG_PRIMER"] == "1" {
            permissionPrimer.presentForDebug()
        }

        if let raw = ProcessInfo.processInfo.environment["RSNOTCH_DEBUG_TAB"],
           let tab = NotchTab(rawValue: raw) {
            notchController.model?.selectedTab = tab
        }

        // Pre-remplit la grappe d'applications pour pouvoir la tester sans
        // passer par un NSOpenPanel. Ne fonctionne qu'en build de developpement
        // non sandboxee : en sandbox, seuls les fichiers designes par
        // l'utilisateur sont accessibles, et c'est bien le comportement voulu.
        // Etat de lecture factice : RSNOTCH_DEBUG_MEDIA=playing|paused|loved|denied|none
        if let variant = ProcessInfo.processInfo.environment["RSNOTCH_DEBUG_MEDIA"] {
            notchController.seedDebugMedia(variant)
        }

        // Depot d'un dossier : RSNOTCH_DEBUG_SEED_FOLDER=/chemin/du/dossier
        if let path = ProcessInfo.processInfo.environment["RSNOTCH_DEBUG_SEED_FOLDER"] {
            notchController.seedDebugFolder(path)
        }

        if ProcessInfo.processInfo.environment["RSNOTCH_DEBUG_SEED_POCKET"] == "1" {
            #if DEBUG
            notchController.seedDebugPocket()
            #endif
        }

        if ProcessInfo.processInfo.environment["RSNOTCH_DEBUG_SEED_APPS"] == "1" {
            #if DEBUG
            notchController.seedDebugApps()
            #endif
        }

        let center = DistributedNotificationCenter.default()
        center.addObserver(
            forName: Notification.Name("com.varicube.RSnotch.debug.expand"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.notchController.model?.expand() }
        }
        center.addObserver(
            forName: Notification.Name("com.varicube.RSnotch.debug.collapse"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.notchController.model?.collapse() }
        }
        center.addObserver(
            forName: Notification.Name("com.varicube.RSnotch.debug.island"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.testIsland() }
        }
        #endif
    }

    #if DEBUG
    @objc private func openGallery() {
        NSApp.activate(ignoringOtherApps: true)
        if let galleryWindow {
            galleryWindow.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 660),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "RSnotch — Design system"
        window.contentView = NSHostingView(rootView: DesignSystemGallery())
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        galleryWindow = window
    }
    #endif

    @objc private func openSettings() {
        settingsWindow.show()
    }
}
