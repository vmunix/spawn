import Testing

@testable import spawn

@Test func parsesEnvFile() {
    let content = """
        ANTHROPIC_API_KEY=sk-ant-123
        OPENAI_API_KEY=sk-456
        """
    let env = EnvLoader.parse(content)
    #expect(env["ANTHROPIC_API_KEY"] == "sk-ant-123")
    #expect(env["OPENAI_API_KEY"] == "sk-456")
}

@Test func ignoresCommentsAndEmptyLines() {
    let content = """
        # This is a comment
        KEY=value

        # Another comment
        KEY2=value2
        """
    let env = EnvLoader.parse(content)
    #expect(env.count == 2)
    #expect(env["KEY"] == "value")
}

@Test func handlesQuotedValues() {
    let content = """
        KEY="value with spaces"
        KEY2='single quoted'
        """
    let env = EnvLoader.parse(content)
    #expect(env["KEY"] == "value with spaces")
    #expect(env["KEY2"] == "single quoted")
}

@Test func validatesRequiredVars() {
    let env = ["ANTHROPIC_API_KEY": "sk-123"]
    let missing = EnvLoader.validateRequired(["ANTHROPIC_API_KEY", "OTHER_KEY"], in: env)
    #expect(missing == ["OTHER_KEY"])
}

@Test func validationPassesWhenAllPresent() {
    let env = ["ANTHROPIC_API_KEY": "sk-123"]
    let missing = EnvLoader.validateRequired(["ANTHROPIC_API_KEY"], in: env)
    #expect(missing.isEmpty)
}

@Test func parseKeyValueSplitsOnFirstEquals() {
    let result = EnvLoader.parseKeyValue("FOO=bar")
    #expect(result?.key == "FOO")
    #expect(result?.value == "bar")
}

@Test func parseKeyValueReturnsNilWithoutEquals() {
    let result = EnvLoader.parseKeyValue("FOOBAR")
    #expect(result == nil)
}

@Test func parseKeyValueHandlesEqualsInValue() {
    let result = EnvLoader.parseKeyValue("FOO=bar=baz")
    #expect(result?.key == "FOO")
    #expect(result?.value == "bar=baz")
}

@Test func parseKeyValueHandlesEmptyValue() {
    let result = EnvLoader.parseKeyValue("FOO=")
    #expect(result?.key == "FOO")
    #expect(result?.value == "")
}
