//
//  Instruction.swift
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

import CoreTensor

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
    /// Elementwise numeric unary operation (map)
    case numericUnary(NumericUnaryOp, Use)
    /// Elementwise numeric binary operation (zipWith)
    case numericBinary(NumericBinaryOp, Use, Use)
    /// Elementwise binary boolean operation
    case booleanBinary(BooleanBinaryOp, Use, Use)
    /// Negation
    case not(Use)
    /// Comparison
    case compare(ComparisonOp, Use, Use)
    /// Select
    case select(Use, Use, by: Use)
    /// Data type cast operation
    case dataTypeCast(Use, DataType)
    /// Scan operation
    case scan(ReductionCombinator, Use, dims: [Int])
    /// Reduction operation
    case reduce(ReductionCombinator, Use, initial: Use, dims: [Int])
    /// Vector dot, matrix-vector multiplication and matrix-matrix multiplication
    case dot(Use, Use)
    /// Concatenation operation
    case concatenate([Use], axis: Int)
    /// Transpose
    case transpose(Use)
    /// Reverse order of elements
    case reverse(Use, dims: [Int])
    /// Slice
    case slice(Use, at: CountableClosedRange<Int>)
    /// Shuffle
    case random(TensorShape, from: Use, upTo: Use)
    /// Reduce window
    case reduceWindow(
        ReductionCombinator, // Function or op
        Use, // Operand
        initial: Use, // Initial value
        dims: [Int], // Window dimensions
        strides: [Int], // Window strides
        padding: Padding // Padding type
    )
    /// Convolution
    /// A convolution can be thought of as a n-dimensional window moving across a n-dimensional
    /// base area and a computation is performed for each possible position of the window.
    /// (https://www.tensorflow.org/performance/xla/operation_semantics#conv)
    case convolve(
        Use, // Input of rank n+2 [batchs, inChannels, ...spatialDims]
        kernel: Use, // Kernel weights of rank n+2 [outChannels, inChannels, ...spatialDims]
        strides: [Int]?, // Kernel strides of rank n, default value 1
        padding: [(low: Int, high: Int)]?, // Padding of rank n, default value 0
        leftDilation: [Int]?, // Dilation factor of rank n, default value 1
        rightDilation: [Int]?, // Dilation factor of rank n, default value 1
        groups: Int? // Group count for grouped/depthwise convolutions, default value 1
    )

    /** Tensor property getters **/
    /// Tensor rank getter
    case rank(of: Use)
    /// Tensor shape getter
    case shape(of: Use)
    /// Tensor unit count getter
    case unitCount(of: Use)

    /** Cost-free casts **/
    /// Pad shape with dimension of 1
    case padShape(Use, at: Int)
    /// Drop dimension of 1 from shape
    case squeezeShape(Use, at: Int)
    /// Shape cast operation
    case shapeCast(Use, to: TensorShape)
    /// Bitcast
    case bitCast(Use, to: Type)

    /** Aggregate operations **/
    /// Extract an element from tensor, tuple, or array
    case extract(from: Use, at: [ElementKey])
    /// Insert an element to tensor, tuple, or array
    case insert(Use, to: Use, at: [ElementKey])

    /** Function application **/
    case apply(Use, [Use])

    /** Stack data structure operations **/
    /// Allocate a stack
    case createStack
    /// Dealloc a stack
    case destroyStack(Use)
    /// Push value to a stack
    case push(Use, to: Use)
    /// Pop value with type from a stack
    case pop(Type, from: Use)

    /** Memory **/
    /// Allocate host stack memory, returning a pointer
    case allocateStack(Type, Int) /// => *T
    case allocateHeap(Type, count: Use) /// => *T
    /// Reference-counted box
    case allocateBox(Type) /// => box{T}
    case projectBox(Use) /// (box{T}) => *T
    /// Retain/release a box via reference counter
    case retain(Use)
    case release(Use)
    /// Dealloc any heap memory
    case deallocate(Use)
    /// Load value from pointer on the host
    case load(Use)
    /// Store value to pointer on the host
    case store(Use, to: Use)
    /// GEP (without leading index)
    case elementPointer(Use, [ElementKey])
    /// Memory copy
    case copy(from: Use, to: Use, count: Use)
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

    /// Returns true iff the instruction reads from or writes to memory
    var accessesMemory: Bool {
        switch self {
        case .allocateStack, .allocateHeap, .allocateBox,
             .projectBox, .load, .store, .deallocate:
            return true
        default:
            return false
        }
    }

    /// Returns true iff the instruction writes to memory
    var mustWriteToMemory: Bool {
        switch self {
        case .store, .copy, .deallocate: return true
        default: return false
        }
    }

    /// Returns true iff the instruction is a binary operation broadcasting
    /// two tensors of different but compatible shapes
    var isBroadcasting: Bool {
        switch self {
        case let .numericBinary(_, x, y),
             let .compare(_, x, y),
             let .booleanBinary(_, x, y):
            guard case let .tensor(s1, _) = x.type.canonical,
                  case let .tensor(s2, _) = y.type.canonical else {
                return false
            }
            return s1 != s2 && s1.isCompatible(with: s2)
        default:
            return false
        }
    }

    /// Returns true iff the instruction performs element-wise arithmetics
    /// with its operands (which are tensors)
    var isElementwiseArithmetic: Bool {
        switch self {
        case .numericUnary, .numericBinary, .compare: return true
        default: return false
        }
    }

    /// Returns true iff the instruction represents a linear transformation
    var isLinearTransformation: Bool {
        switch self {
        case .transpose, .dot: return true
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

        case let .numericUnary(_, v1):
            return v1.tensorType.flatMap { v1Ty in
                NumericUnaryOp.resultType(for: (v1Ty))
            }.map(Type.tensor) ?? .invalid

        case let .numericBinary(_, v1, v2):
            return v1.tensorType.flatMap { v1Ty in
                v2.tensorType.flatMap { v2Ty in
                    NumericBinaryOp.resultType(for: (v1Ty, v2Ty))
                }
            }.map(Type.tensor) ?? .invalid

        case let .booleanBinary(_, v1, v2):
            return v1.tensorType.flatMap { v1Ty in
                v2.tensorType.flatMap { v2Ty in
                    BooleanBinaryOp.resultType(for: (v1Ty, v2Ty))
                }
            }.map(Type.tensor) ?? .invalid

        case let .not(v1):
            return v1.tensorType.flatMap { v1Ty in
                NegationOp.resultType(for: (v1Ty))
            }.map(Type.tensor) ?? .invalid

        case let .compare(_, v1, v2):
            return v1.tensorType.flatMap { v1Ty in
                v2.tensorType.flatMap { v2Ty in
                    ComparisonOp.resultType(for: (v1Ty, v2Ty))
                }
            }.map(Type.tensor) ?? .invalid

        case let .dot(v1, v2):
            guard case let .tensor(s1, t1) = v1.type.unaliased,
                  case let .tensor(s2, t2) = v2.type.unaliased,
                  t1 == t2 else { return .invalid }
            /// Matrix multiplication
            if let newShape = s1.matrixMultiplied(by: s2) {
                return .tensor(newShape, t1)
            }
            /// Vector dot product
            else if s1.isVector, s1 == s2 {
                return .scalar(t1)
            }
            return .invalid

        case let .reduce(op, v1, initial, dims):
            let dtype: DataType
            let resultType: Type
            let dimSet = Set(dims)
            guard case let .tensor(s1, t1) = v1.type.unaliased,
                dims.count <= s1.rank, dims.forAll({ 0 <= $0 && $0 < s1.rank }) else {
                    return .invalid
            }
            switch op {
            case .boolean(_) where t1 == .bool:
                dtype = .bool
                resultType = .tensor(s1.droppingDimensions(dimSet), .bool)
            case .numeric(_) where t1.isNumeric:
                dtype = t1
                resultType = .tensor(s1.droppingDimensions(dimSet), t1)
            case .numericBuiltin(_) where t1.isNumeric:
                dtype = t1
                resultType = .tensor(s1.droppingDimensions(dimSet), t1)
            case let .function(f)
                where f.type.unaliased == .function([.tensor([], t1)], .tensor([], t1)):
                dtype = t1
                resultType = .tensor(s1.droppingDimensions(dimSet), t1)
            default:
                return .invalid
            }
            guard case .tensor([], dtype) = initial.type.canonical else {
                return .invalid
            }
            return resultType

        case let .scan(_, v1, _):
            guard case .tensor = v1.type.unaliased else { return .invalid }
            return v1.type

        case let .concatenate(vv, axis):
            guard let first = vv.first,
                  case let .tensor(s1, t1) = first.type.unaliased,
                  axis < s1.rank
                else { return .invalid }
            var accShape: TensorShape = s1
            for v in vv.dropFirst() {
                guard case let .tensor(shape, type) = v.type.unaliased,
                      type == t1,
                      let newShape = accShape.concatenating(with: shape, alongDimension: axis)
                    else { return .invalid }
                accShape = newShape
            }
            return .tensor(accShape, t1)

        case let .transpose(v1):
            guard case let .tensor(s1, t1) = v1.type.unaliased
                else { return .invalid }
            return .tensor(s1.transpose, t1)

        case let .reverse(v1, dims: dims):
            guard case let .tensor(s1, t1) = v1.type.unaliased
                else { return .invalid }
            guard dims.count <= s1.rank && dims.forAll({ 0 <= $0 && $0 < s1.rank })
                else { return .invalid }
            return .tensor(s1, t1)

        case let .slice(v, at: range):
            return v.type.tensorType.flatMap { tensorTy in
                SliceOp.resultType(for: (tensorTy, range))
            }.map(Type.tensor) ?? .invalid

        case let .random(shape, from: lo, upTo: hi):
            return lo.type.tensorType.flatMap { loTy in
                hi.type.tensorType.flatMap { hiTy in
                    RandomOp.resultType(for: (shape, loTy, hiTy))
                }
            }.map(Type.tensor) ?? .invalid

        case let .select(left, right, by: flags):
            return left.type.tensorType.flatMap { leftTy in
                right.type.tensorType.flatMap { rightTy in
                    flags.type.tensorType.flatMap { flTy in
                        SelectOp.resultType(for: (leftTy, rightTy, flTy))
                    }
                }
            }.map(Type.tensor) ?? .invalid

        case let .convolve(
            lhs, // Input of rank n+2
            kernel, // Kernel weights of rank n+2
            strides, // Kernel strides of rank n
            padding, // Padding of rank n
            leftDilation: ld, // Dilation factor of rank n
            rightDilation: rd, // Dilation factor of rank n
            groups // Group count for grouped/depthwise convolutions
        ):
            guard case let .tensor(s1, t1) = lhs.type.unaliased,
                case let .tensor(s2, t2) = kernel.type.unaliased,
                /// Rank and datatypes must match, rank must be at least 3
                s1.rank == s2.rank, t1 == t2, s1.rank >= 3 else {
                    return .invalid
            }
            /// Set argument defaults
            let n = s1.rank - 2
            let strides = strides ?? Array(repeating: 1, count: n)
            let padding = padding ?? Array(repeating: (low: 0, high: 0), count: n)
            let ld = ld ?? Array(repeating: 1, count: n)
            let rd = rd ?? Array(repeating: 1, count: n)
            let groups = groups ?? 1
            /// Strides/padding/dilation factors must have rank equal to n
            guard strides.count == n, padding.count == n,
                ld.count == n, rd.count == n else {
                    return .invalid
            }
            /// Strides must be greater than one, padding must be non-negative
            /// Dilation factors must be positive
            /// Group count must be between 1 and output channel count
            /// Group count must satisfy s1[1] / groups == s2[1]
            guard strides.forAll({ $0 >= 1 }),
                padding.forAll({ $0.low >= 0 && $0.high >= 0 }),
                ld.forAll({ $0 > 0 }), rd.forAll({ $0 > 0 }),
                1 <= groups && groups <= s2[0], s1[1] / groups == s2[1] else {
                    return .invalid
            }
            /// Calculate output spatial dimensions
            var outputDims: [Int] = []
            for i in 0..<n {
                let dilatedBase = (s1[i + 2] - 1) * ld[i] + 1
                let paddedDilatedBase = padding[i].low + dilatedBase + padding[i].high
                let dilatedWindow = (s2[i + 2] - 1) * rd[i] + 1
                let outputDim = dilatedWindow > paddedDilatedBase
                    ? 0 : (paddedDilatedBase - dilatedWindow) / strides[i] + 1
                outputDims.append(outputDim)
            }
            /// Construct full output shape
            let batchCount = s1[0]
            let outChannelDim = (s2[0] / groups) * groups
            return .tensor(TensorShape([batchCount, outChannelDim] + outputDims), t1)

        /// Reduce window
        case let .reduceWindow(
            op, // Function or op
            v1, // Operand
            initial, // Initial value
            dims, // Window dimensions
            strides, // Window strides
            padding // Padding type
        ):
            let resultType: Type
            /// Operand must be a tensor
            guard case let .tensor(s1, t1) = v1.type.unaliased else {
                return .invalid
            }
            /// Window must have same rank as operand, window dims must be positive
            guard dims.count == s1.rank, dims.forAll({ $0 > 0 }) else {
                    return .invalid
            }
            /// Strides must be greater than one
            guard strides.forAll({ $0 >= 1 }) else {
                return .invalid
            }
            /// Get output shape
            var outputDims: [Int] = []
            for i in 0..<s1.rank {
                let outputDim: Int
                switch padding {
                case .none: outputDim = max((s1[i] - dims[i]) / strides[i] + 1, 0)
                case .half: outputDim = (s1[i] - 1) / strides[i] + 1
                case .full: outputDim = (s1[i] + dims[i] - 2) / strides[i] + 1
                }
                outputDims.append(outputDim)
            }
            let outputShape = TensorShape(outputDims)
            /// Get result type
            switch (op, v1.type.unaliased) {
            case (.boolean(_), .tensor(_, t1)) where t1 == .bool:
                resultType = .tensor(outputShape, .bool)
                break
            case let (.numeric(_), .tensor(_, t1)) where t1.isNumeric:
                resultType = .tensor(outputShape, t1)
                break
            case let (.numericBuiltin(_), .tensor(_, t1)) where t1.isNumeric:
                resultType = .tensor(outputShape, t1)
                break
            case let (.function(f), .tensor(_, t1))
                where f.type.unaliased == .function([.tensor([], t1)], .tensor([], t1)):
                resultType = .tensor(outputShape, t1)
                break
            default:
                return .invalid
            }
            guard case .tensor([], t1) = initial.type.canonical else {
                return .invalid
            }
            return resultType

        case let .dataTypeCast(v1, dt):
            guard case let .tensor(s1, t1) = v1.type.unaliased, t1.canCast(to: dt) else {
                return .invalid
            }
            return .tensor(s1, dt)

        case let .shapeCast(v1, s):
            switch v1.type.unaliased {
            case let .tensor(s1, t1) where s1.contiguousSize == s.contiguousSize:
                return .tensor(s, t1)
            default: return .invalid
            }

        case let .rank(of: v1):
            guard case .tensor = v1.type.unaliased else {
                return .invalid
            }
            return .int(64)

        case let .shape(of: v1):
            guard case let .tensor(s1, _) = v1.type.unaliased else {
                return .invalid
            }
            return .tensor([s1.count], .int(64))

        case let .unitCount(of: v1):
            guard case .tensor = v1.type.unaliased else {
                return .invalid
            }
            return .int(64)

        case let .padShape(v1, at: index):
            switch v1.type.unaliased {
            case let .tensor(s1, t1) where s1.indices.contains(index) || s1.endIndex == index:
                return .tensor(s1.paddingDimension(at: index), t1)
            default: return .invalid
            }

        case let .squeezeShape(v1, at: index):
            switch v1.type.unaliased {
            case let .tensor(s1, t1) where s1.indices.contains(index) && s1[index] == 1:
                return .tensor(s1.droppingDimension(index), t1)
            default: return .invalid
            }

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

        case let .allocateStack(type, n):
            guard n > 0 else { return .invalid }
            return .pointer(type)

        case let .load(v):
            guard case let .pointer(t) = v.type.unaliased else { return .invalid }
            return t

        case let .elementPointer(v, ii):
            guard case let .pointer(t) = v.type else { return .invalid }
            return t.elementType(at: ii).flatMap(Type.pointer) ?? .invalid

        case let .bitCast(_, t):
            // guard v.type.size == t.size else { return .invalid }
            return t

        case let .allocateBox(t):
            return .box(t)

        case let .allocateHeap(t, count: _):
            return .pointer(t)

        case let .projectBox(v):
            guard case let .box(t) = v.type.unaliased else { return .invalid }
            return .pointer(t)

        case .createStack:
            return .stack

        case let .push(_, to: stack):
            guard case .stack = stack.type else { return .invalid }
            return .void

        case let .pop(t, from: stack):
            guard case .stack = stack.type else { return .invalid }
            return t

        case .branch, .conditional, .return, .branchEnum, .store, .copy,
             .deallocate, .destroyStack, .retain, .release, .trap:
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
        case let .numericBinary(_, op1, op2),
             let .booleanBinary(_, op1, op2),
             let .compare(_, op1, op2),
             let .dot(op1, op2),
             let .insert(op1, to: op2, at: _),
             let .convolve(op1, kernel: op2, strides: _, padding: _,
                           leftDilation: _, rightDilation: _, groups: _),
             let .reduce(_, op1, initial: op2, _),
             let .reduceWindow(_, op1, initial: op2, dims: _, strides: _,
                               padding: _),
             let .random(_, from: op1, upTo: op2),
             let .push(op1, to: op2):
            return [op1, op2]
        case let .not(op), let .numericUnary(_, op), let .scan(_, op, _),
             let .transpose(op), let .reverse(op, dims: _), let .slice(op, at: _),
             let .shapeCast(op, _), let .dataTypeCast(op, _), let .bitCast(op, _),
             let .return(op?), let .rank(op), let .shape(op), let .unitCount(op),
             let .padShape(op, at: _), let .squeezeShape(op, at: _),
             let .extract(from: op, at: _), let .branchEnum(op, _), let .load(op),
             let .store(op, _), let .elementPointer(op, _), let .deallocate(op),
             let .allocateHeap(_, count: op), let .projectBox(op),
             let .release(op), let .retain(op), let .destroyStack(op),
             let .pop(_, from: op):
            return [op]
        case .builtin(_, let ops),
             .concatenate(let ops, _),
             .branch(_, let ops):
            return ops
        case let .conditional(cond, _, thenArgs, _, elseArgs):
            return [cond] + thenArgs + elseArgs
        case let .apply(f, args):
            return [f] + args
        case let .copy(from: op1, to: op2, count: op3),
             let .select(op1, op2, by: op3):
            return [op1, op2, op3]
        case let .literal(lit, _):
            return lit.operands
        case .return(nil), .allocateBox, .trap, .allocateStack, .createStack:
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
        case let .array(ops), let .tensor(ops), let .tuple(ops):
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
        case let (.numericUnary(op1, x1), .numericUnary(op2, y1)):
            return op1 == op2 && x1 == y1
        case let (.numericBinary(op1, x1, x2), .numericBinary(op2, y1, y2)):
            return op1 == op2 && x1 == y1 && x2 == y2
        case let (.booleanBinary(op1, x1, x2), .booleanBinary(op2, y1, y2)):
            return op1 == op2 && x1 == y1 && x2 == y2
        case let (.compare(op1, x1, x2), .compare(op2, y1, y2)):
            return op1 == op2 && x1 == y1 && x2 == y2
        case let (.not(x1), .not(x2)):
            return x1 == x2
        case let (.dot(x1, x2), .dot(y1, y2)):
            return x1 == y1 && x2 == y2
        case let (.reduce(op1, x1, i1, d1), .reduce(op2, x2, i2, d2)):
            return op1 == op2 && x1 == x2 && i1 == i2 && d1 == d2
        case let (.reduceWindow(op1, x1, initial: i1, dims: d1, strides: s1, padding: p1),
                  .reduceWindow(op2, x2, initial: i2, dims: d2, strides: s2, padding: p2)):
            return op1 == op2 && x1 == x2 && i1 == i2 && d1 == d2 && s1 == s2 && p1 == p2
        case let (.scan(op1, x1, d1), .scan(op2, x2, d2)):
            return op1 == op2 && x1 == x2 && d1 == d2
        case let (.concatenate(vv1, axis1), .concatenate(vv2, axis2)):
            return vv1 == vv2 && axis1 == axis2
        case let (.transpose(x1), .transpose(x2)):
            return x1 == x2
        case let (.reverse(x1, d1), .reverse(x2, d2)):
            return x1 == x2 && d1 == d2
        case let (.slice(x1, at: range1), .slice(x2, at: range2)):
            return x1 == x2 && range1 == range2
        case let (.random(s1, from: l1, upTo: h1), .random(s2, from: l2, upTo: h2)):
            return s1 == s2 && l1 == l2 && h1 == h2
        case let (.select(l1, r1, by: f1), .select(l2, r2, by: f2)):
            return l1 == l2 && r1 == r2 && f1 == f2
        case let (.convolve(l1, kernel: r1, strides: s1, padding: p1,
                            leftDilation: ld1, rightDilation: rd1, groups: g1),
                  .convolve(l2, kernel: r2, strides: s2, padding: p2,
                            leftDilation: ld2, rightDilation: rd2, groups: g2)):
            guard l1 == l2 && r1 == r2 && s1 == s2 && ld1 == ld2 && rd1 == rd2 && g1 == g2 else {
                return false
            }
            switch (p1, p2) {
            case (nil, nil):
                return true
            case let (p1?, p2?):
                return p1 == p2
            default:
                return false
            }
        case let (.dataTypeCast(x1, dt1), .dataTypeCast(x2, dt2)):
            return x1 == x2 && dt1 == dt2
        case let (.rank(of: x1), .rank(of: x2)),
             let (.shape(of: x1), .shape(of: x2)),
             let (.unitCount(of: x1), .rank(of: x2)):
            return x1 == x2
        case let (.padShape(x1, at: i1), .padShape(x2, at: i2)):
            return x1 == x2 && i1 == i2
        case let (.squeezeShape(x1, at: i1), .squeezeShape(x2, at: i2)):
            return x1 == x2 && i1 == i2
        case let (.shapeCast(x1, s1), .shapeCast(x2, s2)):
            return x1 == x2 && s1 == s2
        case let (.bitCast(x1, t1), .bitCast(x2, t2)):
            return x1 == x2 && t1 == t2
        case let (.apply(f1, args1), .apply(f2, args2)):
            return f1 == f2 && args1 == args2
        case (.createStack, .createStack):
            return true
        case let (.destroyStack(x1), .destroyStack(x2)):
            return x1 == x2
        case let (.push(v1, to: x1), .push(v2, to: x2)):
            return v1 == v2 && x1 == x2
        case let (.pop(t1, from: x1), .pop(t2, from: x2)):
            return t1 == t2 && x1 == x2
        case let (.extract(from: v1, at: i1), .extract(from: v2, at: i2)):
            return v1 == v2 && i1 == i2
        case let (.insert(s1, to: d1, at: i1), .insert(s2, to: d2, at: i2)):
            return s1 == s2 && d1 == d2 && i1 == i2
        case let (.branchEnum(e1, b1), .branchEnum(e2, b2)):
            return e1 == e2 && b1 == b2
        case let (.allocateStack(t1, n1), .allocateStack(t2, n2)):
            return t1 == t2 && n1 == n2
        case let (.load(x1), .load(x2)):
            return x1 == x2
        case let (.elementPointer(x1, ii1), .elementPointer(x2, ii2)):
            return x1 == x2 && ii1 == ii2
        case let (.allocateBox(t1), .allocateBox(t2)):
            return t1 == t2
        case let (.allocateHeap(t1, count: c1), .allocateHeap(t2, count: c2)):
            return t1 == t2 && c1 == c2
        case let (.projectBox(x1), .projectBox(x2)):
            return x1 == x2
        case let (.store(x1, to: d1), .store(x2, to: d2)):
            return x1 == x2 && d1 == d2
        case let (.copy(from: f1, to: t1, count: c1), .copy(from: f2, to: t2, count: c2)):
            return f1 == f2 && t1 == t2 && c1 == c2
        case let (.deallocate(x1), .deallocate(x2)):
            return x1 == x2
        case let (.branch(bb1, x1), .branch(bb2, x2)):
            return bb1 == bb2 && x1 == x2
        case let (.conditional(c1, t1, ta1, e1, ea1), .conditional(c2, t2, ta2, e2, ea2)):
            return c1 == c2 && t1 == t2 && ta1 == ta2 && e1 == e2 && ea1 == ea2
        case let (.return(x1), .return(x2)):
            return x1 == x2
        case let (.retain(x1), .retain(x2)):
            return x1 == x2
        case let (.release(x1), .release(x2)):
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
        case .numericUnary(let fun, old):
            return .numericUnary(fun, new)
        case .numericBinary(let fun, old, old):
            return .numericBinary(fun, new, new)
        case .numericBinary(let fun, old, let use2):
            return .numericBinary(fun, new, use2)
        case .numericBinary(let fun, let use1, old):
            return .numericBinary(fun, use1, new)
        case .booleanBinary(let fun, old, old):
            return .booleanBinary(fun, new, new)
        case .booleanBinary(let fun, old, let use2):
            return .booleanBinary(fun, new, use2)
        case .booleanBinary(let fun, let use1, old):
            return .booleanBinary(fun, use1, new)
        case .compare(let fun, old, old):
            return .compare(fun, new, new)
        case .compare(let fun, old, let use2):
            return .compare(fun, new, use2)
        case .compare(let fun, let use1, old):
            return .compare(fun, use1, new)
        case .not(old):
            return .not(new)
        case let .concatenate(uses, axis: axis):
            return .concatenate(uses.map(condSubst), axis: axis)
        case .transpose(old):
            return .transpose(new)
        case .reverse(old, dims: let dims):
            return .reverse(new, dims: dims)
        case .slice(old, at: let range):
            return .slice(new, at: range)
        case .reduce(.function(old), old, initial: old, dims: let dims):
            return .reduce(.function(new), new, initial: new, dims: dims)
        case .reduce(.function(old), old, initial: let v1, dims: let dims):
            return .reduce(.function(new), new, initial: v1, dims: dims)
        case .reduce(.function(old), let v1, initial: old, dims: let dims):
            return .reduce(.function(new), v1, initial: new, dims: dims)
        case .reduce(.function(old), let v1, initial: let v2, dims: let dims):
            return .reduce(.function(new), v1, initial: v2, dims: dims)
        case .reduce(let op, old, initial: old, dims: let dims):
            return .reduce(op, new, initial: new, dims: dims)
        case .reduce(let op, let v2, initial: old, dims: let dims):
            return .reduce(op, v2, initial: new, dims: dims)
        case .reduce(let op, old, initial: let v2, dims: let dims):
            return .reduce(op, new, initial: v2, dims: dims)
        case .reduceWindow(.function(old), old, initial: old, dims: let d,
                           strides: let s, padding: let p):
            return .reduceWindow(.function(new), new, initial: new,
                                 dims: d, strides: s, padding: p)
        case .reduceWindow(.function(old), old, initial: let v1,
                           dims: let d, strides: let s, padding: let p):
            return .reduceWindow(.function(new), new, initial: v1,
                                 dims: d, strides: s, padding: p)
        case .reduceWindow(.function(old), let v1, initial: old,
                           dims: let d, strides: let s, padding: let p):
            return .reduceWindow(.function(new), v1, initial: new,
                                 dims: d, strides: s, padding: p)
        case .reduceWindow(.function(old), let v1, initial: let v2,
                           dims: let d, strides: let s, padding: let p):
            return .reduceWindow(.function(new), v1, initial: v2,
                                 dims: d, strides: s, padding: p)
        case .reduceWindow(let op, old, initial: old,
                           dims: let d, strides: let s, padding: let p):
            return .reduceWindow(op, new, initial: new,
                                 dims: d, strides: s, padding: p)
        case .reduceWindow(let op, old, initial: let v2,
                           dims: let d, strides: let s, padding: let p):
            return .reduceWindow(op, new, initial: v2,
                                 dims: d, strides: s, padding: p)
        case .reduceWindow(let op, let v2, initial: old,
                           dims: let d, strides: let s, padding: let p):
            return .reduceWindow(op, v2, initial: new,
                                 dims: d, strides: s, padding: p)
        case .convolve(old, kernel: old, strides: let s, padding: let p,
                       leftDilation: let ld, rightDilation: let rd, groups: let g):
            return .convolve(new, kernel: new, strides: s, padding: p,
                             leftDilation: ld, rightDilation: rd, groups: g)
        case .convolve(old, kernel: let v1, strides: let s, padding: let p,
                       leftDilation: let ld, rightDilation: let rd, groups: let g):
            return .convolve(new, kernel: v1, strides: s, padding: p,
                             leftDilation: ld, rightDilation: rd, groups: g)
        case .convolve(let v1, kernel: old, strides: let s, padding: let p,
                       leftDilation: let ld, rightDilation: let rd, groups: let g):
            return .convolve(v1, kernel: new, strides: s, padding: p,
                             leftDilation: ld, rightDilation: rd, groups: g)
        case .dot(old, let use2):
            return .dot(new, use2)
        case .dot(let use1, old):
            return .dot(use1, new)
        case .dot(old, old):
            return .dot(new, new)
        case .rank(of: old):
            return .rank(of: new)
        case .shape(of: old):
            return .shape(of: new)
        case .unitCount(of: old):
            return .unitCount(of: new)
        case .padShape(old, at: let i):
            return .padShape(new, at: i)
        case .squeezeShape(old, at: let i):
            return .squeezeShape(new, at: i)
        case .shapeCast(old, let shape):
            return .shapeCast(new, to: shape)
        case .dataTypeCast(old, let type):
            return .dataTypeCast(new, type)
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
        case .bitCast(old, let targetT):
            return .bitCast(new, to: targetT)
        case .elementPointer(old, let indices):
            return .elementPointer(new, indices)
        case .store(old, to: let dest):
            return .store(new, to: dest)
        case .store(let val, to: old):
            return .store(val, to: new)
        case .load(old):
            return .load(new)
        case .allocateHeap(let ty, count: old):
            return .allocateHeap(ty, count: new)
        case .deallocate(old):
            return .deallocate(new)
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
        case .random(let shape, from: old, upTo: old):
            return .random(shape, from: new, upTo: new)
        case .random(let shape, from: old, upTo: let v2):
            return .random(shape, from: new, upTo: v2)
        case .random(let shape, from: let v1, upTo: old):
            return .random(shape, from: v1, upTo: new)
        case .select(old, old, by: old):
            return .select(new, new, by: new)
        case .select(old, old, by: let v3):
            return .select(new, new, by: v3)
        case .select(let v1, old, by: old):
            return .select(v1, new, by: new)
        case .select(old, let v2, by: old):
            return .select(new, v2, by: new)
        case .select(old, let v2, by: let v3):
            return .select(new, v2, by: v3)
        case .select(let v1, old, by: let v3):
            return .select(v1, new, by: v3)
        case .select(let v1, let v2, by: old):
            return .select(v1, v2, by: new)
        case .destroyStack(old):
            return .destroyStack(new)
        case .push(old, to: old):
            return .push(new, to: new)
        case .push(let val, to: old):
            return .push(val, to: new)
        case .push(old, to: let stack):
            return .push(new, to: stack)
        case .pop(let ty, from: old):
            return .pop(ty, from: new)
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
    case dataTypeCast
    case scan
    case reduce
    case reduceWindow
    case dot
    case concatenate
    case transpose
    case reverse
    case slice
    case convolve
    case rank
    case shape
    case unitCount
    case padShape
    case squeezeShape
    case shapeCast
    case bitCast
    case extract
    case insert
    case apply
    case allocateStack
    case allocateHeap
    case allocateBox
    case projectBox
    case createStack
    case destroyStack
    case push
    case pop
    case retain
    case release
    case deallocate
    case load
    case store
    case elementPointer
    case copy
    case trap
    case numericBinaryOp(NumericBinaryOp)
    case compare(ComparisonOp)
    case numericUnaryOp(NumericUnaryOp)
    case not
    case booleanBinaryOp(BooleanBinaryOp)
    case random
    case select
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
        case .numericUnary(let op, _): return .numericUnaryOp(op)
        case .numericBinary(let op, _, _): return .numericBinaryOp(op)
        case .booleanBinary(let op, _, _): return .booleanBinaryOp(op)
        case .not: return .not
        case .compare(let op, _, _): return .compare(op)
        case .dataTypeCast: return .dataTypeCast
        case .scan: return .scan
        case .reduce: return .reduce
        case .reduceWindow: return .reduceWindow
        case .dot: return .dot
        case .concatenate: return .concatenate
        case .transpose: return .transpose
        case .reverse: return .reverse
        case .slice: return .slice
        case .convolve: return .convolve
        case .rank: return .rank
        case .shape: return .shape
        case .unitCount: return .unitCount
        case .padShape: return .padShape
        case .squeezeShape: return .squeezeShape
        case .shapeCast: return .shapeCast
        case .bitCast: return .bitCast
        case .extract: return .extract
        case .insert: return .insert
        case .apply: return .apply
        case .allocateStack: return .allocateStack
        case .allocateHeap: return .allocateHeap
        case .allocateBox: return .allocateBox
        case .projectBox: return .projectBox
        case .createStack: return .createStack
        case .destroyStack: return .destroyStack
        case .push: return .push
        case .pop: return .pop
        case .retain: return .retain
        case .release: return .release
        case .deallocate: return .deallocate
        case .load: return .load
        case .store: return .store
        case .elementPointer: return .elementPointer
        case .copy: return .copy
        case .trap: return .trap
        case .random: return .random
        case .select: return .select
        }
    }
}
