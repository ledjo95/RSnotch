import Foundation

// MARK: - LaunchItem
//
// Element de la grappe de lancement. Trois natures, a ne pas confondre :
//
//   .app        un bundle a lancer ;
//   .directory  un DOSSIER DU FINDER epingle. Un clic l'ouvre dans le Finder.
//               C'est un raccourci vers le disque, rien de plus ;
//   .folder     un GROUPE DE RACCOURCIS interne a RSnotch, garni en y glissant
//               des tuiles. Un clic ouvre son sous-panneau.
//
// Les deux derniers portent la meme icone de dossier mais n'ont rien a voir :
// l'un designe un emplacement reel, l'autre n'existe que dans l'app.
//
// La recursivite s'arrete a un niveau — un groupe ne contient que des
// applications. Des groupes imbriques dans un panneau de 150 pt de haut
// seraient impossibles a naviguer.

struct LaunchItem: Identifiable, Codable, Equatable, Sendable {

    enum Payload: Codable, Equatable, Sendable {
        /// Application designee par l'utilisateur. Le chemin sert d'affichage
        /// et de repli ; l'acces reel passe par le security-scoped bookmark.
        case app(path: String)
        /// Dossier du Finder epingle. Le chemin sert d'affichage et de repli ;
        /// l'acces reel passe par le security-scoped bookmark, comme pour une
        /// application.
        case directory(path: String)
        /// Groupe de raccourcis, interne a l'app.
        case folder(children: [LaunchItem])
    }

    let id: UUID
    var name: String
    var payload: Payload

    init(id: UUID = UUID(), name: String, payload: Payload) {
        self.id = id
        self.name = name
        self.payload = payload
    }

    // MARK: Derives

    /// Groupe de raccourcis interne. NE couvre PAS un dossier du Finder
    /// epingle : c'est cette distinction qui decide si un clic ouvre un
    /// sous-panneau ou le Finder.
    var isFolder: Bool {
        if case .folder = payload { return true }
        return false
    }

    var isDirectory: Bool {
        if case .directory = payload { return true }
        return false
    }

    var directoryPath: String? {
        if case .directory(let path) = payload { return path }
        return nil
    }

    var children: [LaunchItem] {
        if case .folder(let children) = payload { return children }
        return []
    }

    var appPath: String? {
        if case .app(let path) = payload { return path }
        return nil
    }

    /// Cle du security-scoped bookmark de cette application.
    var bookmarkKey: String { "launch.\(id.uuidString)" }

    // MARK: Fabriques

    static func app(url: URL) -> LaunchItem {
        LaunchItem(
            name: url.deletingPathExtension().lastPathComponent,
            payload: .app(path: url.path)
        )
    }

    static func directory(url: URL) -> LaunchItem {
        LaunchItem(name: url.lastPathComponent, payload: .directory(path: url.path))
    }

    static func folder(name: String = "Dossier") -> LaunchItem {
        LaunchItem(name: name, payload: .folder(children: []))
    }
}
