//
//  TransformUtilities.swift
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

// FIXME(dan-zheng): Nuke definedNames.

// MARK: - Fresh name generators
fileprivate extension BasicBlock {
    var definedNames: Set<String> {
        return Set(name.flatMap { [$0] } ?? [])
            .union(arguments.compactMap { $0.name })
            .union(elements.compactMap { $0.name })
    }
}

fileprivate extension Function {
    var definedNames: Set<String> {
        return Set(elements.flatMap { $0.definedNames })
    }
}

internal extension Module {
    func makeFreshFunctionName(_ name: String) -> String {
        var result = name
        var count = 0
        while elements.map({ $0.name }).contains(result) {
            result = "\(name)_\(count)"
            count += 1
        }
        return result
    }
}

internal extension Function {
    func makeFreshName(_ name: String) -> String {
        var result = name
        var count = 0
        while definedNames.contains(result) {
            result = "\(name)_\(count)"
            count += 1
        }
        return result
    }

    func makeFreshBasicBlockName(_ name: String) -> String {
        var result = name
        var count = 0
        while elements.contains(where: { $0.name == result }) {
            result = "\(name)_\(count)"
            count += 1
        }
        return result
    }
}

internal extension BasicBlock {
    func makeFreshName(_ name: String) -> String {
        return parent.makeFreshName(name)
    }

    func makeFreshBasicBlockName(_ name: String) -> String {
        return parent.makeFreshBasicBlockName(name)
    }
}

// MARK: - Basic block related utilities
internal extension Argument {
    func incomingValue(from bb: BasicBlock) -> Use {
        guard let index = parent.arguments.index(of: self) else {
            DLImpossible(
                "\(self) is not an argument of its parent '\(bb.printedName).")
        }
        let terminator = bb.premise.terminator
        switch terminator.kind {
        case .branch(parent, let args),
             .conditional(_, parent, let args, _, _),
             .conditional(_, _, _, parent, let args):
            return args[index]
        case .branchEnum(let enumCase, _):
            // FIXME: should not return enum directly but rather the
            // corresponding associated value
            return enumCase
        default:
            preconditionFailure("""
                Basic block '\(bb.printedName) does not branch to argument \
                parent '\(parent.printedName).
                """)
        }
    }
}

// MARK: - Function cloning
internal extension Function {
    /// Create clone of function
    func makeClone(named name: String) -> Function {
        let newFunc = Function(name: name,
                               argumentTypes: argumentTypes,
                               returnType: returnType,
                               attributes: attributes,
                               declarationKind: declarationKind,
                               parent: parent)
        copyContents(to: newFunc)
        return newFunc
    }

    /// Copy basic blocks to an empty function
    func copyContents(to other: Function) {
        /// Other function must be empty (has no basic blocks)
        guard other.isEmpty else {
            fatalError("""
                Could not copy contents to @\(other.printedName) because it is \
                not empty.
                """)
        }

        /// Mappings from old IR units to new IR units
        var newArgs: [Argument : Argument] = [:]
        var newBlocks: [BasicBlock : BasicBlock] = [:]
        var newInsts: [Instruction : Instruction] = [:]

        func newUse(from old: Use) -> Use {
            switch old {
            /// If recursion, replace function with new function
            case .definition(.function(self)):
                return %other
            case .definition(.function), .definition(.variable):
                return old
            case let .literal(ty, lit) where lit.isAggregate:
                return .literal(
                    ty, lit.substituting(newUse(from: old), for: old))
            case let .literal(ty, lit):
                return .literal(ty, lit)
            case let .definition(.argument(arg)):
                return %newArgs[arg]!
            case let .definition(.instruction(inst)):
                return %newInsts[inst]!
            }
        }

        /// Clone basic blocks
        for oldBB in self {
            let newBB = BasicBlock(
                name: oldBB.name,
                arguments: oldBB.arguments.map{($0.name, $0.type)},
                parent: other)
            other.append(newBB)
            /// Insert arguments into mapping
            for (oldArg, newArg) in zip(oldBB.arguments, newBB.arguments) {
                newArgs[oldArg] = newArg
            }
            newBlocks[oldBB] = newBB
        }
        /// Clone instructions
        for oldBB in self {
            let newBB = newBlocks[oldBB]!
            for oldInst in oldBB {
                let newInst = Instruction(name: oldInst.name,
                                          kind: oldInst.kind, parent: newBB)
                /// Replace operands with new uses
                for oldUse in newInst.operands {
                    newInst.substitute(newUse(from: oldUse), for: oldUse)
                }
                /// If instruction branches, replace old BBs with new BBs
                switch newInst.kind {
                case let .branch(dest, args):
                    newInst.kind = .branch(newBlocks[dest]!, args)
                case let .conditional(cond, thenBB, thenArgs, elseBB, elseArgs):
                    newInst.kind = .conditional(
                        cond, newBlocks[thenBB]!, thenArgs,
                        newBlocks[elseBB]!, elseArgs)
                default: break
                }
                /// Insert instruction into mapping and new BB
                newInsts[oldInst] = newInst
                newBB.append(newInst)
            }
        }
    }
}

internal extension BasicBlock {
    /// Creates a new basic block that unconditionally branches to self and
    /// hoists some predecessors to the new block. Also, updates the CFG
    /// accordingly.
    @discardableResult
    func hoistPredecessorsToNewBlock<C : Collection>(
        named name: String?,
        hoisting predecessors: C,
        at index: Int? = nil,
        controlFlow cfg: inout DirectedGraph<BasicBlock>) -> BasicBlock
        where C.Element == BasicBlock
    {
        let newBB = BasicBlock(
            name: name.map(makeFreshName),
            arguments: arguments.map { (nil, $0.type) },
            parent: parent)
        if let index = index {
            parent.insert(newBB, at: index)
        } else {
            parent.append(newBB)
        }
        let builder = IRBuilder(basicBlock: newBB)
        builder.branch(self, newBB.arguments.map(%))
        cfg.insertEdge(from: newBB, to: self)
        /// Change all predecessors to branch to new block.
        predecessors.forEach { pred in
            pred.premise.terminator.substituteBranches(to: self, with: newBB)
            cfg.removeEdge(from: pred, to: self)
            cfg.insertEdge(from: pred, to: newBB)
        }
        return newBB
    }

    @discardableResult
    func hoistPredecessorsToNewBlock<C : Collection>(
        named name: String?,
        hoisting predecessors: C,
        before other: BasicBlock,
        controlFlow cfg: inout DirectedGraph<BasicBlock>) -> BasicBlock
        where C.Element == BasicBlock
    {
        guard let index = parent.index(of: other) else {
            preconditionFailure("""
                Function @\(parent.printedName) does not contain basic block \
                '\(other.printedName).
                """)
        }
        return hoistPredecessorsToNewBlock(named: name, hoisting: predecessors,
                                           at: index, controlFlow: &cfg)
    }

    @discardableResult
    func hoistPredecessorsToNewBlock<C : Collection>(
        named name: String?,
        hoisting predecessors: C,
        after other: BasicBlock,
        controlFlow cfg: inout DirectedGraph<BasicBlock>) -> BasicBlock
        where C.Element == BasicBlock
    {
        guard let prevIndex = parent.index(of: other) else {
            preconditionFailure("""
                Function @\(parent) does not contain basic block '\(other).
                """)
        }
        return hoistPredecessorsToNewBlock(named: name, hoisting: predecessors,
                                           at: prevIndex + 1, controlFlow: &cfg)
    }
}
