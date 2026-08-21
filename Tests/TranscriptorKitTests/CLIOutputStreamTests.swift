import Foundation
import Testing

@Test
func `empty workspace reports nothing to do on standard error`() throws {
  let workspace = try TemporaryWorkspace(withVideosDirectory: true)
  defer { workspace.remove() }

  let result = try CLIRunner.run(["--transcribe-only"], in: workspace.root)

  #expect(result.exitCode == 0)
  #expect(result.standardError.contains("Nothing to do"))
  #expect(result.standardOutput.isEmpty)
}

@Test
func `missing videos directory fails on standard error`() throws {
  let workspace = try TemporaryWorkspace(withVideosDirectory: false)
  defer { workspace.remove() }

  let result = try CLIRunner.run(["--transcribe-only"], in: workspace.root)

  #expect(result.exitCode == 1)
  #expect(result.standardError.contains("videos directory not found"))
  #expect(result.standardOutput.isEmpty)
}
