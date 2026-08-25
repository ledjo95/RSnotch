import SwiftUI

// MARK: - NotchShape
//
// Forme du panneau : bord superieur plaque contre le haut de l'ecran, coins
// inferieurs convexes, coins superieurs concaves qui raccordent la forme au
// bord de l'ecran. C'est ce raccord concave qui donne l'impression que le
// panneau est creuse dans la dalle plutot que pose dessus.
//
// Concentricite (recommandation Liquid Glass) : le rayon inferieur d'un
// conteneur doit valoir le rayon de son contenu + la marge qui l'entoure.
// Voir `NotchShape.concentric(inner:padding:)`.

struct NotchShape: InsettableShape {

    /// Rayon des deux coins inferieurs (convexes).
    var bottomRadius: CGFloat
    /// Rayon des deux raccords superieurs (concaves).
    var topRadius: CGFloat

    // Rend la forme animable : pendant le morph pilule → panneau, les rayons
    // interpolent au lieu de sauter d'une valeur a l'autre.
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bottomRadius, topRadius) }
        set {
            bottomRadius = newValue.first
            topRadius = newValue.second
        }
    }

    /// Retrait applique par `strokeBorder` pour que le trait reste a l'interieur.
    private var insetAmount: CGFloat = 0

    init(bottomRadius: CGFloat, topRadius: CGFloat? = nil) {
        self.bottomRadius = bottomRadius
        // Par defaut le raccord haut vaut la moitie du rayon bas : assez marque
        // pour se lire, assez discret pour ne pas manger la largeur utile.
        self.topRadius = topRadius ?? bottomRadius / 2
    }

    func inset(by amount: CGFloat) -> NotchShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    func path(in bounds: CGRect) -> Path {
        let rect = bounds.insetBy(dx: insetAmount, dy: insetAmount)
        let w = rect.width
        let h = rect.height
        // Bride les rayons pour que la forme reste valide sur une pilule etroite.
        let top = min(topRadius, w / 4, h)
        let bottom = min(bottomRadius, (w - 2 * top) / 2, h - top)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Raccord concave haut-gauche.
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top, y: rect.minY + top),
            control: CGPoint(x: rect.minX + top, y: rect.minY)
        )
        // Flanc gauche.
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        // Coin convexe bas-gauche.
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
            control: CGPoint(x: rect.minX + top, y: rect.maxY)
        )
        // Base.
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        // Coin convexe bas-droit.
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
            control: CGPoint(x: rect.maxX - top, y: rect.maxY)
        )
        // Flanc droit.
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        // Raccord concave haut-droit.
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - top, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }

    /// Rayon concentrique d'un conteneur qui entoure un contenu arrondi.
    static func concentric(inner: CGFloat, padding: CGFloat) -> CGFloat {
        inner + padding
    }
}
