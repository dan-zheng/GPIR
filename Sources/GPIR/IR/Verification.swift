//
//  Verification.swift
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

public enum VerificationError<Node : Verifiable> : Error {
    case axisOutOfBounds(Int, Use, Node)
    case basicBlockArgumentMismatch([Use], BasicBlock, Node)
    case basicBlockParentMismatch(Function, Node)
    case blockFunctionMismatch(BasicBlock, Node)
    case dataTypeMismatch(Use, Use, Node)
    case dataTypeNotBoolean(Use, Node)
    case dataTypeNotNumeric(Use, Node)
    case declarationCannotHaveBody(Node)
    case definitionNotInBasicBlock(Use, BasicBlock, Node)
    case duplicateStructField(String, Node)
    case duplicateEnumCase(String, Node)
    case functionArgumentMismatch([Use], Type, Node)
    case functionEntryArgumentMismatch(BasicBlock, Node)
    case illegalName(String, Node)
    case instructionParentMismatch(BasicBlock, Node)
    case instructionFunctionMismatch(Function, Node)
    case invalidAllocationSize(Node)
    case invalidCopyOperands(Use, Use, Node)
    case invalidEnumCase(EnumType, String, Node)
    case invalidEnumCaseBranch(EnumType, EnumType.Case, BasicBlock, Node)
    case invalidIndex(Use, Int, Node)
    case invalidIndices(Use, [ElementKey], Node)
    case invalidIntrinsic(Intrinsic.Type, Node)
    case invalidLiteral(Type, Literal, Node)
    case invalidOffset(Use, [ElementKey], Node)
    case invalidType(Node)
    case missingIndices(Use, Node)
    case missingTerminator(Node)
    case multipleExits([BasicBlock], Node)
    case namedVoidValue(Node)
    case nestedLiteralNotInLiteralInstruction(Literal, Node)
    case noDimensions(Use, Node)
    case noEntry(Node)
    case noExit(Node)
    case noOperands(Node)
    case noParent(Node)
    case noReturn(Node)
    case notAFunctionCall(Use, Function, Node)
    case notBool(Use, Node)
    case notConstantExpression(Node)
    case notEnum(Use, Node)
    case notFunction(Use, Node)
    case notPointer(Use, Node)
    case notTuple(Use, Node)
    case redeclared(Node)
    case returnTypeMismatch(Instruction, Node)
    case structFieldNameMismatch(StructType, Use, Node)
    case terminatorNotLast(Node)
    case typeMismatch(Use, Use, Node)
    case unbroadcastableMismatch([Use], Node)
    case unexpectedBasicBlockType(BasicBlock, Node)
    case unexpectedDataType(Use, DataType, Node)
    case unexpectedMemoryType(Use, Node)
    case unexpectedType(Use, Type, Node)
    case useBeforeDef(user: Instruction, usee: Value, Node)
    case useInvalidParent(user: Instruction, usee: Value, Node)
    case useTypeMismatch(Node)
}

public protocol Verifiable {
    func performVerification() throws
}

import struct Foundation.NSRange
import class Foundation.NSRegularExpression
private let identifierPattern = try! NSRegularExpression(pattern: "[a-zA-Z_][a-zA-Z0-9_.]*",
                                                         options: [ .dotMatchesLineSeparators ])

private func verifyIdentifier<Unit : Verifiable>(_ id: String, in unit: Unit) throws {
    guard let _ = identifierPattern.firstMatch(in: id, options: [ .anchored ],
                                               range: NSRange(0..<id.count)) else {
        throw VerificationError.illegalName(id, unit)
    }
}

extension Module : Verifiable {
    private func verify<T: Verifiable & NamedValue>
        (_ declaration: T, namespace: inout Set<String>) throws {
        if let name = declaration.name {
            guard !namespace.contains(name) else {
                throw VerificationError.redeclared(declaration)
            }
            namespace.insert(name)
        }
        try declaration.performVerification()
    }
    
    private func verify<T: Verifiable & NominalType>
        (_ declaration: T, namespace: inout Set<String>) throws {
        guard !namespace.contains(declaration.name) else {
            throw VerificationError.redeclared(declaration)
        }
        namespace.insert(declaration.name)
        try declaration.performVerification()
    }

    public func performVerification() throws {
        try verifyIdentifier(name, in: self)
        /// Verify types and values
        var typeNameSet: Set<String> = []
        try typeAliases.forEach { try self.verify($0, namespace: &typeNameSet) }
        try enums.forEach { try self.verify($0, namespace: &typeNameSet) }
        try structs.forEach { try self.verify($0, namespace: &typeNameSet) }
        var valueNameSet: Set<String> = []
        try elements.forEach { try self.verify($0, namespace: &valueNameSet) }
        try variables.forEach { try self.verify($0, namespace: &valueNameSet) }
    }
}

extension Variable : Verifiable {
    public func performVerification() throws {}
}

extension TypeAlias : Verifiable {
    public func performVerification() throws {
        guard let type = type else { return }
        guard type.canonical.isValid else {
            throw VerificationError.invalidType(self)
        }
    }
}

extension StructType : Verifiable {
    public func performVerification() throws {
        var set: Set<String> = []
        /// Verify struct fields' uniqueness and validity
        for (name, ty) in fields {
            guard !set.contains(name) else {
                throw VerificationError.duplicateStructField(name, self)
            }
            guard ty.isValid else {
                throw VerificationError.invalidType(self)
            }
            set.insert(name)
        }
    }
}

extension EnumType : Verifiable {
    public func performVerification() throws {
        var set: Set<String> = []
        /// Verify enum cases' uniqueness and validity
        for (name, types) in cases {
            guard !set.contains(name) else {
                throw VerificationError.duplicateEnumCase(name, self)
            }
            guard types.forAll({$0.isValid}) else {
                throw VerificationError.invalidType(self)
            }
            set.insert(name)
        }
    }
}

extension LiteralValue : Verifiable {
    private func verifyUse(_ use: Use, _ elementType: Type) throws {
        try use.performVerification()
        guard use.type == elementType else {
            throw VerificationError.unexpectedType(use, elementType, self)
        }
    }

    public func performVerification() throws {
        switch (type.canonical, literal) {

        /* Simple literals */

        /// Anything can be undefined
        case (_, .undefined): break

        /// Boolean literal
        case (.bool, .bool):
            break

        /* Aggregate literals */

        /// Tuple literal
        case let (.tuple(elementTypes), .tuple(elements)) where elementTypes.count == elements.count:
            for (elementType, use) in zip(elementTypes, elements) {
                try verifyUse(use, elementType)
            }

        /// Struct literal
        case let (.struct(structTy), .struct(fields)) where structTy.fields.count == fields.count:
            for ((name: fmlName, type: fmlType), (name, val)) in zip(structTy.fields, fields) {
                guard fmlName == name else {
                    throw VerificationError.structFieldNameMismatch(structTy, val, self)
                }
                try verifyUse(val, fmlType)
            }

        /// Enum literal
        case let (.enum(enumTy), .enumCase(name, uses)):
            guard let enumCase = enumTy.cases.first(where: { $0.name == name }) else {
                throw VerificationError.invalidEnumCase(enumTy, name, self)
            }
            for (use, type) in zip(uses, enumCase.associatedTypes) {
                try verifyUse(use, type)
            }

        default:
            throw VerificationError.invalidLiteral(type, literal, self)
        }
    }
}

extension Function : Verifiable {
    public func performVerification() throws {
        if let name = name {
            try verifyIdentifier(name, in: self)
        }

        /// Verify declaration
        if let declarationKind = declarationKind {
            /// Declarations cannot have body
            guard isEmpty else {
                throw VerificationError.declarationCannotHaveBody(self)
            }
            switch declarationKind {
            case .external:
                break
            }
            /// Skip all CFG/DFG verifications because it's a declaration!
            return
        }

        let domTree = analysis(from: DominanceAnalysis.self)
        var bbNames: Set<String> = []

        /// Verify basic blocks
        for bb in self {
            /// Check for redeclaration/redefinition
            if let name = bb.name {
                guard !bbNames.contains(name) else {
                    throw VerificationError.redeclared(bb)
                }
                bbNames.insert(name)
            }
            /// Check entry block arguments
            guard !bb.isEntry || bb.arguments.map({ $0.type }).elementsEqual(argumentTypes) else {
                throw VerificationError.functionEntryArgumentMismatch(bb, self)
            }
            
            /// Verify bb
            try bb.performVerification()
            /// Verify that bb parent is self
            guard bb.parent == self else {
                throw VerificationError.basicBlockParentMismatch(self, bb)
            }
            /// Check return type
            let bbPremise = try bb.verifyPremise()
            if case let .return(retVal) = bbPremise.terminator.kind {
                switch retVal {
                case let use? where use.type != returnType:
                    throw VerificationError.returnTypeMismatch(bbPremise.terminator, self)
                case nil where !returnType.isVoid:
                    throw VerificationError.returnTypeMismatch(bbPremise.terminator, self)
                default:
                    break
                }
            }
            /// Check dominance for reachable basic blocks
            guard domTree.contains(bb) else { continue }
            for user in bb {
                for use in user.operands {
                    guard domTree.properlyDominates(use, user) else {
                        throw VerificationError.useBeforeDef(user: user, usee: use.value, bb)
                    }
                }
            }
        }
    }
}

extension BasicBlock : Verifiable {
    public func performVerification() throws {
        if let name = name {
            try verifyIdentifier(name, in: self)
        }
        /// Check for terminator
        guard hasTerminator else {
            throw VerificationError<BasicBlock>.missingTerminator(self)
        }
        /// Check for name duplication
        var names: Set<String> = []
        /// Check arguments
        for arg in arguments {
            if let name = arg.name {
                guard !names.contains(name) else {
                    throw VerificationError.redeclared(arg)
                }
                names.insert(name)
            }
            try arg.performVerification()
        }
        /// Check instructions
        for inst in self {
            if let name = inst.name {
                guard !names.contains(name) else {
                    throw VerificationError.redeclared(inst)
                }
                names.insert(name)
            }
            try inst.performVerification()
            /// Check for instruction parent/function mismatch
            guard inst.parent == self else {
                throw VerificationError.instructionParentMismatch(self, inst)
            }
        }
    }
}

extension Argument : Verifiable {
    public func performVerification() throws {
        if let name = name {
            try verifyIdentifier(name, in: self)
        }
    }
}

extension Instruction : Verifiable {
    public func performVerification() throws {
        if let name = name {
            try verifyIdentifier(name, in: self)
        }
        /// Use type must match usee type
        for use in operands {
            try use.performVerification()
            /// Uses must come from same function
            switch use {
            case let .definition(.argument(arg)) where arg.parent.parent != parent.parent:
                throw VerificationError.useInvalidParent(user: self, usee: arg, self.parent.parent)
            case let .definition(.instruction(inst)) where inst.parent.parent != parent.parent:
                throw VerificationError.useInvalidParent(user: self, usee: inst, self.parent.parent)
            default: break
            }
            /// Special case: nested literals can only be in a `literal`
            /// instruction
            if opcode != .literal, case .literal(let ty, let lit) = use {
                guard case .bool = ty else {
                    throw VerificationError
                        .nestedLiteralNotInLiteralInstruction(lit, self)
                }
            }
        }

        /// Visit kind
        try kind.performVerification(in: self)

        /// Check type
        switch type {
        case .void where name != nil:
            /// If void, it cannot have a name
            throw VerificationError.namedVoidValue(self)
        case .invalid:
            /// Cannot be invalid
            throw VerificationError.invalidType(self)
        default:
            break
        }
    }
}

extension InstructionKind {
    /// Verifies instruction
    public func performVerification(in instruction: Instruction) throws {
        switch self {
        case let .builtin(op, args):
            guard IntrinsicRegistry.global.intrinsic(named: op.opcode) == op else {
                throw VerificationError.invalidIntrinsic(op, instruction)
            }
            guard op.resultType(for: args).isValid else {
                throw VerificationError.invalidType(instruction)
            }

        case let .conditional(use, thenBB, thenArgs, elseBB, elseArgs):
            guard case .bool = use.type.unaliased else {
                throw VerificationError.unexpectedType(use, .bool, instruction)
            }
            guard thenBB.arguments.count == thenArgs.count,
                  zip(thenBB.arguments, thenArgs).forAll({$0.1.type == $0.1.type}) else {
                throw VerificationError.basicBlockArgumentMismatch(thenArgs, thenBB, instruction)
            }
            guard elseBB.arguments.count == elseArgs.count,
                  zip(elseBB.arguments, elseArgs).forAll({$0.0.type == $0.1.type}) else {
                throw VerificationError.basicBlockArgumentMismatch(elseArgs, elseBB, instruction)
            }

        case let .branch(bb, args):
            guard bb.arguments.count == args.count,
                  zip(bb.arguments, args).forAll({$0.0.type == $0.1.type}) else {
                throw VerificationError.basicBlockArgumentMismatch(args, bb, instruction)
            }

        case .return: break /// Verified at Function

        case let .literal(lit, ty):
            try LiteralValue(type: ty, literal: lit).performVerification()

        case let .booleanBinary(_, lhs, rhs):
            guard case .bool = lhs.type.unaliased else {
                throw VerificationError.notBool(lhs, instruction)
            }
            guard case .bool = rhs.type.unaliased else {
                throw VerificationError.notBool(rhs, instruction)
            }

        case let .not(v):
            guard case .bool = v.type.unaliased else {
                throw VerificationError.notBool(v, instruction)
            }

        case let .apply(fun, vv):
            let actual = vv.map{$0.type}
            switch fun.type.unaliased {
            case let .function(args, _),
                 let .pointer(.function(args, _)):
                guard actual.count == args.count && zip(actual, args).forAll({$0.0.conforms(to: $0.1)}) else {
                    throw VerificationError.functionArgumentMismatch(vv, fun.type.unaliased, instruction)
                }
            default:
                throw VerificationError.invalidType(fun)
            }

        case let .extract(v1, indices):
            guard !indices.isEmpty else {
                throw VerificationError.missingIndices(v1, instruction)
            }
            guard let _ = v1.type.elementType(at: indices) else {
                throw VerificationError.invalidIndices(v1, indices, instruction)
            }

        case let .insert(src, to: dest, at: indices):
            guard !indices.isEmpty else {
                throw VerificationError.missingIndices(dest, instruction)
            }
            guard let elementType = dest.type.elementType(at: indices) else {
                throw VerificationError.invalidIndices(dest, indices, instruction)
            }
            guard elementType == src.type else {
                throw VerificationError.typeMismatch(src, dest, instruction)
            }

        case let .branchEnum(v1, branches):
            guard case let .enum(e1) = v1.type else {
                throw VerificationError.notEnum(v1, instruction)
            }
            for (name, bb) in branches {
                guard let enumCase = e1.case(named: name) else {
                    throw VerificationError.invalidEnumCase(e1, name, instruction)
                }
                guard enumCase.associatedTypes == bb.arguments.map({$0.type}) else {
                    throw VerificationError.invalidEnumCaseBranch(e1, enumCase, bb, instruction)
                }
            }

        case let .load(v1):
            guard case .pointer(_) = v1.type.unaliased else {
                throw VerificationError.notPointer(v1, instruction)
            }

        case let .store(v1, to: v2):
            guard case let .pointer(elementType) = v2.type.unaliased else {
                throw VerificationError.notPointer(v2, instruction)
            }
            guard v1.type == elementType else {
                throw VerificationError.typeMismatch(v1, v2, instruction)
            }

        case let .copy(from: src, to: dest, _):
            /*
            guard case .int(64) = count.type.unaliased else {
                throw VerificationError.unexpectedType(count, .scalar(.int(64)), instruction)
            }
            */
            switch (src.type, dest.type) {
            case let (.pointer(t1), .pointer(t2)) where t1 == t2:
                break
            default:
                throw VerificationError.invalidCopyOperands(src, dest, instruction)
            }

        case let .elementPointer(v, ii):
            guard case let .pointer(t) = v.type.unaliased else {
                throw VerificationError.notPointer(v, instruction)
            }
            guard let _ = t.elementType(at: ii) else {
                throw VerificationError.invalidOffset(v, ii, instruction)
            }

        case .trap: break
        }
    }
}

extension Use : Verifiable {
    public func performVerification() throws {
        /// Verify value if not function
        switch self {
        case .definition(.function): break
        default: try value.performVerification()
        }
        /// Type must be valid
        guard type.isValid else {
            throw VerificationError.invalidType(self)
        }
        func verify(_ lhs: Type, _ rhs: Type) throws {
            guard lhs == rhs else {
                throw VerificationError.useTypeMismatch(self)
            }
        }
    }
}

extension Definition : Verifiable {
    public func performVerification() throws {
        switch self {
        case .argument(let x): try x.performVerification()
        case .instruction(let x): try x.performVerification()
        case .variable(let x): try x.performVerification()
        case .function(let x): try x.performVerification()
        }
    }
}

/// Verifier pass
public enum Verifier<Unit : IRCollection> : VerificationPass {
    public typealias Body = Unit
    public typealias Result = Void

    public static func run(on body: Body) throws {
        try body.performVerification()
    }
}

/// Cached verification
public extension IRCollection {
    func verify() throws {
        try runVerification(Verifier<Self>.self)
    }
}
