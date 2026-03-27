#!/usr/bin/env swift
// generate_data.swift — Generate 10K+ labeled training examples for intent classification
//
// Labels: fix, add, refactor, explain, test, explore
// Includes: adversarial, multi-lingual, ambiguous, ALL CAPS, lower case, paste-like inputs
//
// Run: swift Training/generate_data.swift > Training/intent_data.json

import Foundation

struct Example: Codable {
  let text: String
  let label: String
}

var examples: [Example] = []
var rng = SystemRandomNumberGenerator()

// MARK: - Templates per label

let fixTemplates = [
  "fix the bug in {file}", "there's an error in {func}", "this crashes when {action}",
  "debug {file}", "the {func} function is broken", "getting an error: {error}",
  "why does {func} throw an exception", "null pointer in {file}",
  "fix: {error}", "broken: {func} returns wrong value",
  "segfault when calling {func}", "race condition in {file}",
  "memory leak in {func}", "fix the typo in {file}",
  "the build fails because of {file}", "type error in {func}",
  "this doesn't compile: {error}", "runtime crash in {file}",
  "fix the regression in {func}", "patch the vulnerability in {file}",
  "resolve the merge conflict in {file}", "the test is flaky: {func}",
  "off-by-one error in {func}", "infinite loop in {file}",
  "deadlock when {action}", "fix the import in {file}",
]

let addTemplates = [
  "add a {thing} to {file}", "create a new {thing}", "implement {func}",
  "write a {thing} that {action}", "add {feature} support",
  "create {file}", "implement the {func} method",
  "add a new endpoint for {thing}", "build a {thing} component",
  "write {func} function", "add error handling to {file}",
  "implement {feature} feature", "add logging to {func}",
  "create a {thing} class", "add a {thing} command",
  "implement pagination for {thing}", "add caching to {func}",
  "create a new module for {thing}", "add authentication to {file}",
  "write a migration for {thing}", "scaffold {thing}",
  "generate boilerplate for {thing}", "add a new route for {thing}",
  "implement the {thing} protocol", "add {thing} to the config",
]

let refactorTemplates = [
  "refactor {func}", "clean up {file}", "simplify {func}",
  "extract {thing} from {file}", "rename {func} to something better",
  "move {func} to {file}", "split {file} into smaller files",
  "convert {func} to async/await", "modernize {file}",
  "reduce complexity of {func}", "DRY up {file}",
  "remove duplication in {func}", "optimize {func}",
  "restructure {file}", "decouple {thing} from {file}",
  "convert callbacks to promises in {file}", "improve the API of {func}",
  "make {func} more testable", "extract interface from {file}",
  "consolidate {thing}", "reorganize the {thing} module",
  "replace {thing} with {thing}", "migrate {file} to new API",
]

let explainTemplates = [
  "explain {func}", "what does {file} do", "how does {func} work",
  "explain this code", "walk me through {file}",
  "what is the purpose of {func}", "describe {file}",
  "help me understand {func}", "what's happening in {file}",
  "read {file} and explain", "summarize {file}",
  "explain the architecture of {thing}", "how is {thing} structured",
  "what does this error mean: {error}", "why is {func} designed this way",
  "trace the flow through {func}", "explain the {thing} pattern",
  "what are the dependencies of {file}", "how does {thing} connect to {thing}",
  "document {func}", "annotate {file} with comments",
]

let testTemplates = [
  "write tests for {func}", "add unit tests to {file}",
  "test {func}", "create test cases for {thing}",
  "add integration tests for {file}", "write a test that {action}",
  "test the edge cases in {func}", "add test coverage for {file}",
  "write a regression test for {func}", "test {thing} with mock data",
  "verify {func} handles errors", "test the happy path for {func}",
  "add snapshot tests for {thing}", "write performance tests for {func}",
  "test {func} with boundary values", "create a test fixture for {thing}",
  "test the API endpoint for {thing}", "add E2E tests for {thing}",
]

let exploreTemplates = [
  "search for {thing}", "find all uses of {func}",
  "list files in {thing}", "grep for {thing}",
  "where is {func} defined", "find {thing} in the codebase",
  "show me the {thing}", "look for {thing}",
  "what files use {func}", "find references to {thing}",
  "search the project for {thing}", "where is {thing} imported",
  "list all {thing} in the project", "find TODO comments",
  "show the file structure", "what dependencies does this project use",
  "scan for {thing}", "locate {func}",
]

// MARK: - Substitution values

let files = ["main.swift", "auth.swift", "App.js", "index.ts", "utils.py",
             "server.go", "handler.rs", "config.json", "style.css", "Login.vue",
             "api/routes.js", "src/components/Header.tsx", "Package.swift",
             "Models/User.swift", "lib/auth.rb", "test_utils.py"]

let funcs = ["login", "fetchData", "handleClick", "parseJSON", "validate",
             "authenticate", "processPayment", "sendEmail", "renderUI",
             "calculateTotal", "formatDate", "saveToDatabase", "encryptPassword",
             "generateToken", "parseArgs", "middleware", "serialize"]

let things = ["button", "form", "modal", "navbar", "sidebar", "table",
              "dropdown", "API", "database", "cache", "queue", "worker",
              "logger", "config", "schema", "migration", "controller",
              "service", "repository", "middleware", "decorator", "hook"]

let actions = ["clicking submit", "loading the page", "entering special characters",
               "passing nil", "concurrent access", "timeout", "large input",
               "empty string", "unicode characters", "negative numbers"]

let errors = ["index out of range", "nil unwrap", "type mismatch",
              "connection refused", "timeout exceeded", "permission denied",
              "Cannot find 'x' in scope", "undefined is not a function",
              "Expected ';'", "unresolved identifier"]

let features = ["dark mode", "search", "pagination", "undo",
                "autocomplete", "drag and drop", "notifications",
                "export to PDF", "OAuth", "rate limiting"]

func sub(_ template: String) -> String {
  var s = template
  s = s.replacingOccurrences(of: "{file}", with: files.randomElement()!)
  s = s.replacingOccurrences(of: "{func}", with: funcs.randomElement()!)
  s = s.replacingOccurrences(of: "{thing}", with: things.randomElement()!)
  s = s.replacingOccurrences(of: "{action}", with: actions.randomElement()!)
  s = s.replacingOccurrences(of: "{error}", with: errors.randomElement()!)
  s = s.replacingOccurrences(of: "{feature}", with: features.randomElement()!)
  return s
}

// MARK: - Generate base examples (6K)

let allTemplates: [(templates: [String], label: String)] = [
  (fixTemplates, "fix"),
  (addTemplates, "add"),
  (refactorTemplates, "refactor"),
  (explainTemplates, "explain"),
  (testTemplates, "test"),
  (exploreTemplates, "explore"),
]

for (templates, label) in allTemplates {
  for _ in 0..<1000 {
    let template = templates.randomElement()!
    examples.append(Example(text: sub(template), label: label))
  }
}

// MARK: - Case variations (1.2K)

for (templates, label) in allTemplates {
  for _ in 0..<100 {
    let text = sub(templates.randomElement()!)
    examples.append(Example(text: text.uppercased(), label: label))  // ALL CAPS
    examples.append(Example(text: text.lowercased(), label: label))  // lower case
  }
}

// MARK: - Terse/shorthand (600)

let terseExamples: [(String, String)] = [
  ("fix {func}", "fix"), ("bug {file}", "fix"), ("broken", "fix"), ("crash", "fix"),
  ("add {thing}", "add"), ("create {file}", "add"), ("new {thing}", "add"), ("implement", "add"),
  ("refactor {func}", "refactor"), ("cleanup", "refactor"), ("simplify", "refactor"),
  ("explain {func}", "explain"), ("what is this", "explain"), ("how", "explain"), ("why", "explain"),
  ("test {func}", "test"), ("add tests", "test"), ("coverage", "test"),
  ("find {thing}", "explore"), ("search {thing}", "explore"), ("where", "explore"), ("grep", "explore"),
]
for _ in 0..<30 {
  for (template, label) in terseExamples {
    examples.append(Example(text: sub(template), label: label))
  }
}

// MARK: - Multi-lingual (600)

let multiLingual: [(String, String)] = [
  // Spanish
  ("arregla el error en {file}", "fix"), ("añade una función a {file}", "add"),
  ("refactoriza {func}", "refactor"), ("explica {func}", "explain"),
  ("agrega pruebas para {func}", "test"), ("busca {thing}", "explore"),
  // French
  ("corrige le bug dans {file}", "fix"), ("ajoute un {thing}", "add"),
  ("restructure {func}", "refactor"), ("explique {func}", "explain"),
  // German
  ("behebe den Fehler in {file}", "fix"), ("füge {thing} hinzu", "add"),
  ("vereinfache {func}", "refactor"), ("erkläre {func}", "explain"),
  // Japanese (romanized)
  ("{func} no bagu wo naoshite", "fix"), ("{thing} wo tsuika shite", "add"),
  ("{func} wo setsumei shite", "explain"),
  // Chinese (simplified)
  ("修复{file}中的错误", "fix"), ("添加{thing}", "add"),
  ("解释{func}", "explain"), ("测试{func}", "test"),
  // Portuguese
  ("corrija o erro em {file}", "fix"), ("adicione {thing}", "add"),
  // Korean (romanized)
  ("{file} beogeu gochyeo", "fix"), ("{thing} chuga hae", "add"),
  // Mixed language
  ("fix el bug in {file} por favor", "fix"),
  ("please 添加 a new {thing}", "add"),
]
for _ in 0..<25 {
  for (template, label) in multiLingual {
    examples.append(Example(text: sub(template), label: label))
  }
}

// MARK: - Adversarial / ambiguous (600)

let adversarial: [(String, String)] = [
  // Context-dependent
  ("look at {func} and fix it", "fix"),
  ("can you check {file} for issues and fix them", "fix"),
  ("i need {thing} working", "fix"),
  ("make {func} better", "refactor"),
  ("improve {file}", "refactor"),
  ("update {func}", "refactor"),
  // Paste-like content
  ("[Paste #1: 45 lines, 1200 chars] fix this", "fix"),
  ("[Paste #1: 20 lines, 500 chars] what does this do", "explain"),
  ("[Paste #1: 10 lines, 300 chars] add tests for this", "test"),
  // With error output pasted
  ("Error: Cannot find '{func}' in scope\nfix this", "fix"),
  ("TypeError: {func} is not a function\nwhat's wrong", "fix"),
  // Imperative vs interrogative
  ("{func}", "explain"),  // bare function name → explain
  ("{file}", "explain"),  // bare file name → explain
  ("tests", "test"),
  ("search", "explore"),
  // Typos
  ("fixx the bugg in {file}", "fix"),
  ("ad a new {thing}", "add"),
  ("refactr {func}", "refactor"),
  ("explane {func}", "explain"),
  ("tset {func}", "test"),
]
for _ in 0..<30 {
  for (template, label) in adversarial {
    examples.append(Example(text: sub(template), label: label))
  }
}

// MARK: - Long/complex queries (400)

let complex: [(String, String)] = [
  ("I'm getting a crash when users log in with SSO. The error is in {file} around the {func} function. Can you take a look and fix it?", "fix"),
  ("We need to add a new {thing} that handles {action}. It should be created in {file} and follow the existing patterns.", "add"),
  ("The {func} function has become too complex with too many if/else branches. Can you break it down into smaller, more focused functions?", "refactor"),
  ("I'm new to this codebase. Can you walk me through how {func} works and what role {file} plays in the architecture?", "explain"),
  ("We need comprehensive test coverage for the {func} function, including edge cases like {action} and error scenarios.", "test"),
  ("I know there's some code somewhere that handles {thing} but I can't find it. Can you search the codebase?", "explore"),
]
for _ in 0..<70 {
  for (template, label) in complex {
    examples.append(Example(text: sub(template), label: label))
  }
}

// Shuffle
examples.shuffle()

// Output as JSON
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted]
let data = try! encoder.encode(examples)
print(String(data: data, encoding: .utf8)!)

// Print stats to stderr
let counts = Dictionary(grouping: examples, by: \.label).mapValues(\.count)
for (label, count) in counts.sorted(by: { $0.key < $1.key }) {
  FileHandle.standardError.write("  \(label): \(count)\n".data(using: .utf8)!)
}
FileHandle.standardError.write("Total: \(examples.count)\n".data(using: .utf8)!)
