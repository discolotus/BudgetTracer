import XCTest

final class MacAppShellParityTests: XCTestCase {
    func testXcodeAndSwiftPMMacAppShellsStayInSync() throws {
        let root = try repositoryRoot()
        let xcodeShell = root.appendingPathComponent("Apps/BudgetTracerMac/App/BudgetTracerMacApp.swift")
        let swiftPMShell = root.appendingPathComponent("Sources/BudgetTracerMac/App/BudgetTracerMacApp.swift")

        XCTAssertEqual(
            try normalizedContents(of: xcodeShell),
            try normalizedContents(of: swiftPMShell),
            "Keep the Xcode and SwiftPM macOS app shells identical. Move shared behavior into BudgetTracerSharedUI instead of changing only one shell."
        )
    }

    private func normalizedContents(of url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
            .replacingOccurrences(of: "\r\n", with: "\n")
    }

    private func repositoryRoot() throws -> URL {
        var current = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fileManager = FileManager.default

        while current.path != current.deletingLastPathComponent().path {
            let packagePath = current.appendingPathComponent("Package.swift").path
            let projectPath = current.appendingPathComponent("project.yml").path
            if fileManager.fileExists(atPath: packagePath), fileManager.fileExists(atPath: projectPath) {
                return current
            }

            current.deleteLastPathComponent()
        }

        throw NSError(
            domain: "BudgetTracerTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate BudgetTracer repository root."]
        )
    }
}
