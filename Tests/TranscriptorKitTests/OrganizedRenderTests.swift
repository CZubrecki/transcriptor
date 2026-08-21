import Testing
@testable import TranscriptorKit

private let technical = OrganizedDocument(
  title: "Glass Effects",
  overview: "How glass works.",
  sections: [.init(
    title: "Basics",
    summary: "The modifier.",
    keyPoints: ["Apply to a view."],
    guidance: ["Group related views."],
    caveats: ["iOS 26 or later."],
  )],
  termIndex: ["GlassEffectContainer", "SwiftUI"],
)

private let plain = OrganizedDocument(
  title: "A Lecture",
  overview: "About a topic.",
  sections: [.init(
    title: "Opening",
    summary: "The premise.",
    keyPoints: ["A single point."],
    guidance: [],
    caveats: [],
  )],
  termIndex: [],
)

@Test
func `renders every populated section`() {
  let md = MarkdownRenderer.organized(technical)
  #expect(md.contains("# Glass Effects"))
  #expect(md.contains("How glass works."))
  #expect(md.contains("## Basics"))
  #expect(md.contains("- Apply to a view."))
  #expect(md.contains("### Guidance"))
  #expect(md.contains("### Caveats"))
  #expect(md.contains("GlassEffectContainer"))
}

@Test
func `omits empty sections entirely`() {
  let md = MarkdownRenderer.organized(plain)
  #expect(md.contains("## Opening"))
  #expect(!md.contains("### Guidance"))
  #expect(!md.contains("### Caveats"))
  #expect(!md.contains("## Terms"))
}

@Test
func `omits overview when absent`() {
  var doc = plain
  doc.overview = ""
  let md = MarkdownRenderer.organized(doc)
  #expect(md.contains("# A Lecture"))
  #expect(!md.contains("## Overview"))
}

@Test
func `no heading is immediately followed by another heading`() {
  let md = MarkdownRenderer.organized(plain)
  let lines = md.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
  let headingFollowedByHeading = zip(lines, lines.dropFirst())
    .contains { $0.hasPrefix("#") && $1.hasPrefix("###") }
  #expect(headingFollowedByHeading == false)
}
