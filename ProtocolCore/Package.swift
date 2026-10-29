// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "PlaneProtocol", products: [.library(name: "PlaneProtocol", targets: ["PlaneProtocol"])], targets: [.target(name: "PlaneProtocol"), .testTarget(name: "PlaneProtocolTests", dependencies: ["PlaneProtocol"])])
