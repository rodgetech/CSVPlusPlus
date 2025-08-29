// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CSVPlusPlus",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/dehesa/CodableCSV.git", from: "0.6.7")
    ],
    targets: [
        .target(
            name: "CSVPlusPlus",
            dependencies: ["CodableCSV"]
        )
    ]
)