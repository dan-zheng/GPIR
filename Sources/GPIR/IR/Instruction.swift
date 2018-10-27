//
//  Instruction.swift
//  GPIR
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

// MARK: - Core Instruction Set
public enum InstructionKind {
    /** Builtin intrinsic **/
    case builtin(Intrinsic.Type, [Use])

    /** Control flow **/
    /// Unconditional branch to a basic block
    case branch(BasicBlock, [Use])
    /// Conditional branch based on a boolean value
    case conditional(Use, BasicBlock, [Use], BasicBlock, [Use])
    /// Conditional branch based on enum case
    case branchEnum(Use, [(caseName: String, basicBlock: BasicBlock)])
    /// Return
    case `return`(Use?)

    /** Literal constructor **/
    case literal(Literal, Type)

    /** Operations **/
    /*
    /// Elementwise numeric unary operation (map)
    case numericUnary(NumericUnaryOp, Use)
    /// Elementwise numeric binary operation (zipWith)
    case numericBinary(NumericBinaryOp, Use, Use)
     */
    /// Elementwise binary boolean operation
    case booleanBinary(BooleanBinaryOp, Use, Use)
    /// Negation
    case not(Use)

    /** Aggregate operations **/
    /// Extract an element from a tuple or array
    case extract(from: Use, at: [ElementKey])
    /// Insert an element to a tuple or array
    case insert(Use, to: Use, at: [ElementKey])

    /** Function application **/
    case apply(Use, [Use])

    /** Memory **/
    /// Load value from pointer on the host
    case load(Use)
    /// Store value to pointer on the host
    case store(Use, to: Use)
    /// Memory copy
    case copy(from: Use, to: Use, count: Use)
    /// GEP (without leading index)
    case elementPointer(Use, [ElementKey])
    /// Trap
    case trap
}

public final class Instruction : IRUnit, NamedValue {
    public typealias Parent = BasicBlock
    public var name: String?
    public var kind: InstructionKind
    public var parent: BasicBlock

    public init(name: String? = nil, kind: InstructionKind, parent: BasicBlock) {
        self.name = name
        self.kind = kind
        self.parent = parent
    }
}

extension Instruction : Value {
    public var type: Type {
        return kind.type
    }

    public var opcode: Opcode {
        return kind.opcode
    }

    public func makeUse() -> Use {
        return .definition(.instruction(self))
    }
}

// MARK: - Predicates
public extension InstructionKind {
    /// Returns true iff the instruction is a terminator:
    /// `branch`, `branchEnum`, `conditional` or `return`
    var isTerminator: Bool {
        switch self {
        case .branch, .branchEnum, .conditional, .return:
            return true
        default:
            return false
        }
    }

    /// Returns true iff the instruction is a `return`
    var isReturn: Bool {
        switch self {
        case .return: return true
        default: return false
        }
    }

    /// Returns true iff the instruction is a `trap`
    var isTrap: Bool {
        switch self {
        case .trap: return true
        default: return false
        }
    }
}

// MARK: - Type inference

public extension InstructionKind {
    /// Infers and returns the type of the result of the instruction
    var type: Type {
        switch self {
        case let .builtin(op, args):
            return op.resultType(for: args)

        case let .literal(_, ty):
            return ty

        case .booleanBinary, .not:
            return .bool

        case let .apply(f, vv):
            switch f.type.unaliased {
            case let .pointer(.function(actual, ret)),
                 let .function(actual, ret):
                guard actual == vv.map({$0.type}) else { return .invalid }
                return ret
            default:
                return .invalid
            }

        case let .extract(from: v, at: indices):
            return v.type.elementType(at: indices) ?? .invalid

        case let .insert(src, to: dest, at: indices):
            guard let elementType = dest.type.elementType(at: indices), elementType == src.type else {
                return .invalid
            }
            return dest.type

        case let .load(v):
            guard case let .pointer(t) = v.type.unaliased else { return .invalid }
            return t

        case let .elementPointer(v, ii):
            guard case let .pointer(t) = v.type else { return .invalid }
            return t.elementType(at: ii).flatMap(Type.pointer) ?? .invalid

        case .branch, .conditional, .return, .branchEnum, .store, .copy, .trap:
            return .void
        }
    }
}

// MARK: - Operands

extension Instruction : User {
    public var operands: [Use] {
        return kind.operands
    }
}

extension InstructionKind {
    public var operands: [Use] {
        switch self {
        case let .booleanBinary(_, op1, op2),
             let .insert(op1, to: op2, at: _),
             let .store(op1, op2):
            return [op1, op2]
        case
             let .return(op?), let .branchEnum(op, _), let .not(op),
             let .extract(from: op, at: _), let .load(op),
             let .elementPointer(op, _):
            return [op]
        case let .copy(src, dest, count):
            return [src, dest, count]
        case .builtin(_, let ops),
             .branch(_, let ops):
            return ops
        case let .conditional(cond, _, thenArgs, _, elseArgs):
            return [cond] + thenArgs + elseArgs
        case let .apply(f, args):
            return [f] + args
        case let .literal(lit, _):
            return lit.operands
        case .return(nil), .trap:
            return []
        }
    }
}

public extension Literal {
    var operands: [Use] {
        func literalOperands(in use: Use) -> [Use] {
            switch use {
            case let .literal(_, lit):
                return lit.operands
            default:
                return [use]
            }
        }
        switch self {
        case let .tuple(ops):
            return ops.flatMap(literalOperands(in:))
        case let .struct(fields):
            return fields.map{$1}.flatMap(literalOperands(in:))
        case let .enumCase(values):
            return values.1.flatMap(literalOperands(in:))
        default:
            return []
        }
    }
}

// MARK: - Naming

public extension Instruction {
    var printedName: String? {
        return name ??
            (type.isVoid ? nil : "\(parent.indexInParent).\(indexInParent)")
    }
}

// MARK: - Equality

extension InstructionKind : Equatable {
    public static func == (lhs: InstructionKind, rhs: InstructionKind) -> Bool {
        switch (lhs, rhs) {
        case let (.builtin(op1, args1), .builtin(op2, args2)):
            return op1 == op2 && args1 == args2
        case let (.literal(x1, t1), .literal(x2, t2)):
            return x1 == x2 && t1 == t2
        case let (.booleanBinary(op1, x1, x2), .booleanBinary(op2, y1, y2)):
            return op1 == op2 && x1 == y1 && x2 == y2
        case let (.not(x1), .not(x2)):
            return x1 == x2
        case let (.apply(f1, args1), .apply(f2, args2)):
            return f1 == f2 && args1 == args2
        case let (.extract(from: v1, at: i1), .extract(from: v2, at: i2)):
            return v1 == v2 && i1 == i2
        case let (.insert(s1, to: d1, at: i1), .insert(s2, to: d2, at: i2)):
            return s1 == s2 && d1 == d2 && i1 == i2
        case let (.branchEnum(e1, b1), .branchEnum(e2, b2)):
            return e1 == e2 && b1 == b2
        case let (.load(x1), .load(x2)):
            return x1 == x2
        case let (.store(x1, to: p1), .store(x2, to: p2)):
            return x1 == x2 && p1 == p2
        case let (.copy(from: f1, to: t1, count: c1), .copy(from: f2, to: t2, count: c2)):
            return f1 == f2 && t1 == t2 && c1 == c2
        case let (.elementPointer(x1, ii1), .elementPointer(x2, ii2)):
            return x1 == x2 && ii1 == ii2
        case let (.branch(bb1, x1), .branch(bb2, x2)):
            return bb1 == bb2 && x1 == x2
        case let (.conditional(c1, t1, ta1, e1, ea1), .conditional(c2, t2, ta2, e2, ea2)):
            return c1 == c2 && t1 == t2 && ta1 == ta2 && e1 == e2 && ea1 == ea2
        case let (.return(x1), .return(x2)):
            return x1 == x2
        case (.trap, .trap):
            return true
        default:
            return false
        }
    }
}

// MARK: - Substitution utilities

public extension Instruction {
    func substitute(_ newUse: Use, for use: Use) {
        kind = kind.substituting(newUse, for: use)
    }

    func substituteBranches(to oldBB: BasicBlock, with newBB: BasicBlock) {
        kind = kind.substitutingBranches(to: oldBB, with: newBB)
    }
}

public extension InstructionKind {
    /// Substitutes a new use for an old use
    /// - Note: The current implementation is a vanilla tedious switch
    /// matching all the permutations (a.k.a. very bad).
    func substituting(_ new: Use, for old: Use) -> InstructionKind {
        let condSubst = {$0 == old ? new : $0}
        switch self {
        case .builtin(let op, let args):
            return .builtin(op, args.map(condSubst))
        case .branch(let dest, let args):
            return .branch(dest, args.map(condSubst))
        case let .conditional(cond, thenBB, thenArgs, elseBB, elseArgs):
            let newCond = cond == old ? new : cond
            return .conditional(newCond,
                                thenBB, thenArgs.map(condSubst),
                                elseBB, elseArgs.map(condSubst))
        case .return(old?):
            return .return(new)
        case .literal(let lit, let ty):
            return .literal(lit.substituting(new, for: old), ty)
        case .booleanBinary(let fun, old, old):
            return .booleanBinary(fun, new, new)
        case .booleanBinary(let fun, old, let use2):
            return .booleanBinary(fun, new, use2)
        case .booleanBinary(let fun, let use1, old):
            return .booleanBinary(fun, use1, new)
        case .not(old):
            return .not(new)
        case let .apply(fn, operands):
            let newFn = fn == old ? new : fn
            return .apply(newFn, operands.map(condSubst))
        case .extract(from: old, at: let i):
            return .extract(from: new, at: i)
        case .insert(old, to: old, at: let indices):
            return .insert(new, to: new, at: indices)
        case .insert(old, to: let use1, at: let indices):
            return .insert(new, to: use1, at: indices)
        case .insert(let use1, to: old, at: let indices):
            return .insert(use1, to: new, at: indices)
        case .branchEnum(let use, let branches):
            let newUse = use == old ? new : use
            return .branchEnum(newUse, branches)
        case .load(old):
            return .load(new)
        case .store(old, to: let dest):
            return .store(new, to: dest)
        case .store(let val, to: old):
            return .store(val, to: new)
        case .copy(from: old, to: old, count: old):
            return .copy(from: new, to: new, count: new)
        case .copy(from: old, to: old, count: let v3):
            return .copy(from: new, to: new, count: v3)
        case .copy(from: old, to: let v2, count: old):
            return .copy(from: new, to: v2, count: new)
        case .copy(from: old, to: let v2, count: let v3):
            return .copy(from: new, to: v2, count: v3)
        case .copy(from: let v1, to: old, count: old):
            return .copy(from: v1, to: new, count: new)
        case .copy(from: let v1, to: old, count: let v3):
            return .copy(from: v1, to: new, count: v3)
        case .copy(from: let v1, to: let v2, count: old):
            return .copy(from: v1, to: v2, count: new)
        case .elementPointer(old, let indices):
            return .elementPointer(new, indices)
        default:
            return self
        }
    }

    /// Substitutes branches to an old basic block with a new basic block
    func substitutingBranches(to old: BasicBlock,
                              with new: BasicBlock) -> InstructionKind {
        switch self {
        case .branch(old, let args):
            return .branch(new, args)
        case .conditional(let cond, old, let thenArgs, old, let elseArgs):
            return .conditional(cond, new, thenArgs, new, elseArgs)
        case .conditional(let cond, let thenBB, let thenArgs, old, let elseArgs):
            return .conditional(cond, thenBB, thenArgs, new, elseArgs)
        case .conditional(let cond, old, let thenArgs, let elseBB, let elseArgs):
            return .conditional(cond, new, thenArgs, elseBB, elseArgs)
        default:
            return self
        }
    }
}

// MARK: - Opcode decomposition

public enum Opcode : Equatable {
    case builtin
    case branch
    case branchEnum
    case conditional
    case `return`
    case literal
    case not
    case booleanBinaryOp(BooleanBinaryOp)
    case extract
    case insert
    case apply
    case load
    case store
    case copy
    case elementPointer
    case trap
}

/// Instruction ADT decomposition (opcodes, keywords, operands).
/// - Note: When adding a new instruction, you should insert its
/// corresponding opcode here.
public extension InstructionKind {
    var opcode: Opcode {
        switch self {
        case .builtin: return .builtin
        case .branch: return .branch
        case .branchEnum: return .branchEnum
        case .conditional: return .conditional
        case .return: return .return
        case .literal: return .literal
        case .booleanBinary(let op, _, _): return .booleanBinaryOp(op)
        case .not: return .not
        case .extract: return .extract
        case .insert: return .insert
        case .apply: return .apply
        case .load: return .load
        case .store: return .store
        case .copy: return .copy
        case .elementPointer: return .elementPointer
        case .trap: return .trap
        }
    }
}
