// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SSHFilesViewer",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SSHFilesViewer",
            path: "Sources/SSHFilesViewer",
            // Language logos (devicon, MIT) live in Resources/lang-icons and are
            // copied into the .app's Contents/Resources by build.sh, then loaded
            // via Bundle.main. (Excluded here so SwiftPM doesn't treat the .svg
            // files as unhandled sources.)
            exclude: ["Resources/lang-icons"]
        )
    ],
    // Built with the Swift 6 toolchain but in the Swift 5 language mode: the app
    // shells out to `ssh` and bridges a fair amount of AppKit, and we don't want
    // strict-concurrency noise around Process / FileHandle, which aren't Sendable.
    swiftLanguageModes: [.v5]
)
