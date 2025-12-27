import Foundation

/// Notes service for Apple Notes integration via AppleScript bridge
actor NotesService {
    // MARK: - Cache

    private var notesCache: [Note] = []
    private var foldersCache: [String] = []
    private var lastRefresh: Date?
    private let cacheExpiry: TimeInterval = 300 // 5 minutes

    // MARK: - Note Operations

    func getAllNotes(refresh: Bool = false) async throws -> [Note] {
        if !refresh, let last = lastRefresh, Date().timeIntervalSince(last) < cacheExpiry {
            return notesCache
        }

        let notes = try await fetchAllNotes()
        notesCache = notes
        lastRefresh = Date()
        return notes
    }

    func getNote(id: UUID) async -> Note? {
        notesCache.first { $0.id == id }
    }

    func getNote(sourceId: String) async -> Note? {
        notesCache.first { $0.sourceId == sourceId }
    }

    func searchNotes(query: String) async throws -> [Note] {
        let notes = try await getAllNotes()

        let queryLower = query.lowercased()
        return notes.filter { note in
            note.title.lowercased().contains(queryLower) ||
            note.plainTextBody.lowercased().contains(queryLower)
        }
    }

    func getNotesInFolder(_ folder: String) async throws -> [Note] {
        let notes = try await getAllNotes()
        return notes.filter { $0.folder == folder }
    }

    func getRecentNotes(limit: Int = 10) async throws -> [Note] {
        let notes = try await getAllNotes()
        return Array(notes.sorted { $0.modifiedAt > $1.modifiedAt }.prefix(limit))
    }

    func getPinnedNotes() async throws -> [Note] {
        let notes = try await getAllNotes()
        return notes.filter { $0.isPinned }
    }

    func getNotesWithChecklists() async throws -> [Note] {
        let notes = try await getAllNotes()
        return notes.filter { $0.hasChecklist }
    }

    // MARK: - Create/Update Notes

    func createNote(title: String, body: String, folder: String? = nil) async throws -> Note {
        // Use AppleScript to create note
        let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedBody = body.replacingOccurrences(of: "\"", with: "\\\"")

        var script = """
        tell application "Notes"
            tell account "iCloud"
        """

        if let folder = folder {
            script += """
                tell folder "\(folder)"
                    make new note with properties {name:"\(escapedTitle)", body:"\(escapedBody)"}
                end tell
            """
        } else {
            script += """
                make new note with properties {name:"\(escapedTitle)", body:"\(escapedBody)"}
            """
        }

        script += """
            end tell
        end tell
        """

        _ = try await runAppleScript(script)

        // Create local representation
        let note = Note(
            sourceId: UUID().uuidString,
            source: .appleNotes,
            title: title,
            body: body,
            plainTextBody: body,
            folder: folder,
            createdAt: Date(),
            modifiedAt: Date()
        )

        notesCache.append(note)
        return note
    }

    func appendToNote(_ note: Note, text: String) async throws -> Note {
        let escapedText = text.replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "Notes"
            tell account "iCloud"
                set theNote to note id "\(note.sourceId)"
                set body of theNote to (body of theNote) & "\\n" & "\(escapedText)"
            end tell
        end tell
        """

        _ = try await runAppleScript(script)

        var updated = note
        updated.body += "\n" + text
        updated.plainTextBody += "\n" + text
        updated.modifiedAt = Date()

        if let index = notesCache.firstIndex(where: { $0.id == note.id }) {
            notesCache[index] = updated
        }

        return updated
    }

    func updateNoteTitle(_ note: Note, newTitle: String) async throws -> Note {
        let escapedTitle = newTitle.replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "Notes"
            tell account "iCloud"
                set name of note id "\(note.sourceId)" to "\(escapedTitle)"
            end tell
        end tell
        """

        _ = try await runAppleScript(script)

        var updated = note
        updated.title = newTitle
        updated.modifiedAt = Date()

        if let index = notesCache.firstIndex(where: { $0.id == note.id }) {
            notesCache[index] = updated
        }

        return updated
    }

    func deleteNote(_ note: Note) async throws {
        let script = """
        tell application "Notes"
            tell account "iCloud"
                delete note id "\(note.sourceId)"
            end tell
        end tell
        """

        _ = try await runAppleScript(script)

        notesCache.removeAll { $0.id == note.id }
    }

    // MARK: - Folders

    func getFolders() async throws -> [String] {
        let script = """
        tell application "Notes"
            tell account "iCloud"
                get name of every folder
            end tell
        end tell
        """

        let result = try await runAppleScript(script)
        let folders = parseFolderList(result)
        foldersCache = folders
        return folders
    }

    func createFolder(name: String) async throws {
        let escapedName = name.replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "Notes"
            tell account "iCloud"
                make new folder with properties {name:"\(escapedName)"}
            end tell
        end tell
        """

        _ = try await runAppleScript(script)
        foldersCache.append(name)
    }

    func moveNote(_ note: Note, toFolder folder: String) async throws -> Note {
        let script = """
        tell application "Notes"
            tell account "iCloud"
                move note id "\(note.sourceId)" to folder "\(folder)"
            end tell
        end tell
        """

        _ = try await runAppleScript(script)

        var updated = note
        updated.folder = folder
        updated.modifiedAt = Date()

        if let index = notesCache.firstIndex(where: { $0.id == note.id }) {
            notesCache[index] = updated
        }

        return updated
    }

    // MARK: - Checklist Operations

    func addChecklistItem(_ note: Note, item: String, checked: Bool = false) async throws -> Note {
        let checkboxChar = checked ? "☑" : "☐"
        let text = "\(checkboxChar) \(item)"
        return try await appendToNote(note, text: text)
    }

    func toggleChecklistItem(_ note: Note, itemIndex: Int) async throws -> Note {
        guard itemIndex < note.checklistItems.count else {
            throw NotesServiceError.invalidOperation
        }

        var updated = note
        updated.checklistItems[itemIndex].isChecked.toggle()
        updated.modifiedAt = Date()

        // Rebuild note body with updated checklist
        var lines = note.plainTextBody.components(separatedBy: "\n")
        var checklistIndex = 0

        for (index, line) in lines.enumerated() {
            if line.hasPrefix("☐") || line.hasPrefix("☑") {
                if checklistIndex == itemIndex {
                    let isNowChecked = updated.checklistItems[itemIndex].isChecked
                    let newPrefix = isNowChecked ? "☑" : "☐"
                    lines[index] = newPrefix + String(line.dropFirst(1))
                    break
                }
                checklistIndex += 1
            }
        }

        let newBody = lines.joined(separator: "\n")
        let escapedBody = newBody.replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "Notes"
            tell account "iCloud"
                set body of note id "\(note.sourceId)" to "\(escapedBody)"
            end tell
        end tell
        """

        _ = try await runAppleScript(script)

        if let index = notesCache.firstIndex(where: { $0.id == note.id }) {
            notesCache[index] = updated
        }

        return updated
    }

    func getUncheckedItems() async throws -> [(Note, ChecklistItem)] {
        let notes = try await getAllNotes()
        var unchecked: [(Note, ChecklistItem)] = []

        for note in notes where note.hasChecklist {
            for item in note.uncheckedItems {
                unchecked.append((note, item))
            }
        }

        return unchecked
    }

    // MARK: - Quick Notes

    func createQuickNote(content: String) async throws -> Note {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        let title = "Quick Note - \(dateFormatter.string(from: Date()))"

        return try await createNote(title: title, body: content, folder: "Notes")
    }

    func appendToTodayNote(text: String) async throws -> Note {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let todayString = dateFormatter.string(from: Date())
        let todayTitle = "Daily Note - \(todayString)"

        // Check if today's note exists
        let notes = try await searchNotes(query: todayTitle)
        if let existingNote = notes.first(where: { $0.title == todayTitle }) {
            return try await appendToNote(existingNote, text: text)
        } else {
            return try await createNote(title: todayTitle, body: text, folder: "Daily Notes")
        }
    }

    // MARK: - Semantic Search

    func semanticSearch(query: String, embedding: [Float], topK: Int = 5) async throws -> [Note] {
        let notes = try await getAllNotes()

        // Filter notes that have embeddings
        let notesWithEmbeddings = notes.filter { $0.embedding != nil }

        // Calculate similarities
        var similarities: [(Note, Float)] = []
        for note in notesWithEmbeddings {
            if let noteEmbedding = note.embedding {
                let similarity = cosineSimilarity(embedding, noteEmbedding)
                similarities.append((note, similarity))
            }
        }

        // Sort by similarity and return top K
        return similarities
            .sorted { $0.1 > $1.1 }
            .prefix(topK)
            .map { $0.0 }
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }

        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }

        return dotProduct / denominator
    }

    // MARK: - AppleScript Bridge

    private func fetchAllNotes() async throws -> [Note] {
        let script = """
        tell application "Notes"
            set noteList to {}
            tell account "iCloud"
                repeat with aNote in notes
                    set noteInfo to {id of aNote, name of aNote, plaintext of aNote, creation date of aNote, modification date of aNote}
                    set end of noteList to noteInfo
                end repeat
            end tell
            return noteList
        end tell
        """

        let result = try await runAppleScript(script)
        return parseNotesList(result)
    }

    private func runAppleScript(_ script: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                if let appleScript = NSAppleScript(source: script) {
                    let output = appleScript.executeAndReturnError(&error)

                    if let error = error {
                        continuation.resume(throwing: NotesServiceError.scriptError(error.description))
                    } else {
                        continuation.resume(returning: output.stringValue ?? "")
                    }
                } else {
                    continuation.resume(throwing: NotesServiceError.scriptError("Failed to create AppleScript"))
                }
            }
        }
    }

    private func parseNotesList(_ result: String) -> [Note] {
        // Parse AppleScript output
        // This is a simplified implementation
        var notes: [Note] = []

        // AppleScript returns lists in a specific format
        // Real implementation would parse this properly

        return notes
    }

    private func parseFolderList(_ result: String) -> [String] {
        // Parse AppleScript folder list output
        result.components(separatedBy: ", ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Voice Commands

    func handleVoiceCommand(_ command: String) async throws -> String {
        let lower = command.lowercased()

        if lower.contains("create") || lower.contains("new note") {
            // Extract note content
            let content: String
            if let range = lower.range(of: "note") {
                content = String(command[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            } else if let range = lower.range(of: "create") {
                content = String(command[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            } else {
                content = command
            }

            if content.isEmpty {
                throw NotesServiceError.invalidOperation
            }

            let note = try await createQuickNote(content: content)
            return "Created note: \(note.title)"
        }

        if lower.contains("find") || lower.contains("search") {
            let query: String
            if let range = lower.range(of: "find") {
                query = String(command[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            } else if let range = lower.range(of: "search") {
                query = String(command[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            } else {
                throw NotesServiceError.invalidOperation
            }

            let results = try await searchNotes(query: query)
            if results.isEmpty {
                return "No notes found for '\(query)'"
            }
            return "Found \(results.count) note(s): \(results.prefix(3).map { $0.title }.joined(separator: ", "))"
        }

        if lower.contains("recent") || lower.contains("latest") {
            let notes = try await getRecentNotes(limit: 3)
            if notes.isEmpty {
                return "No recent notes"
            }
            return "Recent notes: \(notes.map { $0.title }.joined(separator: ", "))"
        }

        if lower.contains("add to") && lower.contains("today") {
            let text: String
            if let range = lower.range(of: "add") {
                var remaining = String(command[range.upperBound...])
                if let toRange = remaining.range(of: "to today") {
                    remaining = String(remaining[..<toRange.lowerBound])
                }
                text = remaining.trimmingCharacters(in: .whitespaces)
            } else {
                throw NotesServiceError.invalidOperation
            }

            _ = try await appendToTodayNote(text: text)
            return "Added to today's note"
        }

        throw NotesServiceError.unknownCommand
    }
}

// MARK: - Errors

enum NotesServiceError: Error, LocalizedError {
    case notFound
    case scriptError(String)
    case invalidOperation
    case unknownCommand

    var errorDescription: String? {
        switch self {
        case .notFound: return "Note not found"
        case .scriptError(let message): return "Script error: \(message)"
        case .invalidOperation: return "Invalid operation"
        case .unknownCommand: return "Unknown notes command"
        }
    }
}
