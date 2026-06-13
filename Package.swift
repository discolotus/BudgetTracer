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
        .library(name: "BudgetSecureLocal", targets: ["BudgetSecureLocal"]),
        .library(name: "BudgetTracerSharedUI", targets: ["BudgetTracerSharedUI"]),
        .executable(name: "BudgetTracerMac", targets: ["BudgetTracerMac"])
    ],
    dependencies: [
        .package(url: "https://github.com/plaid/plaid-link-ios-spm.git", from: "7.0.0"),
        .package(url: "https://github.com/sqlcipher/SQLCipher.swift.git", exact: "4.16.0")
    ],
    targets: [
        .target(name: "BudgetCore"),
        .target(
            name: "BudgetPersistence",
            dependencies: [
                "BudgetCore",
                .product(name: "SQLCipher", package: "SQLCipher.swift")
            ],
            cSettings: [.define("SQLITE_HAS_CODEC", to: "1")],
            linkerSettings: [
                .linkedFramework("Security"),
                .linkedFramework("Foundation")
            ]
        ),
        .target(
            name: "BudgetPlaid",
            dependencies: ["BudgetCore", "BudgetPersistence"]
        ),
        .target(
            name: "BudgetSecureLocal",
            dependencies: ["BudgetCore", "BudgetPersistence", "BudgetPlaid"]
        ),
        .executableTarget(
            name: "BudgetTracerBackend",
            dependencies: ["BudgetCore", "BudgetPersistence", "BudgetPlaid"]
        ),
        .target(
            name: "BudgetTracerSharedUI",
            dependencies: [
                "BudgetCore",
                "BudgetSecureLocal",
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
        ),
        .testTarget(
            name: "BudgetSecureLocalTests",
            dependencies: ["BudgetCore", "BudgetPersistence", "BudgetPlaid", "BudgetSecureLocal"]
        ),
        .testTarget(
            name: "BudgetTracerBackendTests",
            dependencies: ["BudgetTracerBackend"]
        )
    ],
    swiftLanguageVersions: [.v5]
)
