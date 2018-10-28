//
//  Options.swift
//  GPCommandLineTools
//
//  Copyright 2018 The GPIR Team.
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

import struct Basic.AbsolutePath
import struct GPIR.OrderedSet

open class ToolOptions {
    /// Input files
    public var inputFiles: [AbsolutePath] = []
    /// Output paths
    public var outputPaths: [AbsolutePath]?
    /// Transformation passes
    public var passes: OrderedSet<TransformPass>?
    /// Print IR
    public var shouldPrintIR = true

    public required init() {}
}
