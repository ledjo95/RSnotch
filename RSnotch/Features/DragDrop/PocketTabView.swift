import AppKit
import SwiftUI

// MARK: - PocketTabView
//
// Contenu de la Pocket, regroupe par DEPOT et non par fichier : trois fichiers
// laches ensemble forment une seule carte, et se reprennent ensemble. Un
// fichier lache seul reste une carte simple qui ne rend que lui.
//
// Reprise : la copie vit dans le conteneur de l'app, le destinataire la lit
// directement. Pas de promesse de fichier a honorer, donc rien a maintenir
// pendant le glisser. Un lot d'un seul fichier passe par `draggable` ; au-dela,
// il faut une session AppKit (voir FileDragHandle), SwiftUI ne publiant qu'un
// element a la fois.

struct PocketTabView: View {

    @Bindable var pocket: PocketStorageService

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.contentSpacing) {
            header
            content
        }
    }

    // MARK: En-tete

    private var header: some View {
        HStack {
            Text(headerLabel)
                .font(Theme.Typography.body(11, weight: .medium))
                .foregroundStyle(Theme.Palette.mist)

            Spacer(minLength: 8)

            Button {
                withAnimation(Theme.Motion.morph) { pocket.clear() }
            } label: {
                Label("Tout vider", systemImage: "trash")
                    .font(Theme.Typography.body(10, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.Palette.signal)
            .background(Capsule().fill(Theme.Palette.slate.opacity(0.7)))
            .disabled(pocket.items.isEmpty)
        }
    }

    // MARK: Contenu

    @ViewBuilder
    private var content: some View {
        if pocket.batches.isEmpty {
            GlassCard {
                VStack(spacing: 6) {
                    Image(systemName: "tray")
                        .font(.system(size: 18, weight: .medium))
                    Text("Déposez des fichiers sur la zone Pocket pour les garder ici.")
                        .font(Theme.Typography.body(11))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(Theme.Palette.mist)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Metrics.contentSpacing) {
                    ForEach(pocket.batches) { batch in
                        card(for: batch)
                    }
                }
                .padding(.horizontal, 1)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .animation(Theme.Motion.morph, value: pocket.batches)
        }
    }

    private var headerLabel: String {
        guard !pocket.batches.isEmpty else { return "Pocket vide" }
        let files = pocket.items.count
        let filesLabel = "\(files) fichier\(files > 1 ? "s" : "")"
        guard pocket.batches.count != files else { return filesLabel }
        return "\(filesLabel) · \(pocket.batches.count) dépôts"
    }

    private func card(for batch: PocketBatch) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                icons(for: batch)
                Spacer(minLength: 0)
                Text(batch.title)
                    .font(Theme.Typography.body(11, weight: .medium))
                    .foregroundStyle(Theme.Palette.frost)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text(subtitle(for: batch))
                    .font(Theme.Typography.data(9))
                    .foregroundStyle(Theme.Palette.mist)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(10)
        }
        .frame(width: batch.isSingle ? 120 : 140)
        .modifier(BatchDrag(batch: batch))
        .contextMenu { menu(for: batch) }
        .help(batch.isSingle ? batch.title : batch.items.map(\.name).joined(separator: "\n"))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            batch.isSingle
                ? "\(batch.title), \(batch.formattedSize)"
                : "Dépôt de \(batch.items.count) fichiers, \(batch.formattedSize)"
        )
    }

    /// Icones du depot. Au-dela d'un fichier, elles se chevauchent : la pile
    /// dit d'un coup d'oeil qu'on emportera plusieurs elements.
    private func icons(for batch: PocketBatch) -> some View {
        HStack(spacing: -12) {
            ForEach(Array(batch.items.prefix(3).enumerated()), id: \.element.id) { index, item in
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                    .resizable()
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Theme.Palette.slate)
                            .padding(-1)
                    )
                    .zIndex(Double(3 - index))
            }
            if batch.items.count > 3 {
                Text("+\(batch.items.count - 3)")
                    .font(Theme.Typography.data(9, weight: .medium))
                    .foregroundStyle(Theme.Palette.mist)
                    .padding(.leading, 16)
            }
        }
    }

    private func subtitle(for batch: PocketBatch) -> String {
        guard !batch.isSingle else { return batch.formattedSize }
        return "\(batch.formattedSize) · \(batch.items.map(\.name).joined(separator: ", "))"
    }

    @ViewBuilder
    private func menu(for batch: PocketBatch) -> some View {
        Button("Afficher dans le Finder", systemImage: "folder") {
            NSWorkspace.shared.activateFileViewerSelecting(batch.urls)
        }
        Button("Envoyer par AirDrop", systemImage: "dot.radiowaves.right") {
            AirDropSender.send(batch.urls)
        }
        if !batch.isSingle {
            Divider()
            Menu("Retirer un fichier") {
                ForEach(batch.items) { item in
                    Button(item.name, role: .destructive) {
                        withAnimation(Theme.Motion.morph) { pocket.remove(item) }
                    }
                }
            }
        }
        Divider()
        Button(
            batch.isSingle ? "Retirer" : "Retirer le dépôt",
            systemImage: "trash",
            role: .destructive
        ) {
            withAnimation(Theme.Motion.morph) { pocket.remove(batch) }
        }
    }
}

// MARK: - BatchDrag
//
// Un seul fichier : `draggable` suffit, et rend l'apercu SwiftUI standard.
// Plusieurs : il faut une session AppKit, seule capable de publier autant
// d'elements que de fichiers.

private struct BatchDrag: ViewModifier {
    let batch: PocketBatch

    func body(content: Content) -> some View {
        if let single = batch.items.first, batch.isSingle {
            content.draggable(single.url)
        } else {
            content.overlay { FileDragHandle(urls: batch.urls) }
        }
    }
}
