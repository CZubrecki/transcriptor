import AVFoundation
import Foundation
import FoundationModels

/// What the machine running the tests can actually do.
///
/// Hosted CI runners have no Apple Intelligence and no usable speech synthesis
/// session. Synthesis there never invokes its buffer callback rather than
/// failing, so tests that depend on it must be skipped rather than attempted.
enum Capability {
  static let isCI = ProcessInfo.processInfo.environment["CI"] != nil

  static let speechSynthesis = !isCI && AVSpeechSynthesisVoice(language: "en-US") != nil

  static var foundationModels: Bool {
    guard !isCI else { return false }
    if case .available = SystemLanguageModel.default.availability { return true }
    return false
  }
}
