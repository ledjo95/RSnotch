import SwiftUI
import SwiftData

// MARK: - ClipboardTabView
//
// Onglet presse-papiers : une rangee de filtres, un bouton de vidage, puis
// l'historique en bande horizontale.
//
// Le tri vient de SwiftData ; le filtrage par type se fait en memoire. Avec une
// limite de deux cents entrees, un predicat par onglet couterait plus en
// complexite (et en requetes recompilees a chaque changement de filtre) qu'il
// ne ferait gagner.

struct ClipboardTabView: View {

    @Environment(\.modelContext) private var context
    @Query(sort: \ClipboardEntry.createdAt, order: .reverse)
    private var entries: [ClipboardEntry]

    @State private var filter: ClipboardFilter = .recent

    private var actions: ClipboardActions { ClipboardActions(context: context) }

    private var visible: [ClipboardEntry] {
        switch filter {
        case .recent:
            return entries
        case .favorites:
            return entries.filter(\.isFavorite)
        default:
            guard let kind = filter.kind else { return entries }
            return entries.filter { $0.kind == kind }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.contentSpacing) {
            header
            history
        }
    }

    // MARK: En-tete

    private var header: some View {
        HStack(spacing: Theme.Metrics.contentSpacing) {
            GlassSegmentedRow(
                items: ClipboardFilter.allCases,
                selection: $filter
            ) { $0.title }

            Spacer(minLength: 8)

            Button {
                withAnimation(Theme.Motion.morph) { actions.clearAll() }
            } label: {
                Label("Tout effacer", systemImage: "trash")
                    .font(Theme.Typography.body(10, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.Palette.signal)
            .background(Capsule().fill(Theme.Palette.slate.opacity(0.7)))
            .disabled(entries.allSatisfy(\.isFavorite))
            .help("Vide l’historique en conservant les favoris")
        }
    }

    // MARK: Historique

    @ViewBuilder
    private var history: some View {
        if visible.isEmpty {
            emptyState
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Metrics.contentSpacing) {
                    ForEach(visible) { entry in
                        ClipboardEntryCard(entry: entry, actions: actions)
                    }
                }
                .padding(.horizontal, 1)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .animation(Theme.Motion.morph, value: visible.map(\.id))
        }
    }

    private var emptyState: some View {
        GlassCard {
            VStack(spacing: 6) {
                Image(systemName: filter == .favorites ? "star" : "doc.on.clipboard")
                    .font(.system(size: 18, weight: .medium))
                Text(emptyMessage)
                    .font(Theme.Typography.body(11))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(Theme.Palette.mist)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyMessage: String {
        switch filter {
        case .recent: "Copiez quelque chose pour commencer l’historique."
        case .favorites: "Aucun favori. Épinglez une entrée pour la garder."
        default: "Rien de ce type dans l’historique."
        }
    }
}
