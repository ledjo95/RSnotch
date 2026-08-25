import SwiftUI

// MARK: - TrayTabView
//
// Deux cibles de depot : envoyer par AirDrop, ou ranger dans la Pocket.
//
// Le contour en pointilles n'est pas decoratif : il distingue au premier coup
// d'oeil une zone qui ATTEND quelque chose d'une carte qui affiche du contenu.
// Les deux cartes s'illuminent separement, pour qu'on sache laquelle recevra le
// fichier avant de lacher.

struct TrayTabView: View {

    @Bindable var pocket: PocketStorageService
    @Bindable var launcher: LaunchItemsViewModel
    /// Rend la main a l'onglet voulu une fois le depot traite.
    let finish: (NotchTab?) -> Void
    /// Maintient le panneau ouvert le temps de lire le retour.
    let holdOpen: () -> Void
    /// Signale qu'un fichier survole une zone : annule tout repli en attente.
    let keepOpen: () -> Void

    @State private var targeted: Target?
    @State private var flash: Flash?

    private enum Target { case airdrop, pocket, pin }

    private struct Flash: Equatable {
        let target: Target
        let message: String
        let isError: Bool
    }

    var body: some View {
        HStack(spacing: Theme.Metrics.contentSpacing) {
            dropZone(
                .airdrop,
                symbol: "dot.radiowaves.right",
                title: "AirDrop",
                subtitle: "Envoyer à un appareil proche"
            ) { urls in
                guard AirDropSender.send(urls) else {
                    show(.airdrop, "AirDrop indisponible", isError: true)
                    return false
                }
                show(.airdrop, "Feuille d’envoi ouverte", isError: false)
                return true
            }

            dropZone(
                .pocket,
                symbol: "tray.and.arrow.down",
                title: "Pocket",
                subtitle: "Garder sous la main",
                mode: .materialized
            ) { urls in
                let added = pocket.add(urls, movingSource: true)
                guard added > 0 else {
                    show(.pocket, pocket.lastError ?? "Copie impossible", isError: true)
                    return false
                }
                show(.pocket, added == 1 ? "1 fichier rangé" : "\(added) fichiers rangés",
                     isError: false)
                finish(.pocket)
                return true
            }

            dropZone(
                .pin,
                symbol: "square.grid.2x2",
                title: "Épingler",
                subtitle: "Applications et dossiers"
            ) { urls in
                launcher.clearError()
                let added = launcher.add(urls)
                guard added > 0 else {
                    show(.pin, launcher.lastError ?? "Ni application ni dossier", isError: true)
                    return false
                }
                show(.pin, added == 1 ? "1 élément épinglé" : "\(added) éléments épinglés",
                     isError: false)
                finish(.home)
                return true
            }
        }
    }

    // MARK: Zone

    private func dropZone(
        _ target: Target,
        symbol: String,
        title: String,
        subtitle: String,
        mode: FileDropMode = .reference,
        onDrop: @escaping @MainActor @Sendable ([URL]) -> Bool
    ) -> some View {
        let isTargeted = targeted == target
        let flashMessage = flash?.target == target ? flash : nil

        return VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(isTargeted ? Theme.Palette.ember : Theme.Palette.mist)
            VStack(spacing: 2) {
                Text(title)
                    .font(Theme.Typography.body(13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.frost)
                Text(flashMessage?.message ?? subtitle)
                    .font(Theme.Typography.body(10))
                    .foregroundStyle(
                        flashMessage.map { $0.isError ? Theme.Palette.signal : Theme.Palette.ember }
                            ?? Theme.Palette.mist
                    )
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.Metrics.cardCornerRadius, style: .continuous)
                .fill(Theme.Palette.slate.opacity(isTargeted ? 0.9 : 0.55))
        )
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Metrics.cardCornerRadius, style: .continuous)
                .strokeBorder(
                    isTargeted ? Theme.Palette.ember : Theme.Palette.filament,
                    style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: [5, 4])
                )
        }
        .animation(Theme.Motion.morph, value: isTargeted)
        .fileDropDestination(
            mode: mode,
            isTargeted: Binding(
                get: { targeted == target },
                set: { active in
                    // Tant qu'une zone est visee, le panneau ne doit pas se
                    // refermer : le compte a rebours lance en quittant
                    // l'encoche est annule ici.
                    if active { keepOpen() }
                    targeted = active ? target : nil
                }
            )
        ) { urls in
            targeted = nil
            holdOpen()
            _ = onDrop(urls)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
    }

    // MARK: Retour

    /// Message bref a la place du sous-titre. Une zone de depot qui ne dit rien
    /// apres un lacher laisse croire que le geste a echoue.
    private func show(_ target: Target, _ message: String, isError: Bool) {
        let entry = Flash(target: target, message: message, isError: isError)
        withAnimation(Theme.Motion.morph) { flash = entry }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard flash == entry else { return }
            withAnimation(Theme.Motion.collapse) { flash = nil }
        }
    }
}
