import Foundation
import Testing
@testable import ScotchDomain

struct ProgramSettingsTests {
    @Test func parsesQuotedArgumentString() {
        let settings = ProgramSettings(
            locale: .auto,
            arguments: #"--flag "quoted value" 'single quoted' plain\ arg"#,
            environment: [:]
        )

        let parsed = settings.parsedArguments()
        #expect(parsed == ["--flag", "quoted value", "single quoted", "plain arg"])
    }

    @Test func mergesEnvironmentWithLocaleAndExtraOverrides() {
        let settings = ProgramSettings(
            locale: .japanese,
            arguments: "",
            environment: [
                "A": "1",
                "B": "2"
            ]
        )

        let merged = settings.effectiveEnvironment(extra: ["B": "override", "C": "3"])
        #expect(merged["LC_ALL"] == ProgramLocale.japanese.rawValue)
        #expect(merged["A"] == "1")
        #expect(merged["B"] == "override")
        #expect(merged["C"] == "3")
    }

    @Test func codableRoundtripUsesLocaleRawValue() throws {
        let settings = ProgramSettings(
            locale: .korean,
            arguments: "-windowed",
            environment: ["FOO": "BAR"]
        )

        let data = try PropertyListEncoder().encode(settings)
        let decoded = try PropertyListDecoder().decode(ProgramSettings.self, from: data)
        #expect(decoded == settings)
    }
}

