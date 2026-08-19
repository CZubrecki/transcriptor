import Foundation

public struct OrganizedDocument: Sendable, Equatable {
  public struct Section: Sendable, Equatable {
    public var title: String
    public var summary: String
    public var keyPoints: [String]
    public var guidance: [String]
    public var caveats: [String]
  }

  public var title: String
  public var overview: String
  public var sections: [Section]
  public var termIndex: [String]
}

public enum DocumentMerger {
  public static func merge(notes: [ChunkNotes], outline: DocumentOutline?) -> OrganizedDocument {
    let sections: [OrganizedDocument.Section]
    if let outline, !outline.groups.isEmpty {
      var consumed: Set<Int> = []
      var groupSections: [OrganizedDocument.Section] = []
      for group in outline.groups {
        let indices = group.chunkIndices.filter { notes.indices.contains($0) && !consumed.contains($0) }
        guard !indices.isEmpty else { continue }
        indices.forEach { consumed.insert($0) }
        let members = indices.map { notes[$0] }
        groupSections.append(OrganizedDocument.Section(
          title: group.title,
          summary: members.map(\.summary).joined(separator: " "),
          keyPoints: members.flatMap(\.keyPoints),
          guidance: members.flatMap(\.guidance),
          caveats: members.flatMap(\.caveats)))
      }
      let orphanSections = notes.indices.filter { !consumed.contains($0) }.map { index -> OrganizedDocument.Section in
        let note = notes[index]
        return OrganizedDocument.Section(
          title: note.topic, summary: note.summary,
          keyPoints: note.keyPoints, guidance: note.guidance, caveats: note.caveats)
      }
      sections = groupSections + orphanSections
    } else {
      sections = notes.map {
        OrganizedDocument.Section(
          title: $0.topic, summary: $0.summary,
          keyPoints: $0.keyPoints, guidance: $0.guidance, caveats: $0.caveats)
      }
    }

    var seen: Set<String> = []
    var terms: [String] = []
    for term in notes.flatMap(\.terms) {
      let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
      terms.append(trimmed)
    }

    return OrganizedDocument(
      title: outline?.title.isEmpty == false ? outline!.title : (notes.first?.topic ?? "Transcription"),
      overview: outline?.overview ?? "",
      sections: sections,
      termIndex: terms.sorted { $0.lowercased() < $1.lowercased() })
  }
}
