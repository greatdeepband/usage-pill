import Foundation
import Testing
@testable import UsageCore

@discardableResult
private func runSecurity(_ args: [String]) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    p.arguments = args; p.standardOutput = Pipe(); p.standardError = Pipe()
    try? p.run(); p.waitUntilExit(); return p.terminationStatus
}
private func loginKeychainWritable() -> Bool {
    let s = "usage-pill-probe-\(UUID().uuidString)"
    defer { runSecurity(["delete-generic-password", "-s", s]) }
    return runSecurity(["add-generic-password", "-s", s, "-a", "t", "-w", "x", "-U"]) == 0
}

@Test(.enabled(if: loginKeychainWritable()))
func readsAppOwnedItemViaSecurityTool() throws {
    let service = "usage-pill-test-\(UUID().uuidString)"
    let blob = #"{"claudeAiOauth":{"accessToken":"sk-test-12345","expiresAt":99999999999999}}"#
    #expect(runSecurity(["add-generic-password", "-s", service, "-a", "t", "-w", blob, "-U"]) == 0)
    defer { runSecurity(["delete-generic-password", "-s", service]) }
    let data = try SecurityToolReader().read(service: service)
    #expect(String(data: data, encoding: .utf8) == blob)
    #expect(try CredentialsParser.parse(data).accessToken == "sk-test-12345")
}

// Hex path: a non-ASCII secret comes back hex-encoded from `-w`; the reader must
// dehex so it parses (verified live: `é` blob → 7b226b…).
@Test(.enabled(if: loginKeychainWritable()))
func dehexesNonAsciiSecret() throws {
    let service = "usage-pill-hex-\(UUID().uuidString)"
    let blob = #"{"claudeAiOauth":{"accessToken":"sk-café-99"}}"#   // contains é (0xC3 0xA9)
    #expect(runSecurity(["add-generic-password", "-s", service, "-a", "t", "-w", blob, "-U"]) == 0)
    defer { runSecurity(["delete-generic-password", "-s", service]) }
    let data = try SecurityToolReader().read(service: service)
    #expect(String(data: data, encoding: .utf8) == blob)            // round-trips through dehex
    #expect(try CredentialsParser.parse(data).accessToken == "sk-café-99")
}

@Test func absentServiceThrowsNotFound() {
    #expect(throws: KeychainReadError.notFound) {
        try SecurityToolReader().read(service: "usage-pill-absent-\(UUID().uuidString)")
    }
}
@Test func badToolPathThrowsSpawnFailed() {
    #expect(throws: KeychainReadError.spawnFailed) {
        try SecurityToolReader(toolPath: "/nonexistent/security").read(service: "x")
    }
}
// Timeout is bounded and fast — point the reader at a hanging command via injected args.
@Test func hangingToolTimesOutFast() {
    let start = Date()
    let reader = SecurityToolReader(toolPath: "/bin/sleep", timeout: 0.3, killGrace: 0.2,
                                    arguments: { _ in ["10"] })
    #expect(throws: KeychainReadError.timedOut) { try reader.read(service: "x") }
    #expect(Date().timeIntervalSince(start) < 2.0)   // returned well before sleep 10
}
// Non-44 failure maps to .toolFailed (point at `false`, which exits 1).
@Test func nonNotFoundExitMapsToToolFailed() {
    let reader = SecurityToolReader(toolPath: "/usr/bin/false", arguments: { _ in [] })
    #expect(throws: KeychainReadError.toolFailed(1)) { try reader.read(service: "x") }
}
// Output with no trailing newline is returned intact (echo -n).
@Test func noTrailingNewlineReturnedIntact() throws {
    let reader = SecurityToolReader(toolPath: "/bin/echo", arguments: { _ in ["-n", "raw"] })
    #expect(String(data: try reader.read(service: "x"), encoding: .utf8) == "raw")
}
// Hardening: the production argv carries -w (output) and NEVER -g (which would
// route the secret to stderr). Pure construction assertion.
@Test func productionArgvUsesDashWNotDashG() {
    let args = SecurityToolReader.defaultArguments("Claude Code-credentials")
    #expect(args == ["find-generic-password", "-s", "Claude Code-credentials", "-w"])
    #expect(!args.contains("-g"))
}
