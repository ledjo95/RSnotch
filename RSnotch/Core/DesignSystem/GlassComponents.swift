import SwiftUI

// MARK: - Regle de couleur du design system
//
// Un seul accent, employe avec parcimonie, sinon il ne veut plus rien dire :
//
//   ambre  (Palette.ember)  action primaire et decompte en cours.
//                           « Start timer », minuteur actif, filament du panneau.
//   neutre (verre prominent) selection. Onglets, pilules de filtre.
//   rouge  (Palette.signal)  marqueur temporel. Jour de la semaine, alerte breve.
//
// Une vue qui a besoin d'une quatrieme signification a probablement un probleme
// de hierarchie, pas un probleme de couleur.

// MARK: - Filament
//
// Signature visuelle de RSnotch : un liseré lumineux d'un pixel qui suit le
// contour du panneau, dense sous la base et eteint sur les flancs. Il s'allume
// pendant le morph et retombe au repos — seul effet decoratif de l'app.

struct FilamentOverlay<S: InsettableShape>: ViewModifier {
    let shape: S
    /// 0 au repos, 1 panneau grand ouvert.
    let intensity: Double
    let tint: Color

    func body(content: Content) -> some View {
        content.overlay {
            ZStack {
                // 1. Le halo. La lumiere ne s'arrete pas net a l'arete : elle
                // deborde. Un second trait, plus epais et flou, pose SOUS le
                // trait net, fait la difference entre « un liseré ambre » et
                // « du verre eclaire de l'interieur » — c'est-a-dire entre la
                // bordure coloree que dessinerait n'importe quel gabarit et la
                // signature promise par la direction visuelle.
                filamentStroke(width: Theme.Metrics.filamentWidth * 2.5, opacity: 0.42)
                    .blur(radius: 2.5)

                // 2. Le trait net, qui donne l'arete.
                filamentStroke(width: Theme.Metrics.filamentWidth, opacity: 1.0)
            }
            .opacity(0.30 + 0.70 * intensity)
            .allowsHitTesting(false)
        }
    }

    /// Le liseré lui-meme. Le degradé horizontal l'eteint vers les flancs, le
    /// masque vertical l'eteint vers le haut : la lumiere se concentre donc
    /// sous la base et s'attarde aux deux coins convexes, exactement la ou une
    /// lumiere interne s'echapperait d'un boitier.
    private func filamentStroke(width: CGFloat, opacity: Double) -> some View {
        shape
            .strokeBorder(
                LinearGradient(
                    stops: [
                        .init(color: tint.opacity(0.0), location: 0.0),
                        .init(color: tint.opacity(0.85 * opacity), location: 0.35),
                        .init(color: tint.opacity(0.85 * opacity), location: 0.65),
                        .init(color: tint.opacity(0.0), location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                lineWidth: width
            )
            // Masque vertical : le filament s'eteint vers le haut. Le bord
            // superieur du panneau est plaque contre l'arete de la dalle,
            // ou un liseré ne se lit pas — il n'y ferait que du bruit.
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .clear, location: 0.45),
                        .init(color: .white, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            // Pas de `blendMode(.plusLighter)` : le mode de fusion remonte
            // au contexte de composition parent — ici une fenetre
            // transparente pleine largeur — et teinte toute la barre des
            // menus. L'eclat vient de l'opacite du trait, pas d'un blend.
    }
}

extension View {
    /// Applique le filament signature le long d'une forme.
    func filament<S: InsettableShape>(
        _ shape: S,
        intensity: Double,
        tint: Color = Theme.Palette.filament
    ) -> some View {
        modifier(FilamentOverlay(shape: shape, intensity: intensity, tint: tint))
    }
}

// MARK: - GlassCard
//
// Carte de contenu du panneau, traitee comme un CREUX TAILLE DANS LE VERRE de
// la coquille — pas comme une plaque posee dessus.
//
// CE QUI A CHANGE, ET POURQUOI. La carte peignait un aplat opaque
// (`Palette.slate`) : la coquille avait beau etre du Liquid Glass, chaque carte
// l'effacait sur toute sa surface, et le panneau se lisait comme un tableau de
// bord sombre. Le fond est desormais un degrade translucide (`wellFill`) et
// l'arete un biseau directionnel (`rim`), vif en haut, eteint en bas.
//
// PAS DE `.glassEffect` ICI, VOLONTAIREMENT. La coquille en pose deja un ; en
// rajouter un par carte ferait trois couches de materiau empilees, ce que les
// recommandations Liquid Glass deconseillent expressement — le verre ne sait
// plus a quoi s'adapter et tout vire au laiteux. Le relief vient donc de
// l'ARETE, qui est de toute facon la ou le materiau se lit vraiment.
//
// `imageBleed` retire le creux quand la carte encadre une image plein cadre :
// la lisibilite vient alors du contenu superpose, pas du fond.

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = Theme.Metrics.cardCornerRadius
    var imageBleed: Bool = false
    @ViewBuilder var content: Content

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        content
            .background {
                if !imageBleed {
                    // Le creux repose sur un voile d'encre. Son opacite est le
                    // reglage le plus sensible de tout le design system :
                    // mesuree a 0,34, la coloration syntaxique d'un editeur
                    // ouvert dessous traversait la carte et rendait les
                    // libelles illisibles. Le verre se lit a son arete, pas a
                    // ce qu'on distingue au travers — le voile peut donc etre
                    // dense sans rien couter au materiau.
                    shape.fill(Theme.Palette.ink.opacity(0.72))
                    shape.fill(Theme.Palette.wellFill)
                }
            }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(Theme.Palette.rim, lineWidth: 1)
            }
    }
}

// MARK: - Libelle grave
extension View {
    /// Nomenclature d'instrument : capitales minuscules et espacees. Les trois
    /// reglages — corps, casse, interlettrage — vont ensemble et ne doivent pas
    /// etre appliques separement, d'ou ce modificateur unique.
    func engraved(_ size: CGFloat = 9, color: Color = Theme.Palette.mist) -> some View {
        font(Theme.Typography.caption(size))
            .textCase(.uppercase)
            .tracking(Theme.Typography.engravedTracking)
            .foregroundStyle(color)
    }
}

// MARK: - GlassIconButton
//
// Bouton rond de la barre du haut. L'etat selectionne se lit au materiau —
// verre prominent neutre — et non a une pastille coloree rapportee.

struct GlassIconButton: View {
    let symbolName: String
    let accessibilityLabel: String
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 26)
        }
        .glassButton(isProminent: isActive, tint: isActive ? .white : nil)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

extension GlassIconButton {
    init(tab: NotchTab, isActive: Bool, action: @escaping () -> Void) {
        self.init(
            symbolName: tab.symbolName,
            accessibilityLabel: tab.accessibilityLabel,
            isActive: isActive,
            action: action
        )
    }
}

// MARK: - GlassActionButton
//
// Action primaire (« Démarrer »). Seul composant autorise a porter l'ambre en
// aplat : il doit rester unique a l'ecran.
//
// L'aplat n'est pas une coquetterie. `.glassProminent` seul laisse le materiau
// decider de sa luminosite d'apres le fond — pose sur le noir de l'encoche, un
// ambre teinte ressort gris. La couleur est posee en dessous pour etre garantie,
// le verre par-dessus pour le relief et la reaction au pointeur.

struct GlassActionButton: View {
    let title: String
    var symbolName: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbolName {
                    Image(systemName: symbolName)
                        .font(.system(size: 10, weight: .bold))
                }
                Text(title)
                    .font(Theme.Typography.body(11, weight: .semibold))
            }
            .foregroundStyle(Theme.Palette.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .accentSurface(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

// MARK: - GlassRoundButton
/// Commande ronde (pause, arret). `isAccented` distingue l'action de reprise du
/// simple arret, qui reste neutre.
struct GlassRoundButton: View {
    let symbolName: String
    let label: String
    var isAccented: Bool = false
    var side: CGFloat = 26
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: side * 0.42, weight: .bold))
                .foregroundStyle(isAccented ? Theme.Palette.ink : .white)
                .frame(width: side, height: side)
                .modifier(RoundSurface(isAccented: isAccented))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct RoundSurface: ViewModifier {
    let isAccented: Bool

    func body(content: Content) -> some View {
        if isAccented {
            content.accentSurface(.circle)
        } else {
            content
                .background(Circle().fill(Theme.Palette.slate.opacity(0.9)))
                .glassEffect(.regular, in: .circle)
        }
    }
}

// MARK: - Surface d'accent
extension View {
    /// Aplat ambre garanti, surmonte du materiau Liquid Glass.
    func accentSurface(_ shape: some Shape) -> some View {
        background(shape.fill(Theme.Palette.ember))
            .glassEffect(.regular.tint(Theme.Palette.ember).interactive(), in: shape)
    }
}

// MARK: - Style de bouton
//
// `.glass` et `.glassProminent` ne partagent pas de type commun : ce helper
// evite d'ecrire un `if` sur le style dans chaque appelant, ce qui casserait
// l'identite de vue et donc le morph.

extension View {
    @ViewBuilder
    func glassButton(isProminent: Bool, tint: Color?) -> some View {
        if isProminent {
            buttonStyle(.glassProminent).tint(tint ?? .white)
        } else {
            // `.clear` neutralise la teinte d'accent systeme heritee sur macOS :
            // sans cela, tous les boutons de verre virent au bleu.
            buttonStyle(.glass).tint(tint ?? .clear)
        }
    }
}
