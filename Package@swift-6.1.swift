// swift-tools-version: 6.1

import PackageDescription

let package = Package(name: "Alamofire",
                      platforms: [.macOS(.v10_13),
                                  .iOS(.v17),
                                  .tvOS(.v12),
                                  .watchOS(.v4)],
                      products: [
                          .library(name: "Alamofire", targets: ["Alamofire"]),
                          .library(name: "AlamofireDynamic", type: .dynamic, targets: ["Alamofire"])
                      ],
                      targets: [.target(name: "Alamofire",
                                        path: "Source",
                                        exclude: ["Info.plist"],
                                        resources: [.process("PrivacyInfo.xcprivacy")],
                                        swiftSettings: [.enableUpcomingFeature("ExistentialAny")],
                                        linkerSettings: [.linkedFramework("CFNetwork",
                                                                          .when(platforms: [.iOS,
                                                                                            .macOS,
                                                                                            .tvOS,
                                                                                            .watchOS]))])],
                      swiftLanguageModes: [.v5])
