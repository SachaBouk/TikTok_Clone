import Foundation

// Chats de groupe (ADR-059) : privés, 32 membres au plus, amis seulement ; administrateur = membre le plus ancien ;
// nom facultatif (sinon les noms des membres) ; lignes d'événement dans la conversation.

struct GroupMember: Identifiable, Equatable, Sendable {
    var id: String { user.id }
    let user: UserSummary
    let joinedAt: Date
    // Dernier message lu (« Vu par »).
    var lastReadMessageID: String?
}

struct GroupChat: Equatable, Sendable {
    var name: String?
    // Le membre le plus ancien : lui seul retire un membre.
    var adminID: String
    // Groupe en sourdine pour le compte connecté (plus de notification push).
    var muted: Bool
    // Du plus ancien au plus récent, compte connecté compris.
    var members: [GroupMember]

    // Les autres membres, du plus ancien au plus récent.
    func others(ownID: String?) -> [UserSummary] {
        members.map(\.user).filter { $0.id != ownID }
    }

    // Nom du groupe, sinon les noms des autres membres : « Inès, Nathan et Léa », « Inès, Nathan et 3 autres ».
    func title(ownID: String?) -> String {
        if let name { return name }
        let names = others(ownID: ownID).map(\.displayName)
        return GroupRules.names(names)
    }

    // « Vu par Inès, Nathan », « Vu par 5 » : membres (sauf soi et les comptes masqués) qui ont lu `message`. Un membre
    // ajouté après le message ne compte pas : son repère de lecture part du dernier message à son entrée (ADR-059).
    func seenBy(_ message: DirectMessage, ownID: String?, hidden: Set<String> = []) -> [UserSummary] {
        members.filter { member in
            member.user.id != ownID && !hidden.contains(member.user.id) && member.joinedAt <= message.createdAt
                && member.lastReadMessageID.map { MessageRules.isAtOrBefore(message.id, $0) } == true
        }.map(\.user)
    }

    func isAdmin(_ userID: String?) -> Bool { userID == adminID }
}

// Ligne d'événement d'un groupe, faite par l'expéditeur du message.
struct GroupEvent: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case created
        case added
        case removed
        case left
        case renamed
    }

    let kind: Kind
    // Membre ajouté ou retiré ; nil si son compte n'existe plus.
    let user: UserSummary?
    // Nouveau nom d'un renommage ; nil : nom retiré.
    let name: String?

    // « Inès a créé le groupe », « Tu as ajouté Nathan », « Inès t’a ajouté(e) », « Nathan a quitté le groupe »,
    // « Inès a renommé le groupe « Vacances » ».
    func text(actor: UserSummary?, ownID: String?) -> String {
        let isOwn = actor?.id == ownID && ownID != nil
        let who = isOwn ? "Tu" : (actor?.displayName ?? "Un compte supprimé")
        let target: String = {
            guard let user else { return "un compte supprimé" }
            return user.id == ownID ? "toi" : user.displayName
        }()
        switch kind {
        case .created:
            return isOwn ? "Tu as créé le groupe" : "\(who) a créé le groupe"
        case .added:
            if user?.id == ownID, !isOwn { return "\(who) t’a ajouté(e) au groupe" }
            return isOwn ? "Tu as ajouté \(target)" : "\(who) a ajouté \(target)"
        case .removed:
            if user?.id == ownID, !isOwn { return "\(who) t’a retiré(e) du groupe" }
            return isOwn ? "Tu as retiré \(target)" : "\(who) a retiré \(target)"
        case .left:
            return isOwn ? "Tu as quitté le groupe" : "\(who) a quitté le groupe"
        case .renamed:
            guard let name else { return isOwn ? "Tu as retiré le nom du groupe" : "\(who) a retiré le nom du groupe" }
            return isOwn ? "Tu as renommé le groupe « \(name) »" : "\(who) a renommé le groupe « \(name) »"
        }
    }
}

enum GroupRules {
    static let maxMembers = 32
    // Au moins 2 amis à la création : un groupe de deux serait une conversation à deux.
    static let minFriends = 2
    static let maxNameLength = 50

    // Nom nettoyé comme l'API ; nil s'il est vide.
    static func cleanedName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // « Inès », « Inès et Nathan », « Inès, Nathan et Léa », « Inès, Nathan et 3 autres ».
    static func names(_ names: [String], visible: Int = 2) -> String {
        switch names.count {
        case 0: return "Groupe"
        case 1: return names[0]
        case 2: return "\(names[0]) et \(names[1])"
        case 3: return "\(names[0]), \(names[1]) et \(names[2])"
        default: return "\(names.prefix(visible).joined(separator: ", ")) et \(names.count - visible) autres"
        }
    }

    // « Vu par Inès, Nathan », au-delà de 3 lecteurs « Vu par 5 ».
    static func seenLabel(_ readers: [UserSummary]) -> String? {
        guard !readers.isEmpty else { return nil }
        if readers.count > 3 { return "Vu par \(readers.count)" }
        return "Vu par \(readers.map(\.displayName).joined(separator: ", "))"
    }

    // « Inès écrit… », « Inès et Nathan écrivent… », « 3 personnes écrivent… ».
    static func typingLabel(_ names: [String]) -> String? {
        switch names.count {
        case 0: return nil
        case 1: return "\(names[0]) écrit…"
        case 2: return "\(names[0]) et \(names[1]) écrivent…"
        default: return "\(names.count) personnes écrivent…"
        }
    }

    // Amis choisis à la création : au moins 2, et au plus 31 (le créateur compte).
    static func canCreate(selected: Int) -> Bool {
        selected >= minFriends && selected < maxMembers
    }

    // Places restantes dans un groupe de `members` membres.
    static func remainingPlaces(members: Int) -> Int {
        max(0, maxMembers - members)
    }
}
