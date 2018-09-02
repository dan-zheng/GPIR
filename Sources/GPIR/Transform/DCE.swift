//
//  DCE.swift
//  DLVM
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

/// Dead code elimination (traditional algorithm)
open class DeadCodeElimination : TransformPass {
    public typealias Body = Function

    open class func run(on body: Function) -> Bool {
        var changed = false
        var workList: [Instruction] = []
        var count = 0
        /// Iterate over the original function, only adding instructions to the
        /// worklist if they actually need to be revisited. This avoids having
        /// to pre-init the worklist with the entire function's worth of
        /// instructions.
        for inst in body.instructions where !workList.contains(inst) {
            changed = performDCE(on: inst,
                                 workList: &workList,
                                 count: &count) || changed
        }
        while let inst = workList.popLast() {
            changed = performDCE(on: inst,
                                 workList: &workList,
                                 count: &count) || changed
        }
        /// TODO: Print count when DEBUG
        return changed
    }

    private static func performDCE(on inst: Instruction,
                                   workList: inout [Instruction],
                                   count: inout Int) -> Bool {
        let function = inst.parent.parent
        let module = function.parent
        var dfg = function.analysis(from: DataFlowGraphAnalysis.self)
        let sideEffectInfo = module.analysis(from: SideEffectAnalysis.self)

        /// If instruction is not trivially dead, change nothing
        guard dfg.successors(of: inst).isEmpty,
            sideEffectInfo[inst] == .none,
            !inst.kind.isTerminator else { return false }
        /// Eliminate
        inst.removeFromParent()
        count += 1
        /// Remove instruction and check users
        /// Get new user analysis
        dfg = function.analysis(from: DataFlowGraphAnalysis.self)
        /// For original uses, check if they need to be revisited
        for case let .definition(.instruction(usee)) in inst.operands
            where dfg.successors(of: usee).isEmpty
                && sideEffectInfo[usee] == .none
                && !inst.kind.isTerminator {
            workList.append(usee)
        }
        return true
    }
}
