import Foundation
import Testing
@testable import UsageCore

@Suite struct UpdateTests {
    @Test func numericVersionsAndPreviewTags() {
        #expect(ReleaseVersion("v2.10.0")! > ReleaseVersion("2.9.9")!)
        #expect(ReleaseVersion("2.1") == ReleaseVersion("2.1.0"))
        for invalid in ["2.1.0-beta", "2..1", "release2", "", "9999999999999999999999999", "２.１.０"] {
            #expect(ReleaseVersion(invalid) == nil)
        }
    }
    private func fixture(tag: String = "v2.2.0", page: String = "https://github.com/WangSH-666/codex-usage-widget/releases/tag/v2.2.0", draft: Bool = false, prerelease: Bool = false, assetURL: String? = nil) throws -> Data {
        let url = assetURL ?? "https://github.com/WangSH-666/codex-usage-widget/releases/download/v2.2.0/Codex-Usage-2.2.0-macOS-arm64.zip"
        return try JSONSerialization.data(withJSONObject: ["tag_name":tag, "body":"新增检查更新。", "html_url":page, "draft":draft, "prerelease":prerelease,
            "assets":[["name":"Codex-Usage-2.2.0-macOS-arm64.zip", "browser_download_url":url]]])
    }
    @Test func newerReleaseChoosesMatchingBinaryAndNotes() throws {
        let release = try ReleaseUpdate.decode(fixture(), statusCode: 200, architecture: "arm64")
        #expect(release.isNewer(than: "2.1.0"))
        #expect(!release.isNewer(than: "2.2.0"))
        #expect(!release.isNewer(than: "2.3.0"))
        #expect(release.downloadURL?.lastPathComponent == "Codex-Usage-2.2.0-macOS-arm64.zip")
        #expect(release.notes == "新增检查更新。")
        let otherArchitecture = try ReleaseUpdate.decode(fixture(), statusCode: 200, architecture: "x86_64")
        #expect(otherArchitecture.downloadURL == nil)
    }
    @Test func invalidAndUnpublishedReleasesAreRejected() throws {
        for data in [try fixture(draft: true), try fixture(prerelease: true), try fixture(tag: "v2.2.0-beta"), try fixture(page: "https://example.com/update"), Data("{}".utf8)] {
            #expect(throws: UpdateError.self) { try ReleaseUpdate.decode(data, statusCode: 200, architecture: "arm64") }
        }
    }
    @Test func downloadLinksStayWithinThisRepository() throws {
        for url in ["http://github.com/WangSH-666/codex-usage-widget/releases/download/v2.2.0/app.zip", "https://example.com/app.zip", "https://github.com/other/repo/releases/download/v2.2.0/app.zip"] {
            let release = try ReleaseUpdate.decode(fixture(assetURL: url), statusCode: 200, architecture: "arm64")
            #expect(release.downloadURL == nil)
        }
    }
    @Test func unavailableServerResponsesAreHandled() {
        for status in [403,404,429,500] {
            #expect(throws: UpdateError.self) { try ReleaseUpdate.decode(Data(), statusCode: status, architecture: "arm64") }
        }
    }
}
