// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DhakaSky",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DhakaSky",
            path: "Sources/DhakaSky",
            linkerSettings: [
                .linkedFramework("SpriteKit"),
                .linkedFramework("Vision"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("IOKit"),
            ]
        )
    ]
)
