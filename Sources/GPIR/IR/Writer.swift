//
//  Writer.swift
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

extension LiteralValue : TextOutputStreamable {
    public func write<Target : TextOutputStream>(to target: inout Target) {
        target.write("\(literal) : \(type)")
    }
}

extension Literal : TextOutputStreamable {
    public func write<Target : TextOutputStream>(to target: inout Target) {
        switch self {
        case let .bool(b):
            target.write(b.description)
        case let .tuple(vals):
            target.write("(\(vals.joinedDescription))")
        case let .struct(fields):
            target.write("{\(fields.map{"#\($0.0) = \($0.1)"}.joined(separator: ", "))}")
        case let .enumCase(name, associatedTypes):
            target.write("?\(name)(\(associatedTypes.joinedDescription))")
        case .zero:
            target.write("zero")
        case .undefined:
            target.write("undefined")
        case .null:
            target.write("null")
        }
    }
}

extension StructType : TextOutputStreamable {
    public func write<Target>(to target: inout Target) where Target : TextOutputStream {
        target.write("struct $\(name) {\n")
        for (name, type) in fields {
            target.write("    #\(name): \(type)\n")
        }
        target.write("}")
    }
}

extension EnumType : TextOutputStreamable {
    public func write<Target>(to target: inout Target) where Target : TextOutputStream {
        target.write("enum $\(name) {\n")
        for (name, assocTypes) in cases {
            target.write("    ?\(name)(\(assocTypes.joinedDescription))\n")
        }
        target.write("}")
    }
}

extension Type : TextOutputStreamable {
    public func write<Target>(to target: inout Target) where Target : TextOutputStream {
        switch self {
        case .invalid:
            target.write("<<error>>")
        case .bool:
            target.write("bool")
        case let .tuple(elementTypes):
            target.write("(\(elementTypes.joinedDescription))")
        case let .pointer(elementType):
            target.write("*\(elementType)")
        case let .function(args, ret):
            target.write("(\(args.joinedDescription)) -> \(ret)")
        case let .alias(a):
            target.write("$")
            a.name.write(to: &target)
        case let .struct(structTy):
            target.write("$")
            structTy.name.write(to: &target)
        case let .enum(enumTy):
            target.write("$")
            enumTy.name.write(to: &target)
        }
    }
}

extension DataType.Base : TextOutputStreamable {
    public func write<Target : TextOutputStream>(to target: inout Target) {
        switch self {
        case .float: target.write("f")
        case .int: target.write("i")
        case .bool: target.write("b")
        }
    }
}

extension DataType : TextOutputStreamable {
    public func write<Target : TextOutputStream>(to target: inout Target) {
        switch self {
        case .bool: target.write("bool")
        case let .int(w): target.write("i\(w)")
        case let .float(w): target.write("f\(w.rawValue)")
        }
    }
}

extension InstructionKind : TextOutputStreamable {
    public func write<Target : TextOutputStream>(to target: inout Target) {
        switch self {
        case let .builtin(op, args):
            target.write("""
                \(op.description)(\(args.joinedDescription)) \
                -> \(op.resultType(for: args))
                """)
        case let .branch(bb, args):
            target.write("branch '\(bb.printedName)(\(args.joinedDescription))")
        case let .conditional(op, thenBB, thenArgs, elseBB, elseArgs):
            target.write("""
                conditional \(op) \
                then '\(thenBB.printedName)(\(thenArgs.joinedDescription)) \
                else '\(elseBB.printedName)(\(elseArgs.joinedDescription))
                """)
        case let .return(op):
            target.write("return")
            if let op = op {
                target.write(" \(op)")
            }
        case let .literal(lit, ty):
            target.write("literal \(lit): \(ty)")
        case let .booleanBinary(f, op1, op2):
            target.write("\(f) \(op1), \(op2)")
        case let .not(op):
            target.write("not \(op)")
        case let .apply(f, args):
            var retType: Type = .invalid
            if case let .function(_, fRetType) = f.type {
                retType = fRetType
            }
            target.write("apply \(f.identifier)(\(args.joinedDescription)) -> \(retType)")
        case let .extract(use, indices):
            target.write("extract \(indices.joinedDescription) from \(use)")
        case let .insert(src, to: dest, at: indices):
            target.write("insert \(src) to \(dest) at \(indices.joinedDescription)")
        case let .branchEnum(e1, branches):
            target.write("branchEnum \(e1)")
            for (name, bb) in branches {
                target.write(" case ?\(name) '\(bb.printedName)")
            }
        case let .load(v):
            target.write("load \(v)")
        case let .store(v, p):
            target.write("store \(v) to \(p)")
        case let .copy(from: src, to: dest, count: count):
            target.write("copy from \(src) to \(dest) count \(count)")
        case let .elementPointer(v, ii):
            target.write("elementPointer \(v) at \(ii.joinedDescription)")
        case .trap:
            target.write("trap")
        }
    }
}

extension Instruction : TextOutputStreamable {
    public func write<Target : TextOutputStream>(to target: inout Target) {
        if let name = printedName {
            target.write("%\(name) = ")
        }
        kind.write(to: &target)
    }
}

extension Variable : TextOutputStreamable {
    public func write<Target : TextOutputStream>(to target: inout Target) {
        target.write("var @\(printedName): \(valueType)")
    }
}

extension TypeAlias : TextOutputStreamable {
    public func write<Target>(to target: inout Target) where Target : TextOutputStream {
        target.write("type $\(name) = ")
        if let type = type {
            type.write(to: &target)
        } else {
            target.write("opaque")
        }
    }
}

extension ElementKey : TextOutputStreamable {
    public func write<Target>(to target: inout Target) where Target : TextOutputStream {
        switch self {
        case let .index(i): target.write("\(i)")
        case let .name(n): target.write("#" + n)
        case let .value(v): target.write("\(v)")
        }
    }
}

extension Use : TextOutputStreamable {
    public func write<Target : TextOutputStream>(to target: inout Target) {
        target.write("\(identifier): \(type)")
    }

    public var identifier: String {
        switch self {
        case let .literal(_, lit):
            return lit.description
        case let .definition(.variable(ref)):
            return "@\(ref.printedName)"
        case let .definition(.instruction(ref)):
            return ref.printedName.flatMap{"%\($0)"} ?? "%_"
        case let .definition(.argument(ref)):
            return "%\(ref.printedName)"
        case let .definition(.function(ref)):
            return "@\(ref.printedName)"
        }
    }
}

extension BasicBlock : TextOutputStreamable {
    private func makeIndentation() -> String {
        return "    "
    }

    public func write<Target : TextOutputStream>(to target: inout Target) {
        /// Begin block
        target.write("'\(printedName)(\(arguments.map{"\($0)"}.joined(separator: ", "))):\n")
        for inst in elements {
            /// Write indentation
            makeIndentation().write(to: &target)
            inst.write(to: &target)
            target.write("\n")
        }
    }
}

extension Argument : TextOutputStreamable {
    public func write<Target>(to target: inout Target) where Target : TextOutputStream {
        target.write("%\(printedName): \(type)")
    }
}

extension Function.Attribute : TextOutputStreamable {
    public func write<Target>(to target: inout Target) where Target : TextOutputStream {
        target.write("!")
        switch self {
        case .inline: target.write("inline")
        }
    }
}

extension Function : TextOutputStreamable {
    public func write<Target : TextOutputStream>(to target: inout Target) {
        for attr in attributes {
            attr.write(to: &target)
            target.write("\n")
        }
        switch declarationKind {
        case .external?:
            target.write("[extern]\n")
        default:
            break
        }
        target.write("func ")
        target.write("@\(printedName): \(type)")
        if isDefinition {
            target.write(" {\n")
            for bb in self {
                bb.write(to: &target)
            }
            target.write("}")
        }
    }
}

extension String {
    var literal: String {
        var out = ""
        for char in self {
            switch char {
            case "\"", "\\":
                out.append("\\")
                out.append(char)
            case "\n":
                out.append("\\n")
            case "\t":
                out.append("\\t")
            case "\r":
                out.append("\\r")
            default:
                out.append(char)
            }
        }
        return out
    }
}

extension Module : TextOutputStreamable {
    func write<C, T>(_ elements: C, to target: inout T)
        where C : Collection, T : TextOutputStream,
              C.Element : TextOutputStreamable
    {
        for element in elements {
            target.write("\n")
            element.write(to: &target)
            target.write("\n")
        }
    }

    public func write<Target : TextOutputStream>(to target: inout Target) {
        target.write("module \"\(name.literal)\"\n")
        target.write("stage \(stage)\n")
        write(enums, to: &target)
        write(structs, to: &target)
        write(typeAliases, to: &target)
        write(variables, to: &target)
        write(elements, to: &target)
    }
}
