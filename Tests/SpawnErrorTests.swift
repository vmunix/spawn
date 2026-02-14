import Testing

@testable import spawn

@Suite struct SpawnErrorTests {
    @Test func containerFailedIncludesStatusCode() {
        let error = SpawnError.containerFailed(status: 42)
        #expect(error.description == "Container exited with status 42")
    }

    @Test func containerFailedWithZeroStatus() {
        let error = SpawnError.containerFailed(status: 0)
        #expect(error.description == "Container exited with status 0")
    }

    @Test func containerFailedWithNegativeStatus() {
        let error = SpawnError.containerFailed(status: -1)
        #expect(error.description == "Container exited with status -1")
    }

    @Test func containerNotFoundHasExpectedFixedMessage() {
        let error = SpawnError.containerNotFound
        #expect(error.description == "Container CLI not found. Install Apple's container tool first.")
    }

    @Test func imageNotFoundIncludesImageNameAndHint() {
        let error = SpawnError.imageNotFound(image: "spawn-rust:latest", hint: "Run 'spawn build' first.")
        #expect(error.description == "Image 'spawn-rust:latest' not found. Run 'spawn build' first.")
    }

    @Test func imageNotFoundWithEmptyHint() {
        let error = SpawnError.imageNotFound(image: "myimage:v1", hint: "")
        #expect(error.description == "Image 'myimage:v1' not found. ")
    }

    @Test func runtimeErrorIncludesMessage() {
        let error = SpawnError.runtimeError("Something went wrong")
        #expect(error.description == "Something went wrong")
    }

    @Test func runtimeErrorWithEmptyMessage() {
        let error = SpawnError.runtimeError("")
        #expect(error.description == "")
    }

    @Test func conformsToErrorProtocol() {
        let error: any Error = SpawnError.runtimeError("test")
        #expect(error is SpawnError)
    }
}
