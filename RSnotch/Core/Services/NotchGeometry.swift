import AppKit

// MARK: - NotchGeometry
//
// Decrit l'encoche d'un ecran a partir d'APIs publiques uniquement :
//   - NSScreen.safeAreaInsets.top       -> hauteur de la zone occultee
//   - NSScreen.auxiliaryTopLeftArea     -> zone de menu utilisable a gauche
//   - NSScreen.auxiliaryTopRightArea    -> zone de menu utilisable a droite
// La largeur du notch se deduit de ce que ces deux zones NE couvrent PAS.
// Aucun appel a CoreGraphics prive (CGSCopyManagedDisplaySpaces & co).

struct NotchGeometry: Equatable, Sendable {

    /// `true` si l'ecran possede une encoche physique.
    let hasPhysicalNotch: Bool
    /// Taille de l'encoche (ou de la barre simulee sur ecran sans encoche).
    let notchSize: CGSize
    /// Rect de l'encoche en coordonnees ecran (origine bas-gauche, comme AppKit).
    let notchRect: CGRect
    /// Rect complet de l'ecran.
    let screenFrame: CGRect

    // MARK: Fabrique

    /// Repli utilise sur un ecran sans encoche : barre centree de meme gabarit,
    /// pour que le comportement du panneau reste identique partout. La largeur
    /// est reglable (§3.9) : sans encoche physique, rien n'impose de gabarit.
    static let simulatedNotchHeight: CGFloat = 32
    static let simulatedWidthRange: ClosedRange<Double> = 140...360

    @MainActor
    static func measure(_ screen: NSScreen, simulatedBarWidth: Double? = nil) -> NotchGeometry {
        let frame = screen.frame
        let topInset = screen.safeAreaInsets.top

        // Un ecran a encoche expose deux zones auxiliaires de part et d'autre.
        if topInset > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = max(0, frame.width - left.width - right.width)
            let size = CGSize(width: width, height: topInset)
            let rect = CGRect(
                x: frame.minX + left.width,
                y: frame.maxY - topInset,
                width: width,
                height: topInset
            )
            return NotchGeometry(
                hasPhysicalNotch: width > 0,
                notchSize: size,
                notchRect: rect,
                screenFrame: frame
            )
        }

        // Ecran externe / MacBook sans encoche : on simule.
        let width = (simulatedBarWidth ?? AppSettings.shared.simulatedBarWidth)
            .clamped(to: simulatedWidthRange)
        let size = CGSize(width: width, height: simulatedNotchHeight)
        let rect = CGRect(
            x: frame.midX - size.width / 2,
            y: frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        return NotchGeometry(
            hasPhysicalNotch: false,
            notchSize: size,
            notchRect: rect,
            screenFrame: frame
        )
    }

    // MARK: Selection d'ecran

    /// Ecran cible du panneau.
    ///
    /// Par defaut : celui qui porte une encoche, sinon l'ecran principal. Le
    /// reglage `.primary` force l'ecran principal — cas du MacBook capot ouvert
    /// a cote d'un moniteur, ou l'encoche n'est pas la ou on travaille.
    ///
    /// `showWithoutNotch` desactive coupe le panneau des qu'aucun ecran a
    /// encoche n'est disponible : la barre simulee ne convient pas a tout le
    /// monde, et mieux vaut rien afficher que reserver une zone non demandee.
    @MainActor
    static func preferredScreen(
        preference: ScreenPreference = AppSettings.shared.screenPreference,
        allowSimulated: Bool = AppSettings.shared.showWithoutNotch
    ) -> NSScreen? {
        let notched = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
        switch preference {
        case .withNotch:
            if let notched { return notched }
        case .primary:
            if let main = NSScreen.main, main.safeAreaInsets.top > 0 { return main }
        }
        // Aucun ecran a encoche ne convient : reste la barre simulee sur
        // l'ecran principal, si elle est autorisee.
        guard allowSimulated else { return nil }
        return NSScreen.main
    }

    // MARK: Derives

    /// Marge horizontale entre le bord de l'ecran et l'encoche.
    var horizontalInset: CGFloat { notchRect.minX - screenFrame.minX }

    /// Rect que doit couvrir la fenetre hote : toute la largeur de l'ecran, sur
    /// une bande assez haute pour accueillir le panneau etendu. La fenetre ne
    /// change jamais de taille — c'est le contenu SwiftUI qui grandit, ce qui
    /// permet un vrai morph Liquid Glass au lieu d'une animation de frame.
    func hostFrame(maxPanelHeight: CGFloat) -> CGRect {
        CGRect(
            x: screenFrame.minX,
            y: screenFrame.maxY - maxPanelHeight,
            width: screenFrame.width,
            height: maxPanelHeight
        )
    }
}


// MARK: - Utilitaire
private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
