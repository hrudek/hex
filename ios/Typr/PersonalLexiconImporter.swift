import Contacts
import Foundation
import Observation

/// Contacts and dictation data never cross into the extension: only the bounded token file does.
@MainActor
@Observable
final class PersonalLexiconImporter {
    static let shared = PersonalLexiconImporter()
    private(set) var problem: String?
    private var generation = 0
    private var lastInput: [String]?
    private var pending: Task<Void, Never>?
    private let defaults = UserDefaults(suiteName: KeyboardBridge.appGroup)

    var contactsEnabled: Bool { defaults?.bool(forKey: ProtectedPersonalLexicon.contactsKey) == true }
    var vocabularyEnabled: Bool { defaults?.bool(forKey: ProtectedPersonalLexicon.vocabularyKey) == true }

    func setContacts(_ enabled: Bool) async {
        let reset = defaults?.string(forKey: ProtectedPersonalLexicon.resetKey)
        if enabled {
            do {
                guard try await CNContactStore().requestAccess(for: .contacts) else {
                    problem = "Contacts access was not granted. You can change access in iOS Settings."
                    return
                }
            } catch {
                problem = "Typr could not request contacts access. Try again in iOS Settings."
                return
            }
        }
        guard reset == defaults?.string(forKey: ProtectedPersonalLexicon.resetKey) else { return }
        defaults?.set(enabled, forKey: ProtectedPersonalLexicon.contactsKey)
        refresh(force: true)
    }

    func setVocabulary(_ enabled: Bool) {
        defaults?.set(enabled, forKey: ProtectedPersonalLexicon.vocabularyKey)
        refresh(force: true)
    }

    func clear() {
        generation &+= 1
        pending?.cancel()
        lastInput = nil
        do {
            try ProtectedPersonalLexicon.reset(directory: KeyboardLearningStore.sharedDirectory, defaults: defaults)
            problem = nil
        } catch { problem = "Typr could not delete imported words. Try again." }
    }

    func refresh(force: Bool = false) {
        let contacts = contactsEnabled
        let vocabulary = vocabularyEnabled
        var texts: [String] = []
        if vocabulary {
            texts = CustomVocabularySettings().activeTerms
            // Final output only, never rejected ASR/model answers or sounds-like misspellings.
            // The existing recent cache is bounded; no archive walk or raw audio read.
            let recent = DictationLogStore.shared.entries
                .sorted { lhs, rhs in
                    if lhs.context.createdAt != rhs.context.createdAt { return lhs.context.createdAt > rhs.context.createdAt }
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                .prefix(DictationLogStore.maximumEntries)
            for entry in recent where entry.status == .finished {
                if let text = entry.finalText?.text { texts.append(text) }
            }
        }
        let input = [contacts ? "contacts" : "", vocabulary ? "vocabulary" : ""] + texts
        guard force || input != lastInput else { return }
        lastInput = input
        generation &+= 1
        let revision = generation
        pending?.cancel()
        if !contacts && !vocabulary {
            pending = nil
            do {
                // No defaults mutation/notification loop and no empty-file recreation after reset.
                try ProtectedPersonalLexicon.reset(directory: KeyboardLearningStore.sharedDirectory, defaults: nil)
                problem = nil
            } catch {
                lastInput = nil
                problem = "Typr could not delete imported words. Open Typr to retry."
            }
            return
        }
        let sourceTexts = texts
        pending = Task { [weak self] in
            let worker = Task.detached(priority: .utility) {
                Self.build(texts: sourceTexts, contacts: contacts)
            }
            let result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard let self, self.generation == revision, !Task.isCancelled,
                  self.contactsEnabled == contacts, self.vocabularyEnabled == vocabulary else { return }
            do {
                try result.lexicon.write(directory: KeyboardLearningStore.sharedDirectory)
                self.problem = result.problem
            } catch {
                self.lastInput = nil
                self.problem = "Typr could not save imported words. Open Typr to retry."
            }
        }
    }

    private nonisolated static func build(texts: [String], contacts: Bool)
        -> (lexicon: ProtectedPersonalLexicon, problem: String?) {
        var builder = ProtectedPersonalLexicon.Builder()
        for text in texts {
            if Task.isCancelled { return (.empty, nil) }
            builder.add(text)
        }
        var problem: String?
        if contacts {
            do {
                let keys: [CNKeyDescriptor] = [CNContactGivenNameKey as CNKeyDescriptor,
                    CNContactFamilyNameKey as CNKeyDescriptor, CNContactNicknameKey as CNKeyDescriptor,
                    CNContactOrganizationNameKey as CNKeyDescriptor]
                let request = CNContactFetchRequest(keysToFetch: keys)
                var contactBuilder = builder
                try CNContactStore().enumerateContacts(with: request) { contact, stop in
                    if Task.isCancelled { stop.pointee = true; return }
                    contactBuilder.add(contact.givenName)
                    contactBuilder.add(contact.familyName)
                    contactBuilder.add(contact.nickname)
                    contactBuilder.add(contact.organizationName)
                }
                builder = contactBuilder
            } catch { problem = "Typr could not read contacts. Check Contacts access in iOS Settings." }
        }
        return (builder.build(), problem)
    }
}
