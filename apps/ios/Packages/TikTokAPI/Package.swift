// swift-tools-version: 6.0
import PackageDescription

// Client de l'API généré depuis apps/api/openapi.json (ADR-005), à chaque build, par swift-openapi-generator.
// Le code généré n'est jamais versionné. Versions figées ici, et avec leurs dépendances transitives dans le
// Package.resolved versionné du projet (ADR-034).
let package = Package(
    name: "TikTokAPI",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "TikTokAPI", targets: ["TikTokAPI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-generator", exact: "1.13.1"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", exact: "1.12.1"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", exact: "1.3.1"),
    ],
    targets: [
        .target(
            name: "TikTokAPI",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
            ],
            plugins: [.plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")]
        ),
    ]
)
