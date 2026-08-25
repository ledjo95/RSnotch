import SwiftUI

// MARK: - TickRuler
//
// Regle graduee horizontale : le curseur reste fixe au centre, c'est la regle
// qui defile sous lui. Regler une duree revient alors au meme geste que faire
// tourner une molette, et la valeur choisie est toujours au meme endroit de
// l'ecran — on n'a pas a chercher ou on en est.
//
// Le trace passe par un Canvas : cent vingt graduations en vues SwiftUI
// couteraient cher a chaque image d'animation, alors qu'il s'agit de traits.

struct TickRuler: View {

    @Binding var minutes: Int
    let range: ClosedRange<Int>
    /// Desactivee pendant un decompte : changer la cible en cours de route
    /// rendrait le temps affiche incoherent.
    var isEnabled: Bool = true

    /// Espacement d'une minute. 10 pt donne un geste precis sans exiger une
    /// course de souris demesuree pour traverser deux heures.
    private let pointsPerMinute: CGFloat = 10
    /// Une graduation haute et un libelle tous les cinq minutes.
    private let majorEvery = 5

    @State private var dragAnchor: Int?

    var body: some View {
        Canvas { context, size in
            draw(in: context, size: size)
        }
        .frame(height: 46)
        .contentShape(Rectangle())
        .overlay(alignment: .center) { cursor }
        .gesture(dragGesture)
        .opacity(isEnabled ? 1 : 0.4)
        .allowsHitTesting(isEnabled)
        .accessibilityElement()
        .accessibilityLabel("Durée du minuteur")
        .accessibilityValue("\(minutes) minutes")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(minutes + 1)
            case .decrement: set(minutes - 1)
            @unknown default: break
            }
        }
    }

    // MARK: Trace

    private func draw(in context: GraphicsContext, size: CGSize) {
        let centerX = size.width / 2
        let visible = Int(size.width / pointsPerMinute / 2) + 2

        drawEndStop(in: context, size: size, centerX: centerX, at: range.lowerBound)
        drawEndStop(in: context, size: size, centerX: centerX, at: range.upperBound)

        for value in (minutes - visible)...(minutes + visible) {
            guard range.contains(value) else { continue }

            let x = centerX + CGFloat(value - minutes) * pointsPerMinute
            let isMajor = value % majorEvery == 0
            let height: CGFloat = isMajor ? 14 : 7
            let top = size.height - height - 4

            var line = Path()
            line.move(to: CGPoint(x: x, y: top))
            line.addLine(to: CGPoint(x: x, y: top + height))
            context.stroke(
                line,
                with: .color(isMajor ? Theme.Palette.ember : Theme.Palette.ember.opacity(0.45)),
                lineWidth: 1
            )

            guard isMajor else { continue }
            let isCurrent = value == minutes
            var label = context.resolve(
                Text("\(value)")
                    .font(Theme.Typography.data(9, weight: isCurrent ? .bold : .regular))
                    .foregroundStyle(isCurrent ? .white : Theme.Palette.ember.opacity(0.8))
            )
            label.shading = .color(isCurrent ? .white : Theme.Palette.ember.opacity(0.8))
            context.draw(label, at: CGPoint(x: x, y: 8), anchor: .center)
        }
    }

    /// Butee de fin de course. Sans elle, le vide au-dela de la derniere
    /// graduation se lit comme un defaut d'affichage plutot que comme le bout
    /// de la regle.
    private func drawEndStop(
        in context: GraphicsContext,
        size: CGSize,
        centerX: CGFloat,
        at value: Int
    ) {
        let x = centerX + CGFloat(value - minutes) * pointsPerMinute
        guard x >= -2, x <= size.width + 2 else { return }

        var stop = Path()
        stop.move(to: CGPoint(x: x, y: size.height - 26))
        stop.addLine(to: CGPoint(x: x, y: size.height - 4))
        context.stroke(stop, with: .color(Theme.Palette.ember), lineWidth: 2.5)
    }

    /// Curseur : un simple triangle. Il marque la position de lecture, il n'a
    /// pas a etre un objet en soi.
    private var cursor: some View {
        Triangle()
            .fill(Theme.Palette.ember)
            .frame(width: 9, height: 7)
            .offset(y: 6)
            .allowsHitTesting(false)
    }

    // MARK: Geste

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let anchor = dragAnchor ?? minutes
                if dragAnchor == nil { dragAnchor = anchor }
                // Glisser vers la gauche fait defiler la regle vers la gauche,
                // donc augmente la valeur : le meme sens qu'une molette.
                set(anchor - Int((value.translation.width / pointsPerMinute).rounded()))
            }
            .onEnded { _ in dragAnchor = nil }
    }

    private func set(_ value: Int) {
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        guard clamped != minutes else { return }
        minutes = clamped
    }
}

// MARK: - Triangle
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
