import Foundation

// MARK: - CLIResult

struct CLIResult {
  let standardOutput: String
  let standardError: String
  let exitCode: Int32
}

// MARK: - CLIRunnerError

/// Drives the built `transcriptor` executable as a subprocess.
///
/// `Workspace` is rooted at the process's current directory, so running the
/// binary from a temporary directory keeps each case hermetic.
enum CLIRunnerError: Error {
  case executableNotFound(URL)
}

// MARK: - BundleLocator

/// `Bundle.main` is the SwiftPM test helper rather than the test bundle, so the
/// products directory has to be resolved through a type in this module.
private final class BundleLocator { }

// MARK: - CLIRunner

enum CLIRunner {
  static var executable: URL {
    Bundle(for: BundleLocator.self)
      .bundleURL
      .deletingLastPathComponent()
      .appending(path: "transcriptor")
  }

  static func run(_ arguments: [String], in directory: URL) throws -> CLIResult {
    let executable = executable
    guard FileManager.default.isExecutableFile(atPath: executable.path) else {
      throw CLIRunnerError.executableNotFound(executable)
    }

    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.currentDirectoryURL = directory

    let output = Pipe()
    let error = Pipe()
    process.standardOutput = output
    process.standardError = error

    try process.run()
    let outputData = output.fileHandleForReading.readDataToEndOfFile()
    let errorData = error.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    return CLIResult(
      standardOutput: String(decoding: outputData, as: UTF8.self),
      standardError: String(decoding: errorData, as: UTF8.self),
      exitCode: process.terminationStatus,
    )
  }
}

// MARK: - TemporaryWorkspace

/// A throwaway directory the CLI can treat as its workspace root.
struct TemporaryWorkspace {
  init(withVideosDirectory: Bool) throws {
    root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    if withVideosDirectory {
      try FileManager.default.createDirectory(at: root.appending(path: "videos"), withIntermediateDirectories: true)
    }
  }

  let root: URL

  func remove() {
    try? FileManager.default.removeItem(at: root)
  }
}
