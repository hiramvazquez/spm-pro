// swift-tools-version: 6.2
import PackageDescription

// Proof of PRD-X-02: "lo genérico no causa problemas en la app que adopta el SPM" —
// AppFoundation y CoreNetworking, consumidos JUNTOS por un tercer paquete que solo
// conoce sus tipos públicos, sin imports internos ni `@testable`.
//
// `defaultIsolation(MainActor)`, igual que los dos paquetes que consume: es el modo en
// el que una app SwiftUI real construiría este mismo código.
let swiftSettings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault")
]

let package = Package(
    name: "IntegrationExample",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "IntegrationExample",
            targets: ["IntegrationExample"]
        )
    ],
    dependencies: [
        .package(path: "../../AppFoundation"),
        .package(path: "../../CoreNetworking")
    ],
    targets: [
        .target(
            name: "IntegrationExample",
            dependencies: [
                .product(name: "AppFoundation", package: "AppFoundation"),
                .product(name: "CoreNetworking", package: "CoreNetworking"),
                // Previews only (`ProfilePreview`, guarded by `#if DEBUG` at the call
                // site) — `CoreNetworkingTestSupport`'s own Package.swift documents this
                // exact use ("test targets and previews"). SwiftPM's target-dependency
                // conditions don't support a build-configuration case (only `platforms`/
                // `traits`), so this links into every configuration of THIS example
                // target; an app vendoring the pattern keeps its own `ProfilePreview`
                // (or equivalent) in a target that only debug builds pull in.
                .product(name: "CoreNetworkingTestSupport", package: "CoreNetworking")
            ],
            path: "Sources/IntegrationExample",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "IntegrationExampleTests",
            dependencies: [
                "IntegrationExample",
                .product(name: "CoreNetworkingTestSupport", package: "CoreNetworking")
            ],
            path: "Tests/IntegrationExampleTests",
            swiftSettings: swiftSettings
        )
    ]
)
