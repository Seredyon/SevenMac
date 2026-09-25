import Foundation

final class ArchiveTests {
    var root: URL!
    func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("SevenMacTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        SevenZRunner.shared.binaryPath = source.appendingPathComponent("Resources/bin/7zz").path
    }
    func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func fixture(format: ArchiveFormat = .zip, ext: String = "apk", password: String = "") throws -> URL {
        let input = root.appendingPathComponent("input-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: input.appendingPathComponent("assets"), withIntermediateDirectories: true)
        try Data("original\r\nПривет 🌍\n".utf8).write(to: input.appendingPathComponent("assets/config.json"))
        try Data([0, 1, 2, 3]).write(to: input.appendingPathComponent("classes.dex"))
        let archive = root.appendingPathComponent(UUID().uuidString + "." + ext)
        var options = AddOptions(); options.format = format; options.password = password
        try SevenZRunner.shared.run(ArchiveService.addArguments(archive: archive, inputPaths: ["assets", "classes.dex"], options: options), password: password, workingDirectory: input)
        return archive
    }

    func testAPKEditPreservesOtherEntriesAndBackup() throws {
        let archive = try fixture()
        let original = try Data(contentsOf: archive)
        let document = try ArchiveEditor.load(archive: archive, path: "assets/config.json", password: "")
        expectEqual(document.text, "original\r\nПривет 🌍\n")
        let backup = try ArchiveEditor.save(document, text: "changed\r\nДо встречи 🌍\n")
        expectEqual(try Data(contentsOf: backup), original)
        expectEqual(try ArchiveEditor.load(archive: archive, path: document.path, password: "").text, "changed\r\nДо встречи 🌍\n")
        expectEqual(try ArchiveEditor.readEntry(archive: archive, path: "classes.dex", password: ""), Data([0, 1, 2, 3]))
    }

    func testRejectsStaleDocumentWithoutOverwriting() throws {
        let archive = try fixture()
        let document = try ArchiveEditor.load(archive: archive, path: "assets/config.json", password: "")
        try ArchiveEditor.save(document, text: "new")
        let newer = try Data(contentsOf: archive)
        expectThrows(try ArchiveEditor.save(document, text: "stale"))
        expectEqual(try Data(contentsOf: archive), newer)
    }

    func testBinaryReplacement() throws {
        let archive = try fixture()
        let document = try ArchiveEditor.load(archive: archive, path: "classes.dex", password: "")
        expectNil(document.text)
        let replacement = root.appendingPathComponent("replacement.dex")
        let data = Data([0, 255, 4, 2]); try data.write(to: replacement)
        try ArchiveEditor.save(document, replacement: replacement)
        expectEqual(try ArchiveEditor.readEntry(archive: archive, path: "classes.dex", password: ""), data)
    }

    func testEncryptedZIPAnd7zEditing() throws {
        for format in [ArchiveFormat.zip, .sevenZip] {
            let archive = try fixture(format: format, ext: format.rawValue, password: "test-pass")
            let document = try ArchiveEditor.load(archive: archive, path: "assets/config.json", password: "test-pass")
            try ArchiveEditor.save(document, text: "secret")
            expectEqual(try ArchiveEditor.load(archive: archive, path: document.path, password: "test-pass").text, "secret")
            let listing = try ArchiveService.list(archive: archive, password: "test-pass")
            expectTrue(listing.entries.first { $0.path == document.path }!.encrypted)
            expectThrows(try ArchiveEditor.readEntry(archive: archive, path: document.path, password: "wrong"))
        }
    }

    func testTAREditAndDelete() throws {
        let archive = try fixture(format: .tar, ext: "tar")
        let document = try ArchiveEditor.load(archive: archive, path: "assets/config.json", password: "")
        try ArchiveEditor.save(document, text: "tar edit")
        try ArchiveEditor.remove(archive: archive, paths: ["classes.dex"], password: "")
        expectFalse(try ArchiveService.list(archive: archive, password: "").entries.contains { $0.path == "classes.dex" })
    }

    func testFailedReplacementLeavesOriginal() throws {
        let archive = try fixture()
        let original = try Data(contentsOf: archive)
        let document = try ArchiveEditor.load(archive: archive, path: "assets/config.json", password: "")
        expectThrows(try ArchiveEditor.save(document, replacement: root.appendingPathComponent("missing")))
        expectEqual(try Data(contentsOf: archive), original)
    }

    func testUnsafePaths() {
        for path in ["../escape", "/absolute", "a/../../b", "a\\b", "C:/bad", "a\nb", "a//b", "@list", "a/./b", ""] {
            expectThrows(try ArchiveEditor.validatePath(path), path)
        }
        expectNoThrow(try ArchiveEditor.validatePath("assets/-literal [1]*?.txt"))
    }

    func testLiteralWildcardEntry() throws {
        let input = root.appendingPathComponent("literal")
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        for name in ["file*.txt", "file1.txt"] { try Data(name.utf8).write(to: input.appendingPathComponent(name)) }
        let archive = root.appendingPathComponent("literal.zip")
        var options = AddOptions(); options.format = .zip
        try SevenZRunner.shared.run(ArchiveService.addArguments(archive: archive, inputPaths: ["file*.txt", "file1.txt"], options: options), workingDirectory: input)
        let document = try ArchiveEditor.load(archive: archive, path: "file*.txt", password: "")
        try ArchiveEditor.save(document, text: "literal only")
        expectEqual(try ArchiveEditor.load(archive: archive, path: "file1.txt", password: "").text, "file1.txt")
    }

    func testFormatCapabilitiesAndVolumeSizes() {
        for ext in ["apk", "xapk", "docx", "whl", "cbz", "qcow2", "vhdx", "zst", "tar.gz", "7z.003"] {
            expectTrue(ArchiveService.isArchive(URL(fileURLWithPath: "test." + ext)), ext)
        }
        expectFalse(ArchiveService.canModify(URL(fileURLWithPath: "a.rar"), type: "Rar"))
        expectFalse(ArchiveService.canModify(URL(fileURLWithPath: "a.7z.001"), type: "7z"))
        expectTrue(ArchiveService.canModify(URL(fileURLWithPath: "a.apk"), type: "zip"))
        expectFalse(ArchiveService.isValidVolumeSize("0m"))
        expectTrue(ArchiveService.isValidVolumeSize("100m"))
    }

    func testParserPreservesWhitespaceAndFolderTotals() {
        let listing = ArchiveListParser.parse("Type = zip\n----------\nPath = folder/space .txt \nSize = 5\n\nPath = folder\nFolder = +\n\n")
        expectEqual(listing.entries.first?.path, "folder/space .txt ")
        expectEqual(BrowserModel.items(from: listing.entries, inner: "").first?.size, 5)
    }

    func testExtractLiteralWildcardOnly() throws {
        let input = root.appendingPathComponent("input")
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        for name in ["a*.txt", "abc.txt"] { try Data(name.utf8).write(to: input.appendingPathComponent(name)) }
        let archive = root.appendingPathComponent("extract.zip")
        var add = AddOptions(); add.format = .zip
        try SevenZRunner.shared.run(ArchiveService.addArguments(archive: archive, inputPaths: ["a*.txt", "abc.txt"], options: add), workingDirectory: input)
        let output = root.appendingPathComponent("output")
        let options = ExtractOptions(destination: output, selectedPaths: ["a*.txt"])
        try SevenZRunner.shared.run(ArchiveService.extractArguments(archive: archive, options: options))
        expectEqual(try FileManager.default.contentsOfDirectory(atPath: output.path), ["a*.txt"])
    }

    func testAtSignInputAndSingleEntryEdit() throws {
        let input = root.appendingPathComponent("@notes.txt")
        try Data("single file".utf8).write(to: input)
        let archive = root.appendingPathComponent("single.zip")
        var options = AddOptions(); options.format = .zip
        try SevenZRunner.shared.run(ArchiveService.addArguments(archive: archive, inputPaths: [input.lastPathComponent], options: options), workingDirectory: root)
        expectEqual(try ArchiveService.list(archive: archive, password: "").entries.first?.path, "@notes.txt")
        let regular = root.appendingPathComponent("single.txt")
        try Data("one".utf8).write(to: regular)
        let single = root.appendingPathComponent("one.zip")
        try SevenZRunner.shared.run(ArchiveService.addArguments(archive: single, inputPaths: [regular.path], options: options))
        let doc = try ArchiveEditor.load(archive: single, path: "single.txt", password: "")
        try ArchiveEditor.save(doc, text: "two")
        expectEqual(try ArchiveEditor.load(archive: single, path: "single.txt", password: "").text, "two")
    }

    func testPrimaryVolumes() throws {
        for pair in [("a.7z.002", "a.7z.001"), ("b.r03", "b.rar"), ("c.z02", "c.zip"), ("d.part03.rar", "d.part01.rar")] {
            let first = root.appendingPathComponent(pair.1)
            try Data().write(to: first)
            expectEqual(ArchiveService.primaryVolume(root.appendingPathComponent(pair.0)), first)
        }
    }

    func testTextLimit() throws {
        let archive = try fixture()
        let doc = try ArchiveEditor.load(archive: archive, path: "classes.dex", password: "")
        let replacement = root.appendingPathComponent("large.txt")
        try Data(repeating: 65, count: Int(ArchiveEditor.textLimit + 1)).write(to: replacement)
        try ArchiveEditor.save(doc, replacement: replacement)
        expectNil(try ArchiveEditor.load(archive: archive, path: "classes.dex", password: "").text)
        expectThrows(try ArchiveEditor.readEntry(archive: archive, path: "classes.dex", password: ""))
    }
}

private var failures = 0
private func fail(_ message: String, line: UInt) { failures += 1; print("FAIL line \(line): \(message)") }
private func expectEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, line: UInt = #line) {
    do { if try a() != b() { fail("values differ", line: line) } } catch { fail(error.localizedDescription, line: line) }
}
private func expectTrue(_ value: @autoclosure () throws -> Bool, _ message: String = "", line: UInt = #line) {
    do { if try !value() { fail("expected true " + message, line: line) } } catch { fail(error.localizedDescription, line: line) }
}
private func expectFalse(_ value: @autoclosure () throws -> Bool, line: UInt = #line) {
    do { if try value() { fail("expected false", line: line) } } catch { fail(error.localizedDescription, line: line) }
}
private func expectNil<T>(_ value: @autoclosure () throws -> T?, line: UInt = #line) {
    do { if try value() != nil { fail("expected nil", line: line) } } catch { fail(error.localizedDescription, line: line) }
}
private func expectThrows<T>(_ value: @autoclosure () throws -> T, _ message: String = "", line: UInt = #line) {
    do { _ = try value(); fail("expected error " + message, line: line) } catch {}
}
private func expectNoThrow<T>(_ value: @autoclosure () throws -> T, line: UInt = #line) {
    do { _ = try value() } catch { fail(error.localizedDescription, line: line) }
}

@main struct CheckRunner {
    static func main() {
        let suite = ArchiveTests()
        let tests: [(String, () throws -> Void)] = [
            ("testAPKEditPreservesOtherEntriesAndBackup", suite.testAPKEditPreservesOtherEntriesAndBackup),
            ("testRejectsStaleDocumentWithoutOverwriting", suite.testRejectsStaleDocumentWithoutOverwriting),
            ("testBinaryReplacement", suite.testBinaryReplacement),
            ("testEncryptedZIPAnd7zEditing", suite.testEncryptedZIPAnd7zEditing),
            ("testTAREditAndDelete", suite.testTAREditAndDelete),
            ("testFailedReplacementLeavesOriginal", suite.testFailedReplacementLeavesOriginal),
            ("testUnsafePaths", suite.testUnsafePaths),
            ("testLiteralWildcardEntry", suite.testLiteralWildcardEntry),
            ("testFormatCapabilitiesAndVolumeSizes", suite.testFormatCapabilitiesAndVolumeSizes),
            ("testParserPreservesWhitespaceAndFolderTotals", suite.testParserPreservesWhitespaceAndFolderTotals),
            ("testTextLimit", suite.testTextLimit),
            ("testExtractLiteralWildcardOnly", suite.testExtractLiteralWildcardOnly),
            ("testAtSignInputAndSingleEntryEdit", suite.testAtSignInputAndSingleEntryEdit),
            ("testPrimaryVolumes", suite.testPrimaryVolumes)
        ]
        for (name, test) in tests {
            let before = failures
            do { try suite.setUpWithError(); try test() } catch { fail(error.localizedDescription, line: 0) }
            try? suite.tearDownWithError()
            print("\(failures == before ? "PASS" : "FAIL") \(name)")
        }
        print("\(tests.count) checks, \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}
