// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BudgetTracer",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "BudgetCore", targets: ["BudgetCore"]),
        .library(name: "BudgetPersistence", targets: ["BudgetPersistence"]),
        .library(name: "BudgetPlaid", targets: ["BudgetPlaid"]),
        .library(name: "BudgetTracerSharedUI", targets: ["BudgetTracerSharedUI"]),
        .executable(name: "BudgetTracerMac", targets: ["BudgetTracerMac"])
    ],
    dependencies: [
        .package(url: "https://github.com/plaid/plaid-link-ios-spm.git", from: "7.0.0")
    ],
    targets: [
        .target(name: "BudgetCore"),
        .target(
            name: "BudgetPersistence",
            dependencies: ["BudgetCore"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(
            name: "BudgetPlaid",
            dependencies: ["BudgetCore", "BudgetPersistence"]
        ),
        .executableTarget(
            name: "BudgetTracerBackend",
            dependencies: ["BudgetCore", "BudgetPersistence", "BudgetPlaid"]
        ),
        .target(
            name: "BudgetTracerSharedUI",
            dependencies: [
                "BudgetCore",
                .product(name: "LinkKit", package: "plaid-link-ios-spm", condition: .when(platforms: [.iOS]))
            ]
        ),
        .executableTarget(
            name: "BudgetTracerMac",
            dependencies: ["BudgetCore", "BudgetTracerSharedUI"]
        ),
        .testTarget(
            name: "BudgetCoreTests",
            dependencies: ["BudgetCore", "BudgetPersistence", "BudgetPlaid"]
        ),
        .testTarget(
            name: "BudgetTracerSharedUITests",
            dependencies: ["BudgetCore", "BudgetTracerSharedUI"]
        )
    ],
    swiftLanguageVersions: [.v5]
)
