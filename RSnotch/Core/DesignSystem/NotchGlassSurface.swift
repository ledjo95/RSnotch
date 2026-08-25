import SwiftUI

// MARK: - NotchGlassSurface
//
// Coquille de verre du panneau. Regroupe les trois couches, dans cet ordre :
//
//   1. le fond optionnel (image utilisateur), SOUS le verre — le materiau doit
//      pouvoir s'adapter a ce qu'il recouvre ;
//   2. le materiau Liquid Glass, dont la variante vient du reglage d'intensite
//      et la teinte de l'accent du Space ;
//   3. le filament signature.
//
// Aucune vue de fonctionnalite ne redeclare ces couches : elles passent toutes
// par ce composant, ce qui garantit qu'un changement de reglage se propage
// partout d'un coup.

struct NotchGlassSurface<Content: View>: View {

    let shape: NotchShape
    /// 0 au repos, 1 panneau grand ouvert. Pilote l'eclat du filament.
    let filamentIntensity: Double
    let glassNamespace: Namespace.ID
    @ViewBuilder var content: Content

    @Environment(\.glassIntensity) private var intensity
    @Environment(\.spaceAccent) private var accent
    @Environment(\.panelSurface) private var surface

    var body: some View {
        content
            // Le verre est pose en ARRIERE-PLAN, pas autour du contenu.
            // `GlassEffectContainer` fusionne les formes de verre qu'il
            // contient : englober le contenu ferait fondre les boutons
            // d'onglet dans la coquille et leur ferait perdre leur etat
            // selectionne. Le conteneur ne recoit donc que les formes qui
            // doivent morpher entre elles.
            .background {
                GlassEffectContainer(spacing: Theme.Metrics.glassFusionSpacing) {
                    Color.clear
                        .background { backdrop }
                        .glassEffect(intensity.shellGlass(tintedBy: accent), in: shape)
                        .glassEffectID("shell", in: glassNamespace)
                }
            }
            .filament(
                shape,
                intensity: filamentIntensity,
                tint: accent ?? Theme.Palette.ember
            )
    }

    /// Couche posee sous le verre. En mode image, un voile sombre garantit que
    /// le texte reste lisible quelle que soit la photo choisie — c'est la seule
    /// entorse assumee a « laisser le verre gerer la lisibilite », parce qu'une
    /// image utilisateur peut etre uniformement blanche.
    @ViewBuilder
    private var backdrop: some View {
        switch surface {
        case .glass:
            EmptyView()
        case .blackGlass:
            shape.fill(Theme.Palette.ink.opacity(0.35))
        case .image(let url):
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .overlay(Theme.Palette.ink.opacity(0.35))
            } placeholder: {
                Theme.Palette.ink.opacity(0.35)
            }
            .clipShape(shape)
        }
    }
}
