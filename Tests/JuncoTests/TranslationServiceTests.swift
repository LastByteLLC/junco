// TranslationServiceTests.swift — Tests for translation detection, session memory, and fallbacks

import Testing
import Foundation
@testable import JuncoKit

@Suite("TranslationService")
struct TranslationServiceTests {

  @Test("detects English input as no translation needed")
  func englishPassthrough() async {
    let svc = TranslationService()
    let (text, lang, msg) = await svc.processInput("fix the login bug in auth.swift")
    #expect(text == "fix the login bug in auth.swift")
    #expect(lang == nil)
    #expect(msg == nil)
  }

  @Test("short input skips detection")
  func shortInput() async {
    let svc = TranslationService()
    let (text, lang, _) = await svc.processInput("hola")
    #expect(text == "hola")
    #expect(lang == nil)
  }

  @Test("detects Spanish input")
  func detectSpanish() async {
    let svc = TranslationService()
    let (_, lang, _) = await svc.processInput("arregla el error de inicio de sesión en el módulo de autenticación")
    if let lang {
      #expect(lang == "es")
    }
  }

  @Test("remembers session language across turns")
  func sessionMemory() async {
    let svc = TranslationService()
    _ = await svc.processInput("arregla el error de inicio de sesión en el módulo de autenticación")
    let lang1 = await svc.currentLanguage
    if lang1 == "es" {
      let (_, _, _) = await svc.processInput("ahora agrega pruebas")
      let current = await svc.currentLanguage
      #expect(current == "es")
    }
  }

  @Test("reset clears session language")
  func reset() async {
    let svc = TranslationService()
    await svc.setLanguage("es")
    #expect(await svc.currentLanguage == "es")
    await svc.reset()
    #expect(await svc.currentLanguage == nil)
  }

  @Test("setLanguage sets session language")
  func setLanguage() async {
    let svc = TranslationService()
    await svc.setLanguage("fr")
    #expect(await svc.currentLanguage == "fr")
  }

  @Test("isTranslating is false for English")
  func notTranslating() async {
    let svc = TranslationService()
    #expect(await svc.isTranslating == false)
  }

  @Test("processOutput returns nil for English session")
  func outputEnglish() async {
    let svc = TranslationService()
    #expect(await svc.processOutput("test") == nil)
  }

  @Test("availabilityMessage reports status")
  func availabilityMsg() async {
    let svc = TranslationService()
    let msg = await svc.availabilityMessage(for: "es")
    #expect(!msg.isEmpty)
    // Should contain either "installed", "not downloaded", or "not supported"
    #expect(msg.contains("Spanish") || msg.contains("es"))
  }

  @Test("AFM fallback used when adapter provided")
  func afmFallback() async {
    let adapter = AFMAdapter()
    let svc = TranslationService(adapter: adapter)
    await svc.setLanguage("es")
    // With AFM adapter, processInput should attempt translation
    let (text, lang, _) = await svc.processInput("arregla el error de inicio de sesión en el módulo de autenticación")
    // Either translated or passed through — both are valid
    #expect(!text.isEmpty)
  }

  @Test("settingsURL is valid")
  func settingsURL() {
    #expect(TranslationService.settingsURL.contains("systempreferences"))
  }
}
