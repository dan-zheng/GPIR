//
//  ParseError.swift
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

import GPIR

public enum LexicalError : Error {
    case unexpectedToken(SourceLocation)
    case illegalNumber(SourceRange)
    case illegalIdentifier(SourceRange)
    case invalidEscapeCharacter(UTF8.CodeUnit, SourceLocation)
    case unclosedStringLiteral(SourceRange)
    case expectingIdentifierName(SourceLocation)
    case invalidAnonymousLocalIdentifier(SourceLocation)
    case invalidBasicBlockIndex(SourceLocation)
    case invalidAnonymousIdentifierIndex(SourceLocation)
    case unknownAttribute(SourceRange)
}

public enum ParseError : Error {
    case unexpectedIdentifierKind(IdentifierKind, Token)
    case unexpectedEndOfInput(expected: String)
    case unexpectedToken(expected: String, Token)
    case noDimensionsInTensorShape(Token)
    case undefinedIdentifier(Token)
    case undefinedIntrinsic(String, SourceRange)
    case invalidReductionCombinator(Intrinsic.Type, SourceRange)
    case typeMismatch(expected: Type, SourceRange)
    case undefinedNominalType(Token)
    case redefinedIdentifier(Token)
    case anonymousIdentifierNotInLocal(Token)
    case invalidInstructionIndex(Token)
    case invalidArgumentIndex(Token)
    case invalidBasicBlockIndex(Token)
    case invalidVariableIndex(Token)
    case invalidFunctionIndex(Token)
    case variableAfterFunction(Token)
    case typeDeclarationNotBeforeValues(Token)
    case notFunctionType(SourceRange)
    case notInBasicBlock(SourceRange)
    case invalidAttributeArguments(SourceLocation)
    case declarationCannotHaveBody(declaration: SourceRange, body: Token)
    case cannotNameVoidValue(Token)
    case invalidOperands(Token, Opcode)
}

public extension LexicalError {
    var location: SourceLocation? {
        switch self {
        case .expectingIdentifierName(let loc),
             .invalidEscapeCharacter(_, let loc),
             .unexpectedToken(let loc),
             .invalidBasicBlockIndex(let loc),
             .invalidAnonymousIdentifierIndex(let loc),
             .invalidAnonymousLocalIdentifier(let loc):
            return loc
        case .illegalIdentifier(let range),
             .illegalNumber(let range),
             .unclosedStringLiteral(let range),
             .unknownAttribute(let range):
            return range.lowerBound
        }
    }
}

public extension ParseError {
    /// Location of the error, nil if EOF
    var location: SourceLocation? {
        switch self {
        case .unexpectedEndOfInput(_):
            return nil
        case let .unexpectedIdentifierKind(_, tok),
             let .unexpectedToken(_, tok),
             let .noDimensionsInTensorShape(tok),
             let .undefinedIdentifier(tok),
             let .undefinedNominalType(tok),
             let .redefinedIdentifier(tok),
             let .anonymousIdentifierNotInLocal(tok),
             let .invalidInstructionIndex(tok),
             let .invalidArgumentIndex(tok),
             let .invalidBasicBlockIndex(tok),
             let .invalidVariableIndex(tok),
             let .invalidFunctionIndex(tok),
             let .variableAfterFunction(tok),
             let .typeDeclarationNotBeforeValues(tok),
             let .declarationCannotHaveBody(_, body: tok),
             let .cannotNameVoidValue(tok),
             let .invalidOperands(tok, _):
            return tok.startLocation
        case let .typeMismatch(_, range),
             let .undefinedIntrinsic(_, range),
             let .invalidReductionCombinator(_, range),
             let .notFunctionType(range),
             let .notInBasicBlock(range):
            return range.lowerBound
        case let .invalidAttributeArguments(loc):
            return loc
        }
    }
}

extension ParseError : CustomStringConvertible {
    public var description : String {
        var desc = "Error at "
        if let location = location {
            desc += location.description
        } else {
            desc += "the end of file"
        }
        desc += ": "
        switch self {
        case let .unexpectedIdentifierKind(kind, tok):
            desc += "identifier \(tok) has unexpected kind \(kind)"
        case let .unexpectedEndOfInput(expected: expected):
            desc += "expected \(expected) but reached the end of input"
        case let .unexpectedToken(expected: expected, tok):
            desc += "expected \(expected) but found \(tok)"
        case let .noDimensionsInTensorShape(tok):
            desc += """
                no dimensions in tensor type at \(tok.startLocation). If you'd \
                like it to be a scalar, use the data type (e.g. f32) directly.
                """
        case let .undefinedIdentifier(tok):
            desc += "undefined identifier \(tok)"
        case let .undefinedIntrinsic(opcode, range):
            desc += "undefined intrinsic \(opcode) at \(range)"
        case let .invalidReductionCombinator(intrinsic, range):
            desc += """
                invalid reduction combinator "\(intrinsic.opcode)" at \(range)
                """
        case let .typeMismatch(expected: ty, range):
            desc += "value at \(range) should have type \(ty)"
        case let .undefinedNominalType(tok):
            desc += "nominal type \(tok) is undefined"
        case let .redefinedIdentifier(tok):
            desc += "identifier \(tok) is redefined"
        case let .anonymousIdentifierNotInLocal(tok):
            desc += """
                anonymous identifier \(tok) is not in a local (basic block) \
                context
                """
        case let .invalidInstructionIndex(tok):
            desc += "anonymous instruction \(tok) has invalid index"
        case let .invalidArgumentIndex(tok):
            desc += "anonymous argument \(tok) has invalid index"
        case let .invalidBasicBlockIndex(tok):
            desc += "anonymous basic block \(tok) has invalid index"
        case let .invalidVariableIndex(tok):
            desc += "anonymous variable \(tok) has invalid index"
        case let .invalidFunctionIndex(tok):
            desc += "anonymous function \(tok) has invalid index"
        case let .variableAfterFunction(tok):
            desc += "variable \(tok) not declared before functions"
        case let .typeDeclarationNotBeforeValues(tok):
            desc += "type \(tok) not declared before value"
        case let .notFunctionType(range):
            desc += "type signature at \(range) is not a function type"
        case let .notInBasicBlock(range):
            desc += "return at \(range) is not in a basic block"
        case .invalidAttributeArguments(_):
            desc += "invalid attribute arguments"
        case let .declarationCannotHaveBody(declaration: declRange, _):
            desc += "declaration at \(declRange) cannot have a body"
        case .cannotNameVoidValue(_):
            desc += "cannot name an instrution value of void type"
        case let .invalidOperands(_, opcode):
            desc += "invalid operands to the '\(opcode)' instruction"
        }
        return desc
    }
}

extension Token : CustomStringConvertible {
    public var description: String {
        return kind.description
    }
}

extension LexicalError : CustomStringConvertible {
    public var description: String {
        var desc = "Error at "
        if let location = location {
            desc += location.description
        } else {
            desc += "the end of file"
        }
        desc += ": "
        switch self {
        case let .illegalIdentifier(range):
            desc += "illegal identifier at \(range)"
        case let .illegalNumber(range):
            desc += "illegal number at \(range)"
        case .unexpectedToken(_):
            desc += "unexpected token"
        case let .invalidEscapeCharacter(ch, _):
            desc += "invalid escape character '\(Character(UnicodeScalar(ch)))'"
        case let .unclosedStringLiteral(range):
            desc += "string literal at \(range) is not terminated"
        case .expectingIdentifierName(_):
            desc += "expecting identifier name"
        case .invalidAnonymousLocalIdentifier(_):
            desc += """
                invalid anonymous local identifier. It should look either like \
                %<bb_index>.<inst_index> or %<bb_index>^<arg_index>, e.g. \
                %0.1 or %0^1
                """
        case .invalidBasicBlockIndex(_):
            desc += """
                invalid index for basic block in anonymous local identifier
                """
        case .invalidAnonymousIdentifierIndex(_):
            desc += "invalid index in anonymous identifier"
        case let .unknownAttribute(range):
            desc += "unknown attribute at \(range)"
        }
        return desc
    }
}

extension Punctuation : CustomStringConvertible {
    public var description: String {
        switch self {
        case .colon: return ":"
        case .comma: return ","
        case .equal: return "="
        case .leftAngleBracket: return "<"
        case .rightAngleBracket: return ">"
        case .leftCurlyBracket: return "{"
        case .rightCurlyBracket: return "}"
        case .leftSquareBracket: return "["
        case .rightSquareBracket: return "]"
        case .leftParenthesis: return "("
        case .rightParenthesis: return ")"
        case .rightArrow: return "->"
        case .star: return "*"
        case .times: return "x"
        }
    }
}

extension Opcode : CustomStringConvertible {
    public var description: String {
        switch self {
        case .builtin: return "builtin"
        case .literal: return "literal"
        case .branch: return "branch"
        case .conditional: return "condition"
        case .return: return "return"
        case .extract: return "extract"
        case .insert: return "insert"
        case .branchEnum: return "branchEnum"
        case .apply: return "apply"
        case .load: return "load"
        case .store: return "store"
        case .copy: return "copy"
        case .elementPointer: return "elementPointer"
        case .trap: return "trap"
        case let .booleanBinaryOp(op): return String(describing: op)
        case .not: return "not"
        }
    }
}

extension TokenKind : CustomStringConvertible {
    public var description: String {
        switch self {
        case let .punctuation(p): return "'\(p)'"
        case let .dataType(dt): return String(describing: dt)
        case let .float(val): return val.description
        case let .integer(val): return val.description
        case let .keyword(kw): return String(describing: kw)
        case let .opcode(op): return String(describing: op)
        case let .identifier(kind, id):
            let kindDesc: String
            switch kind {
            case .basicBlock: kindDesc = "'"
            case .global: kindDesc = "@"
            case .structKey: kindDesc = "#"
            case .enumCase: kindDesc = "?"
            case .temporary: kindDesc = "%"
            case .type: kindDesc = "$"
            }
            return kindDesc + id
        case let .stringLiteral(str): return "\"\(str)\""
        case .newLine: return "a new line"
        case let .anonymousGlobal(i):
            return "@\(i)"
        case let .anonymousArgument(b, i):
            return "%\(b)^\(i)"
        case let .anonymousBasicBlock(i):
            return "'\(i)"
        case let .anonymousInstruction(b, i):
            return "%\(b).\(i)"
        case let .attribute(attr):
            return String(describing: attr)
        }
    }
}
