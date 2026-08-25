import AppKit
import SwiftUI

// MARK: - NotchPanel
//
// Fenetre hote du panneau. Choix structurants :
//
//  - `.nonactivatingPanel` + `canBecomeKey = false` : cliquer dans le notch ne
//    vole jamais le focus a l'app de premier plan. C'est la condition pour que
//    RSnotch reste un accessoire et non une interruption.
//  - `.borderless`, fond transparent, pas d'ombre : toute la matiere vient du
//    materiau Liquid Glass rendu par SwiftUI, pas du chrome de la fenetre.
//  - niveau `.statusBar` : au-dessus de la barre des menus, donc capable de
//    recouvrir l'encoche physique.
//  - `canJoinAllSpaces` + `fullScreenAuxiliary` : le panneau suit l'utilisateur
//    d'un Space a l'autre et reste disponible au-dessus d'une app plein ecran.
//
// La fenetre garde une taille FIXE (toute la bande superieure de l'ecran).
// L'expansion est purement visuelle, cote SwiftUI.

final class NotchPanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        animationBehavior = .none

        // `sharingType` reste au defaut (.readOnly) : le panneau doit apparaitre
        // dans les captures d'ecran de l'utilisateur. Le masquer en partage
        // d'ecran sera un reglage opt-in (Phase 10), pas un comportement impose.
    }

    // Non activable : aucune saisie clavier n'est prevue en Phase 0.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { false }
}

// MARK: - NotchHostingView
//
// NSHostingView dont le hit-testing est restreint a la forme reellement
// visible. Sans cela, la fenetre — qui couvre toute la largeur de l'ecran —
// avalerait les clics destines a la barre des menus et au bureau.

final class NotchHostingView<Content: View>: NSHostingView<Content> {

    /// Renseigne par le controller. Retourne `true` si le point (coordonnees
    /// fenetre) tombe sur la forme de verre visible.
    var isPointInteractive: ((NSPoint) -> Bool)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isPointInteractive?(point) ?? false else { return nil }
        return super.hitTest(point)
    }
}
