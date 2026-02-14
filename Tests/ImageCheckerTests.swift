import Foundation
import Testing

@testable import spawn

@Test func findsExistingImage() throws {
    let dir = try makeTempDir(files: [
        "state.json": """
        {
            "spawn-base:latest": {
                "mediaType": "application/vnd.oci.image.index.v1+json",
                "digest": "sha256:abc123",
                "size": 375
            }
        }
        """
    ])
    let exists = ImageChecker.imageExists("spawn-base:latest", storeRoot: dir)
    #expect(exists == true)
}

@Test func returnsFalseForMissingImage() throws {
    let dir = try makeTempDir(files: [
        "state.json": """
        {
            "spawn-base:latest": {
                "mediaType": "application/vnd.oci.image.index.v1+json",
                "digest": "sha256:abc123",
                "size": 375
            }
        }
        """
    ])
    let exists = ImageChecker.imageExists("spawn-rust:latest", storeRoot: dir)
    #expect(exists == false)
}

@Test func returnsFalseWhenNoStateFile() throws {
    let dir = try makeTempDir(files: [:])
    let exists = ImageChecker.imageExists("spawn-base:latest", storeRoot: dir)
    #expect(exists == false)
}

@Test func returnsFalseForCorruptStateFile() throws {
    let dir = try makeTempDir(files: [
        "state.json": "not json"
    ])
    let exists = ImageChecker.imageExists("spawn-base:latest", storeRoot: dir)
    #expect(exists == false)
}

@Test func returnsFalseWhenStoreRootIsNil() {
    let exists = ImageChecker.imageExists("spawn-base:latest", storeRoot: nil)
    #expect(exists == false)
}
