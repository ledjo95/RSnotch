import AppKit
import SwiftUI

// MARK: - RelativeAge
//
// Anciennete en une poignee de caracteres. `Date.FormatStyle.relative` rend
// « −2 s » dans le style le plus court : le signe negatif n'a aucun sens pour
// un utilisateur, et la forme longue (« il y a 2 secondes ») ne tient pas dans
// le pied d'une carte de 150 pt.

enum RelativeAge {
    static func short(since date: Date, now: Date = .now) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case ..<60: return "\(seconds) s"
        case ..<3_600: return "\(seconds / 60) min"
        case ..<86_400: return "\(seconds / 3_600) h"
        default: return "\(seconds / 86_400) j"
        }
    }
}

// MARK: - ClipboardEntryCard
//
// Une capture du presse-papiers. Le contenu occupe toute la carte ; les
// metadonnees (application source, anciennete) tiennent sur une seule ligne en
// bas, et les actions n'apparaissent qu'au survol — une rangee de six cartes
// couverte de boutons serait illisible dans une bande de 150 pt.

struct ClipboardEntryCard: View {

    let entry: ClipboardEntry
    let actions: ClipboardActions

    @State private var isHovering = false

    static let width: CGFloat = 150

    var body: some View {
        GlassCard(imageBleed: entry.kind == .image || entry.kind == .color) {
            ZStack(alignment: .bottomLeading) {
                content
                footer
                if isHovering { actionBar }
            }
        }
        .frame(width: Self.width)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .onTapGesture { actions.copy(entry) }
        .contextMenu { menu }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Contenu par type

    @ViewBuilder
    private var content: some View {
        switch entry.kind {
        case .image:
            if let image = entry.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                missing
            }

        case .color:
            ZStack(alignment: .bottomLeading) {
                Color(nsColor: entry.color ?? .darkGray)
                Text(entry.text ?? "")
                    .font(Theme.Typography.data(12, weight: .semibold))
                    .foregroundStyle(legibleTextColor)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 24)
            }

        case .text:
            Text(entry.text ?? "")
                .font(Theme.Typography.body(10))
                .foregroundStyle(Theme.Palette.frost)
                .lineLimit(7)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(10)
                .padding(.bottom, 14)

        case .file:
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Theme.Palette.mist)
                Text(fileName)
                    .font(Theme.Typography.body(11, weight: .medium))
                    .foregroundStyle(Theme.Palette.frost)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(10)
            .padding(.bottom, 14)
        }
    }

    private var missing: some View {
        Image(systemName: "photo.badge.exclamationmark")
            .font(.system(size: 20))
            .foregroundStyle(Theme.Palette.mist)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Pied de carte

    private var footer: some View {
        HStack(spacing: 4) {
            if let icon = entry.sourceIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 12, height: 12)
            }
            Text(RelativeAge.short(since: entry.createdAt))
                .font(Theme.Typography.data(9))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
            Spacer(minLength: 0)
            if entry.isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(Theme.Palette.ember)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        // Voile sombre : le pied se pose sur des images arbitraires, il lui
        // faut son propre fond pour rester lisible.
        .background(.black.opacity(0.45))
    }

    // MARK: Actions au survol

    private var actionBar: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)
            iconButton(
                entry.isFavorite ? "star.slash" : "star",
                entry.isFavorite ? "Retirer des favoris" : "Ajouter aux favoris"
            ) { actions.toggleFavorite(entry) }
            iconButton("doc.on.doc", "Copier à nouveau") { actions.copy(entry) }
            iconButton("trash", "Supprimer") { actions.delete(entry) }
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .transition(.opacity)
    }

    private func iconButton(
        _ symbol: String,
        _ label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.glass)
        .tint(.clear)
        .help(label)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var menu: some View {
        Button("Copier à nouveau", systemImage: "doc.on.doc") { actions.copy(entry) }
        Button(
            entry.isFavorite ? "Retirer des favoris" : "Ajouter aux favoris",
            systemImage: entry.isFavorite ? "star.slash" : "star"
        ) { actions.toggleFavorite(entry) }
        Divider()
        Button("Supprimer", systemImage: "trash", role: .destructive) { actions.delete(entry) }
    }

    // MARK: Derives

    private var fileName: String {
        guard let path = entry.text else { return "Fichier" }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    /// Noir ou blanc selon la luminance de la couleur copiee, pour que le code
    /// hex reste lisible sur un pastel comme sur un bleu nuit.
    private var legibleTextColor: Color {
        guard let color = entry.color?.usingColorSpace(.sRGB) else { return .white }
        let luminance = 0.2126 * color.redComponent
            + 0.7152 * color.greenComponent
            + 0.0722 * color.blueComponent
        return luminance > 0.6 ? Color(nsColor: .black) : .white
    }

    private var accessibilityDescription: String {
        switch entry.kind {
        case .text: "Texte copié : \(entry.text?.prefix(60) ?? "")"
        case .color: "Couleur copiée \(entry.text ?? "")"
        case .image: "Image copiée"
        case .file: "Fichier copié \(fileName)"
        }
    }
}
