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

// MARK: - Staleness detection

@Test func detectsStaleToolchainImage() throws {
    let dir = try makeTempDir(files: [
        "state.json": """
        {
            "spawn-base:latest": {
                "digest": "sha256:aaa",
                "annotations": {
                    "org.opencontainers.image.created": "2026-02-14T12:00:00Z"
                }
            },
            "spawn-go:latest": {
                "digest": "sha256:bbb",
                "annotations": {
                    "org.opencontainers.image.created": "2026-02-13T10:00:00Z"
                }
            }
        }
        """
    ])
    #expect(ImageChecker.isStale("spawn-go:latest", storeRoot: dir) == true)
}

@Test func detectsFreshToolchainImage() throws {
    let dir = try makeTempDir(files: [
        "state.json": """
        {
            "spawn-base:latest": {
                "digest": "sha256:aaa",
                "annotations": {
                    "org.opencontainers.image.created": "2026-02-13T10:00:00Z"
                }
            },
            "spawn-rust:latest": {
                "digest": "sha256:bbb",
                "annotations": {
                    "org.opencontainers.image.created": "2026-02-14T12:00:00Z"
                }
            }
        }
        """
    ])
    #expect(ImageChecker.isStale("spawn-rust:latest", storeRoot: dir) == false)
}

@Test func staleReturnsFalseWhenBaseImageMissing() throws {
    let dir = try makeTempDir(files: [
        "state.json": """
        {
            "spawn-go:latest": {
                "digest": "sha256:bbb",
                "annotations": {
                    "org.opencontainers.image.created": "2026-02-13T10:00:00Z"
                }
            }
        }
        """
    ])
    #expect(ImageChecker.isStale("spawn-go:latest", storeRoot: dir) == false)
}

@Test func staleReturnsFalseForMalformedAnnotations() throws {
    let dir = try makeTempDir(files: [
        "state.json": """
        {
            "spawn-base:latest": {
                "digest": "sha256:aaa",
                "annotations": {
                    "org.opencontainers.image.created": "not-a-date"
                }
            },
            "spawn-cpp:latest": {
                "digest": "sha256:bbb",
                "annotations": {
                    "org.opencontainers.image.created": "also-not-a-date"
                }
            }
        }
        """
    ])
    #expect(ImageChecker.isStale("spawn-cpp:latest", storeRoot: dir) == false)
}

@Test func staleReturnsFalseForBaseImageItself() throws {
    let dir = try makeTempDir(files: [
        "state.json": """
        {
            "spawn-base:latest": {
                "digest": "sha256:aaa",
                "annotations": {
                    "org.opencontainers.image.created": "2026-02-14T12:00:00Z"
                }
            }
        }
        """
    ])
    #expect(ImageChecker.isStale("spawn-base:latest", storeRoot: dir) == false)
}

@Test func staleReturnsFalseWhenAnnotationsMissing() throws {
    let dir = try makeTempDir(files: [
        "state.json": """
        {
            "spawn-base:latest": {
                "digest": "sha256:aaa"
            },
            "spawn-go:latest": {
                "digest": "sha256:bbb"
            }
        }
        """
    ])
    #expect(ImageChecker.isStale("spawn-go:latest", storeRoot: dir) == false)
}
