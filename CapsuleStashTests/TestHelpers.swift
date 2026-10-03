import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import CapsuleStash

/// 테스트 공용 픽스처 (임시 폴더 격리 — 실제 사용자 데이터를 건드리지 않는다).
enum TestHelpers {
    static func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func makeTestPNG(width: Int, height: Int) throws -> URL {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = context.makeImage()!
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }

    static func imageSize(at url: URL) -> (Int, Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return (image.width, image.height)
    }

    @MainActor
    static func makeStore() -> DataStore {
        DataStore(samples: false, loadSeeds: true, persist: false)
    }

    @MainActor
    static func makeStoreWithProject(dir: URL) throws -> (DataStore, Project) {
        let store = DataStore(samples: false, loadSeeds: false, persist: false, attachmentBase: dir)
        store.createWorkspace(name: "W")
        guard let ws = store.workspaces.first,
              let project = store.createProject(title: "P", in: ws.id) else {
            throw XCTSkip("Workspace·Project 필요")
        }
        return (store, project)
    }
}
