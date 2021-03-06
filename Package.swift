// swift-tools-version:4.0
//
//  Package.swift
//  GPIR
//
//  Copyright 2016-2018 The DLVM Team.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import PackageDescription

let package = Package(
    name: "GPIR",
    products: [
        .library(name: "GPIR", type: .dynamic,
                 targets: ["GPIR", "GPParse"]),
        .library(name: "GPIRCore", type: .static,
                 targets: ["GPIR"]),
        .library(name: "GPParse", type: .static,
                 targets: ["GPParse"]),
        .library(name: "GPCommandLineTools", type: .static,
                 targets: ["GPCommandLineTools"]),
        .executable(name: "gpir-opt",
                    targets: ["gpir-opt"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-package-manager",
                 .branch("swift-4.1-branch")),
        .package(url: "https://github.com/dlvm-team/CoreTensor", from: "0.7.2")
    ],
    targets: [
        .target(name: "GPIR", dependencies: ["CoreTensor"]),
        .target(name: "GPParse", dependencies: ["GPIR"]),
        .target(name: "GPCommandLineTools", dependencies: [
            "Utility", "GPIR", "GPParse"
        ]),
        .target(name: "gpir-opt", dependencies: [
            "GPIR", "GPParse", "GPCommandLineTools"
        ]),
        .testTarget(name: "GPIRTests", dependencies: ["GPIR"]),
        .testTarget(name: "GPParseTests", dependencies: [
            "GPIR", "GPParse"
        ]),
    ],
    swiftLanguageVersions: [4]
)
