import Foundation

// MARK: - MarkdownRenderer

public enum MarkdownRenderer {
  public static func timestamp(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite else { return "00:00" }
    let total = Int(max(0, seconds).rounded(.down))
    return String(format: "%02d:%02d", total / 60, total % 60)
  }

  public static func fullTranscript(
    segments: [TranscriptSegment],
    sourcePath: String,
    duration: TimeInterval,
    locale: String,
    date: Date,
  ) -> String {
    var lines = [String]()
    lines.append("---")
    lines.append("source: \(sourcePath)")
    lines.append("duration: \(timestamp(duration))")
    lines.append("locale: \(locale)")
    lines.append("transcribed: \(ISO8601DateFormatter().string(from: date))")
    lines.append("---")
    lines.append("")
    lines.append("# Full Transcription")
    lines.append("")
    for segment in segments {
      let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { continue }
      lines.append("[\(timestamp(segment.start))] \(text)")
      lines.append("")
    }
    return lines.joined(separator: "\n")
  }
}

extension MarkdownRenderer {

  // MARK: Public

  public static func organized(_ document: OrganizedDocument) -> String {
    var lines: [String] = ["# \(document.title)", ""]

    if !document.overview.isEmpty {
      lines.append(contentsOf: ["## Overview", "", document.overview, ""])
    }

    for section in document.sections {
      lines.append("## \(section.title)")
      lines.append("")
      if !section.summary.isEmpty {
        lines.append(contentsOf: [section.summary, ""])
      }
      appendList(&lines, heading: nil, items: section.keyPoints)
      appendList(&lines, heading: "### Guidance", items: section.guidance)
      appendList(&lines, heading: "### Caveats", items: section.caveats)
    }

    if !document.termIndex.isEmpty {
      appendList(&lines, heading: "## Terms (as spoken; identifier casing is unreliable)", items: document.termIndex)
    }

    return lines.joined(separator: "\n")
  }

  // MARK: Private

  private static func appendList(_ lines: inout [String], heading: String?, items: [String]) {
    guard !items.isEmpty else { return }
    if let heading { lines.append(contentsOf: [heading, ""]) }
    for item in items { lines.append("- \(item)") }
    lines.append("")
  }
}
