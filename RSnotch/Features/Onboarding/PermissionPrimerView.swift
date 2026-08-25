import AppKit
import SwiftUI

// MARK: - PermissionPrimerView
//
// Invite de premiere ouverture, montree UNE SEULE FOIS, avant que la boite
// systeme d'Accessibilite ne surgisse.
//
// POURQUOI EXPLIQUER AVANT. Le remplacement du HUD de macOS — la fonction phare
// de RSnotch depuis la sortie du bac a sable — exige d'intercepter les touches
// son et luminosite, donc l'autorisation Accessibilite. Une boite systeme qui
// surgit seule, sans contexte, est refusee par reflexe : l'utilisateur ne sait
// pas pourquoi une app de notch veut « controler son ordinateur ». Cette vue
// pose le motif, puis DECLENCHE la vraie demande. Refuser reste possible et
// sans consequence : les deux jauges cohabitent, l'app fonctionne.

struct PermissionPrimerView: View {

    /// Appelee quand l'utilisateur accepte : declenche la demande systeme.
    let onAuthorize: () -> Void
    /// Appelee quand il remet a plus tard.
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.2.square")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Theme.Palette.ember)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(Theme.Palette.ember.opacity(0.14)))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Jauges dans l’encoche")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Sans le HUD de macOS.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Text("""
            Pour afficher ses propres jauges et masquer celles de macOS, RSnotch \
            doit lire les touches de volume et de luminosité avant le système. \
            Cela demande l’autorisation d’accessibilité.

            Rien ne quitte votre Mac. Vous pouvez révoquer l’autorisation à tout \
            moment dans Réglages Système, ou la refuser maintenant — les deux \
            jauges coexisteront alors.
            """)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Spacer()
                Button("Plus tard", action: onDismiss)
                    .keyboardShortcut(.cancelAction)
                Button("Autoriser…", action: onAuthorize)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 380)
    }
}
