// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "ContactsKit",
    platforms: [.iOS(.v12)],
    products: [
        .library(
            name: "ContactsKit",
            targets: ["ContactsKit"]
        ),
    ],
    dependencies: [
        // no dependencies
    ],
    targets: [
        .target(
            name: "ContactsKit",
            dependencies: [],
            resources: []
        ),
    ]
)
