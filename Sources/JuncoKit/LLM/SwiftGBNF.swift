// SwiftGBNF.swift — GBNF grammars for constrained Swift code generation via Ollama
//
// GBNF (GGML BNF) constrains token-by-token sampling in llama.cpp models.
// These grammars enforce structural correctness (balanced braces, imports first,
// no prose preamble) without restricting the full Swift language.
//
// Intentionally permissive — they prevent structural errors, not semantic ones.

import Foundation

/// GBNF grammars for constrained Swift code generation via Ollama/llama.cpp.
public enum SwiftGBNF {

  /// Select the appropriate grammar for a file role.
  /// Returns nil for roles where grammar constraints aren't beneficial.
  public static func grammar(for role: String) -> String? {
    switch role {
    case "view": return swiftUIViewBody
    case "viewmodel", "service", "model": return swiftFile
    default: return swiftFile
    }
  }

  // MARK: - Grammar: Complete Swift File

  /// Grammar for a complete Swift file.
  /// Enforces: starts with imports, followed by declarations, balanced braces, no trailing prose.
  public static let swiftFile = """
    root ::= ws imports ws declarations ws

    imports ::= (import-stmt ws)*
    import-stmt ::= "import " identifier newline

    declarations ::= (declaration ws)*
    declaration ::= attribute-list ws decl-keyword ws identifier ws conformances ws "{" ws body ws "}" ws
    declaration ::= attribute-list ws "func " identifier ws func-params ws return-clause ws "{" ws body ws "}" ws
    declaration ::= attribute-list ws property-keyword ws identifier ws type-annotation ws initializer ws newline
    declaration ::= comment ws

    attribute-list ::= (attribute ws)*
    attribute ::= "@" identifier ( "(" attr-args ")" )?
    attr-args ::= [^)]*

    decl-keyword ::= "struct" | "class" | "enum" | "actor" | "protocol" | "extension"
    property-keyword ::= "let" | "var"
    access-modifier ::= "public " | "private " | "internal " | "open " | "fileprivate " | ""

    conformances ::= (":" ws identifier-list)?
    identifier-list ::= identifier (ws "," ws identifier)*

    func-params ::= "(" params ")"
    params ::= (param ("," ws param)*)?
    param ::= identifier ws ":" ws type-expr (ws "=" ws expr)?

    return-clause ::= (ws "->" ws type-expr)?
    type-annotation ::= (":" ws type-expr)?
    initializer ::= (ws "=" ws expr)?

    type-expr ::= [A-Za-z_] [A-Za-z0-9_.<>,? \\[\\]]*
    expr ::= [^\\n{}]*

    body ::= (body-line ws)*
    body-line ::= nested-block | line-content newline
    nested-block ::= [^{}]* "{" ws body ws "}" [^\\n]* newline
    line-content ::= [^{}\\n]+

    comment ::= "//" [^\\n]* newline
    comment ::= "/*" ([^*] | "*" [^/])* "*/"
    identifier ::= [A-Za-z_] [A-Za-z0-9_]*
    newline ::= "\\n"
    ws ::= [ \\t\\n]*
    """

  // MARK: - Grammar: SwiftUI View Body

  /// Grammar for SwiftUI view files.
  /// Enforces the `struct X: View { var body: some View { ... } }` pattern
  /// with balanced braces in the view builder.
  public static let swiftUIViewBody = """
    root ::= ws imports ws view-struct ws

    imports ::= (import-stmt ws)*
    import-stmt ::= "import " identifier newline

    view-struct ::= attributes ws access ws "struct " identifier ": " view-conformances "{" ws view-members ws "}" ws
    attributes ::= (attribute ws)*
    attribute ::= "@" identifier ( "(" attr-args ")" )?
    attr-args ::= [^)]*
    access ::= ("public " | "private " | "internal " | "")?

    view-conformances ::= "View" (ws "," ws identifier)* ws
    view-members ::= (view-member ws)*
    view-member ::= property-decl | body-decl | func-decl | nested-type | comment

    property-decl ::= attributes ws property-keyword ws identifier ws type-annotation ws initializer ws newline
    property-keyword ::= "let" | "var" | "@State var" | "@State private var" | "@Binding var" | "@Environment(" env-key ") var"
    env-key ::= [^)]+

    body-decl ::= "var body: some View {" ws view-body ws "}" ws
    view-body ::= (view-expr ws)*
    view-expr ::= view-call | nested-view-block | modifier-chain | comment | line-content newline
    view-call ::= identifier "(" [^)]* ")" modifier-chain?
    nested-view-block ::= identifier ws "{" ws view-body ws "}" modifier-chain?
    modifier-chain ::= (ws "." identifier "(" [^)]* ")")*

    func-decl ::= attributes ws access ws "func " identifier "(" params ")" return-clause ws "{" ws body ws "}" ws
    nested-type ::= access ws decl-keyword ws identifier ws conformances ws "{" ws body ws "}" ws
    decl-keyword ::= "struct" | "class" | "enum"

    params ::= (param ("," ws param)*)?
    param ::= identifier ws ":" ws type-expr (ws "=" ws expr)?
    return-clause ::= (ws "->" ws type-expr)?
    type-annotation ::= (":" ws type-expr)?
    initializer ::= (ws "=" ws expr)?
    conformances ::= (":" ws identifier-list)?
    identifier-list ::= identifier (ws "," ws identifier)*

    type-expr ::= [A-Za-z_] [A-Za-z0-9_.<>,? \\[\\]]*
    expr ::= [^\\n{}]*
    body ::= (body-line ws)*
    body-line ::= nested-block | line-content newline
    nested-block ::= [^{}]* "{" ws body ws "}" [^\\n]* newline
    line-content ::= [^{}\\n]+

    comment ::= "//" [^\\n]* newline
    identifier ::= [A-Za-z_] [A-Za-z0-9_]*
    newline ::= "\\n"
    ws ::= [ \\t\\n]*
    """

  // MARK: - Grammar: Struct/Class Body

  /// Grammar for a simple struct or class body with balanced braces.
  public static let structBody = """
    root ::= ws imports ws type-decl ws

    imports ::= (import-stmt ws)*
    import-stmt ::= "import " identifier newline

    type-decl ::= attributes ws access ws type-keyword ws identifier ws conformances ws "{" ws members ws "}" ws
    attributes ::= (attribute ws)*
    attribute ::= "@" identifier ( "(" attr-args ")" )?
    attr-args ::= [^)]*
    access ::= ("public " | "private " | "internal " | "open " | "")?
    type-keyword ::= "struct" | "class" | "actor" | "enum"

    conformances ::= (":" ws identifier-list)?
    identifier-list ::= identifier (ws "," ws identifier)*

    members ::= (member ws)*
    member ::= property-decl | func-decl | init-decl | nested-type | enum-case | comment
    property-decl ::= attributes ws prop-keyword ws identifier ws type-annotation ws initializer ws newline
    prop-keyword ::= "let" | "var" | "static let" | "static var" | "private let" | "private var"

    func-decl ::= attributes ws access ws static ws "func " identifier "(" params ")" async-throws ws return-clause ws "{" ws body ws "}" ws
    init-decl ::= access ws "init" "(" params ")" ws throws ws "{" ws body ws "}" ws
    nested-type ::= attributes ws access ws type-keyword ws identifier ws conformances ws "{" ws members ws "}" ws
    enum-case ::= "case " identifier (ws "(" params ")")? ws newline

    static ::= ("static " | "")?
    async-throws ::= (" async" | "")? (" throws" | "")?
    throws ::= ("throws" | "")?
    params ::= (param ("," ws param)*)?
    param ::= identifier ws ":" ws type-expr (ws "=" ws expr)?
    return-clause ::= (ws "->" ws type-expr)?
    type-annotation ::= (":" ws type-expr)?
    initializer ::= (ws "=" ws expr)?

    type-expr ::= [A-Za-z_] [A-Za-z0-9_.<>,? \\[\\]]*
    expr ::= [^\\n{}]*
    body ::= (body-line ws)*
    body-line ::= nested-block | line-content newline
    nested-block ::= [^{}]* "{" ws body ws "}" [^\\n]* newline
    line-content ::= [^{}\\n]+

    comment ::= "//" [^\\n]* newline
    identifier ::= [A-Za-z_] [A-Za-z0-9_]*
    newline ::= "\\n"
    ws ::= [ \\t\\n]*
    """

  // MARK: - Validation

  /// Basic syntax check: grammar has a root rule and all rules have `::=`.
  public static func isValidGBNF(_ grammar: String) -> Bool {
    guard grammar.contains("root ::=") else { return false }
    // Check that all non-empty, non-comment lines with rule names have ::=
    let lines = grammar.components(separatedBy: "\n")
    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.isEmpty { continue }
      // Lines that define rules must contain ::=
      // Lines that are continuations (start with |) or are empty are ok
      if trimmed.first?.isLetter == true && !trimmed.contains("::=") && !trimmed.hasPrefix("|") {
        return false
      }
    }
    return true
  }
}
