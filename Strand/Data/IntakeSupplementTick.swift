import Foundation
import WhoopStore

/// The daily supplement tick (stage 3 specification §10.6). A supplement is a Journal question, and
/// the tick and the Journal card are two controls over one row: the native Journal answer under
/// `Repository.journalDeviceId`, which is not a strap id (stage 1 ruling R42). Ticking writes a
/// "yes"; unticking clears the answer and never writes a "no".
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
@MainActor
struct IntakeSupplementTick {
    private let repository: Repository
    private let settings: IntakeSettings

    init(repository: Repository, settings: IntakeSettings) {
        self.repository = repository
        self.settings = settings
    }

    /// "Did you take <name>?", the canonical Journal question for a supplement name. Data, never
    /// localised: a translated key would start a new, disconnected Journal behaviour.
    static func question(forName name: String) -> String {
        "Did you take \(name.trimmingCharacters(in: .whitespacesAndNewlines))?"
    }

    /// Question to true (ticked), false (answered no in the Journal) or nil (not recorded), one key
    /// per listed supplement. Empty, with no read, when none is listed.
    func states(day: String) async -> [String: Bool?] {
        let questions = settings.supplementQuestions
        guard !questions.isEmpty else { return [:] }
        let answers = await repository.nativeJournalAnswers(day: day)
        var states: [String: Bool?] = [:]
        for question in questions {
            let key = Self.storedMatch(question, in: answers.keys)
            states[question] = .some(key.flatMap { answers[$0] })
        }
        return states
    }

    /// Ticked: a "yes" answer. Unticked: the answer is cleared, so the day reads "not recorded".
    func set(_ ticked: Bool, question: String, day: String) async {
        if ticked {
            await repository.saveJournalAnswer(day: day, question: question, answeredYes: true)
        } else {
            let answers = await repository.nativeJournalAnswers(day: day)
            guard let stored = Self.storedMatch(question, in: answers.keys) else { return }
            await repository.clearJournalAnswer(day: day, question: stored)
        }
    }

    /// Lists a supplement: the canonical question is created in the Journal catalogue (kind yes/no,
    /// group Supplements) unless the catalogue already holds it, which is then adopted. False and no
    /// write when the list is full or already holds the question.
    @discardableResult
    func addSupplement(named name: String, catalog: JournalCatalogStore) -> Bool {
        let question = Self.question(forName: name)
        guard settings.supplementQuestions.count < IntakeSettings.maxSupplements,
              !settings.supplementQuestions.contains(where: {
                  JournalCatalogStore.norm($0) == JournalCatalogStore.norm(question)
              }) else { return false }
        // An item the owner already has, saved or a starter, is adopted rather than duplicated.
        let key = JournalCatalogStore.norm(question)
        let existing = catalog.item(for: question)?.canonical
            ?? JournalCatalogStore.starterQuestions.first { JournalCatalogStore.norm($0) == key }
        guard settings.addSupplementQuestion(existing ?? question) else { return false }
        if existing == nil { catalog.addCustom(question, kind: .bool, group: .supplements) }
        return true
    }

    /// The stored question among `keys` that is the same Journal question as `question`: surrounding
    /// whitespace removed, case ignored. Nil when none is.
    private static func storedMatch(_ question: String, in keys: Dictionary<String, Bool>.Keys) -> String? {
        let wanted = question.trimmingCharacters(in: .whitespacesAndNewlines)
        return keys.first {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(wanted) == .orderedSame
        }
    }
}
