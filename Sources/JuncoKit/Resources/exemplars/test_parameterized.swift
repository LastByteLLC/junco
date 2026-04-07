// Parameterized test with @Test arguments for multiple inputs
import Testing

@Suite("Email Validation")
struct EmailValidationTests {
    @Test("Valid emails are accepted", arguments: [
        "user@example.com",
        "name.surname@domain.org",
        "dev+tag@company.io"
    ])
    func validEmail(_ email: String) {
        #expect(isValidEmail(email))
    }

    @Test("Invalid emails are rejected", arguments: [
        "",
        "no-at-sign",
        "@missing-local.com",
        "spaces in@email.com"
    ])
    func invalidEmail(_ email: String) {
        #expect(!isValidEmail(email))
    }
}

func isValidEmail(_ email: String) -> Bool {
    let pattern = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
    return email.range(of: pattern, options: .regularExpression) != nil
}
