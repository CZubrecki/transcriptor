import Foundation
import Testing
@testable import TranscriptorKit

@Test
func `formats timestamps as minutes and seconds`() {
  #expect(MarkdownRenderer.timestamp(0) == "00:00")
  #expect(MarkdownRenderer.timestamp(65) == "01:05")
  #expect(MarkdownRenderer.timestamp(3725) == "62:05")
}

@Test
func `renders frontmatter and timestamped segments`() {
  let segments = [
    TranscriptSegment(text: "Hello there.", start: 0, end: 2),
    TranscriptSegment(text: "Second line.", start: 65, end: 67),
  ]
  let md = MarkdownRenderer.fullTranscript(
    segments: segments,
    sourcePath: "videos/a.mp4",
    duration: 67,
    locale: "en_US",
    date: Date(timeIntervalSince1970: 0),
  )

  #expect(md.hasPrefix("---\n"))
  #expect(md.contains("source: videos/a.mp4"))
  #expect(md.contains("duration: 01:07"))
  #expect(md.contains("locale: en_US"))
  #expect(md.contains("[00:00] Hello there."))
  #expect(md.contains("[01:05] Second line."))
}

@Test
func `trims segment whitespace`() {
  let md = MarkdownRenderer.fullTranscript(
    segments: [TranscriptSegment(text: "  padded  ", start: 0, end: 1)],
    sourcePath: "v.mp4",
    duration: 1,
    locale: "en_US",
    date: Date(timeIntervalSince1970: 0),
  )
  #expect(md.contains("[00:00] padded"))
  #expect(!md.contains("padded  "))
}

@Test
func `timestamp of na N does not crash`() {
  #expect(MarkdownRenderer.timestamp(.nan) == "00:00")
}

@Test
func `timestamp of infinity does not crash`() {
  #expect(MarkdownRenderer.timestamp(.infinity) == "00:00")
}

@Test
func `timestamp of negative does not crash`() {
  #expect(MarkdownRenderer.timestamp(-5) == "00:00")
}

@Test
func `full transcript with na N duration does not crash`() {
  let md = MarkdownRenderer.fullTranscript(
    segments: [TranscriptSegment(text: "Hello.", start: 0, end: 1)],
    sourcePath: "v.mp4",
    duration: .nan,
    locale: "en_US",
    date: Date(timeIntervalSince1970: 0),
  )
  #expect(md.contains("duration: 00:00"))
}
