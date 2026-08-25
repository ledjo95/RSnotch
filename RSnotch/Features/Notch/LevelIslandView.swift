import SwiftUI

// MARK: - LevelIslandView
//
// Jauge de volume / luminosite affichee dans l'encoche elargie.
//
// Le HUD natif de macOS est une dalle posee au milieu de l'ecran, par-dessus le
// travail. Celui-ci reprend le langage du panneau : une lentille de Liquid
// Glass teintee a l'ambre du filament, qui coulisse dans un canal creuse.
//
// LA SIGNATURE : la lentille et la pastille de l'icone vivent dans le MEME
// `GlassEffectContainer` et portent chacune un `glassEffectID`. A bas niveau,
// elles sont assez proches pour FUSIONNER — la lentille se retracte dans la
// pastille et les deux ne font qu'une goutte ; en montant, elle s'en detache et
// s'etire. C'est le morph de materiau que Liquid Glass sait faire et qu'aucun
// degrade ne sait imiter, et c'est la raison pour laquelle libelle et jauge ne
// sont PAS repartis de part et d'autre de l'encoche comme dans la premiere
// version : separees par la reserve centrale, les deux formes ne pouvaient
// jamais se rejoindre.

struct LevelIslandView: View {

    let payload: CompactIslandPayload
    let level: CompactIslandPayload.Level
    /// Largeur de l'encoche physique a neutraliser au centre.
    let notchWidth: CGFloat

    @Namespace private var glassNamespace

    private var tint: Color {
        level.isMuted ? Theme.Palette.mist : Theme.Palette.ember
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(payload.title)
                .engraved(10, color: Theme.Palette.frost)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, IslandMetrics.horizontalPadding)

            // Reserve du notch physique : rien ne passe derriere la dalle.
            Color.clear.frame(width: notchWidth)

            gauge
                // Les marges viennent de `IslandMetrics`, qui sert aussi a
                // MESURER la largeur de l'island. Codees en dur ici, elles
                // avaient deja diverge de 2 pt et rognaient le pourcentage.
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, IslandMetrics.horizontalPadding)
                .padding(.leading, IslandMetrics.gap)
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: level)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(payload.title)
        .accessibilityValue(level.isMuted ? "coupé" : "\(Int(level.value * 100)) %")
    }

    // MARK: Jauge

    private var gauge: some View {
        GlassEffectContainer(spacing: 16) {
            HStack(spacing: LevelIslandMetrics.innerGap) {
                badge
                GlassLens(
                    value: level.isMuted ? 0 : level.value,
                    tint: tint,
                    namespace: glassNamespace
                )

                if level.showsValue {
                    Text("\(Int((level.value * 100).rounded()))")
                        .font(Theme.Typography.data(11, weight: .medium))
                        .foregroundStyle(level.isMuted ? Theme.Palette.mist : Theme.Palette.frost)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .frame(width: LevelIslandMetrics.valueTextWidth, alignment: .trailing)
                }
            }
        }
    }

    private var badge: some View {
        Image(systemName: payload.symbolName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            // Le symbole change a chaque palier (une, deux, trois ondes) :
            // sans transition, l'icone sautille pendant la rampe.
            .contentTransition(.symbolEffect(.replace))
            .frame(width: LevelIslandMetrics.badgeSide, height: LevelIslandMetrics.badgeSide)
            .background(Circle().fill(Theme.Palette.ink.opacity(0.45)))
            .background(Circle().fill(Theme.Palette.wellFill))
            .glassEffect(Glass.clear.interactive(), in: .circle)
            .glassEffectID("hud.badge", in: glassNamespace)
    }
}

// MARK: - GlassLens
//
// Canal creuse + lentille de verre teintee.
//
// La couleur est posee EN CONTENU, sous le materiau, et non confiee a
// `Glass.tint(_:)` seul : au-dessus d'une fenetre transparente, le verre n'a
// presque rien a refracter et la teinte seule rendait une pastille grise,
// illisible — mesure faite. Le verre garde son role — profondeur, arete
// lumineuse, reponse au mouvement — au-dessus d'une teinte, elle, franche.

private struct GlassLens: View {

    let value: Double
    let tint: Color
    let namespace: Namespace.ID

    private var height: CGFloat { LevelIslandMetrics.gaugeHeight }

    /// La lentille ne descend jamais sous sa propre hauteur : reduite a un
    /// trait, elle cesserait de se lire comme du verre — or c'est justement le
    /// materiau qui doit rester reconnaissable a zero.
    private var lensWidth: CGFloat {
        let track = LevelIslandMetrics.gaugeWidth
        return max(height, min(track, track * value))
    }

    var body: some View {
        ZStack(alignment: .leading) {
            channel

            ZStack(alignment: .leading) {
                // 1. La lueur. Elle croit avec la valeur : a fond, la lentille
                // deborde franchement de son canal. C'est ce halo, et non la
                // longueur seule, qui fait sentir le niveau du coin de l'oeil.
                Capsule(style: .continuous)
                    .fill(tint)
                    .frame(width: lensWidth, height: height)
                    .blur(radius: 6)
                    .opacity(0.30 + 0.35 * value)

                // 2. Le corps teinte.
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.98), tint.opacity(0.72)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: lensWidth, height: height)
                    // 3. Le reflet speculaire : une arete claire sur la moitie
                    // haute seulement. C'est ce qui donne l'epaisseur — sans
                    // lui, la lentille reste un aplat colore arrondi.
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Theme.Palette.rim, lineWidth: 1)
                            .frame(width: lensWidth, height: height)
                    }
                    .overlay(alignment: .top) {
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.55), .white.opacity(0.0)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: max(0, lensWidth - 7), height: height * 0.42)
                            .padding(.top, 1.5)
                            .blendMode(.plusLighter)
                    }
                    // `.interactive()` donne au materiau sa reponse au
                    // mouvement : la lentille se deforme legerement pendant la
                    // rampe au lieu de glisser comme un rectangle plat.
                    .glassEffect(Glass.clear.interactive(), in: .capsule)
                    .glassEffectID("hud.lens", in: namespace)
            }
        }
        .frame(width: LevelIslandMetrics.gaugeWidth, height: height)
    }

    /// Canal creuse. Meme vocabulaire que les cartes du panneau — creux plus
    /// arete interieure — pour que la jauge appartienne visiblement au meme
    /// objet que le reste du notch.
    private var channel: some View {
        Capsule(style: .continuous)
            .fill(Theme.Palette.ink.opacity(0.55))
            .overlay(Capsule(style: .continuous).fill(Theme.Palette.wellFill))
            .overlay {
                // Graduations : elles donnent l'echelle et rappellent la regle
                // du minuteur. Sous la lentille, le verre les refracte.
                HStack(spacing: 0) {
                    ForEach(1..<LevelIslandMetrics.tickCount, id: \.self) { _ in
                        Rectangle()
                            .fill(Theme.Palette.filament)
                            .frame(width: 1, height: 4)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, height / 2)
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Theme.Palette.innerRim, lineWidth: 1)
            }
    }
}

// MARK: - LevelIslandMetrics
enum LevelIslandMetrics {
    /// Espacement entre pastille, jauge et valeur. Une seule source, partagee
    /// avec le calcul de largeur ci-dessous.
    static let innerGap: CGFloat = 9
    static let gaugeWidth: CGFloat = 138
    static let gaugeHeight: CGFloat = 16
    static let badgeSide: CGFloat = 24
    static let valueTextWidth: CGFloat = 24
    /// Graduations du canal, espaces reguliers.
    static let tickCount = 8

    /// Pastille + jauge + valeur, espacements compris. Sert a la mesure de
    /// largeur de l'island (voir IslandMetrics).
    static func trailingWidth(showsValue: Bool) -> CGFloat {
        badgeSide + innerGap + gaugeWidth + (showsValue ? innerGap + valueTextWidth : 0)
    }
}
