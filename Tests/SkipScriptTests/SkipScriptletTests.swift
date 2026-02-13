// Copyright 2023–2025 Skip
// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception
import OSLog
import Foundation
import SkipScript // this import means we're testing SkipScript.JSContext()
import XCTest

@available(macOS 11, iOS 14, watchOS 7, tvOS 14, *)
class SkipScriptletTests : XCTestCase {
    let logger: Logger = Logger(subsystem: "test", category: "SkipScriptletTests")

    /// Creates a JSContext pre-configured with a `fs` namespace object providing
    /// cross-platform file system operations: tempDir, writeFile, readFile,
    /// fileExists, deleteFile, and appendFile.
    private func makeFileSystemContext() -> JSContext {
        let ctx = JSContext()
        let fs = JSValue(newObjectIn: ctx)

        // fs.tempDir() -> string
        fs.setObject(JSValue(newFunctionIn: ctx) { ctx, obj, args in
            return JSValue(string: FileManager.default.temporaryDirectory.path, in: ctx)
        }, forKeyedSubscript: "tempDir")

        // fs.writeFile(path, content) -> boolean
        fs.setObject(JSValue(newFunctionIn: ctx) { ctx, obj, args in
            guard args.count >= 2 else { return JSValue(bool: false, in: ctx) }
            let path: String = args[0].toString()
            let content: String = args[1].toString()
            do {
                // TODO: atomically: true needs https://github.com/skiptools/skip-foundation/pull/92
                try content.write(toFile: path, atomically: false, encoding: .utf8)
                return JSValue(bool: true, in: ctx)
            } catch {
                return JSValue(bool: false, in: ctx)
            }
        }, forKeyedSubscript: "writeFile")

        // fs.readFile(path) -> string | null
        fs.setObject(JSValue(newFunctionIn: ctx) { ctx, obj, args in
            guard args.count >= 1 else { return JSValue(nullIn: ctx) }
            let path: String = args[0].toString()
            do {
                let url = URL(fileURLWithPath: path, isDirectory: false)
                let content = try String(contentsOf: url, encoding: .utf8)
                return JSValue(string: content, in: ctx)
            } catch {
                return JSValue(nullIn: ctx)
            }
        }, forKeyedSubscript: "readFile")

        // fs.fileExists(path) -> boolean
        fs.setObject(JSValue(newFunctionIn: ctx) { ctx, obj, args in
            guard args.count >= 1 else { return JSValue(bool: false, in: ctx) }
            let path: String = args[0].toString()
            return JSValue(bool: FileManager.default.fileExists(atPath: path), in: ctx)
        }, forKeyedSubscript: "fileExists")

        // fs.deleteFile(path) -> boolean
        fs.setObject(JSValue(newFunctionIn: ctx) { ctx, obj, args in
            guard args.count >= 1 else { return JSValue(bool: false, in: ctx) }
            let path: String = args[0].toString()
            do {
                try FileManager.default.removeItem(atPath: path)
                return JSValue(bool: true, in: ctx)
            } catch {
                return JSValue(bool: false, in: ctx)
            }
        }, forKeyedSubscript: "deleteFile")

        // fs.appendFile(path, content) -> boolean
        fs.setObject(JSValue(newFunctionIn: ctx) { ctx, obj, args in
            guard args.count >= 2 else { return JSValue(bool: false, in: ctx) }
            let path: String = args[0].toString()
            let content: String = args[1].toString()
            do {
                let url = URL(fileURLWithPath: path, isDirectory: false)
                if FileManager.default.fileExists(atPath: path) {
                    let existing = try String(contentsOf: url, encoding: .utf8)
                    // TODO: atomically: true needs https://github.com/skiptools/skip-foundation/pull/92
                    try (existing + content).write(toFile: path, atomically: false, encoding: .utf8)
                } else {
                    // TODO: atomically: true needs https://github.com/skiptools/skip-foundation/pull/92
                    try content.write(toFile: path, atomically: false, encoding: .utf8)
                }
                return JSValue(bool: true, in: ctx)
            } catch {
                return JSValue(bool: false, in: ctx)
            }
        }, forKeyedSubscript: "appendFile")

        ctx.setObject(fs, forKeyedSubscript: "fs")
        return ctx
    }

    /// Creates a JSContext pre-configured with a `net` namespace object providing
    /// asynchronous network operations: fetch and fetchStatus.
    private func makeNetworkContext() -> JSContext {
        let ctx = JSContext()
        let net = JSValue(newObjectIn: ctx)

        // net.fetch(url) -> Promise<string>
        net.setObject(JSValue(newAsyncFunctionIn: ctx) { ctx, obj, args in
            guard args.count >= 1 else {
                return JSValue(string: "", in: ctx)
            }
            let urlString: String = args[0].toString()
            guard let url = URL(string: urlString) else {
                return JSValue(string: "", in: ctx)
            }
            let (data, _) = try await URLSession.shared.data(from: url)
            let body = String(data: data, encoding: .utf8) ?? ""
            return JSValue(string: body, in: ctx)
        }, forKeyedSubscript: "fetch")

        // net.fetchStatus(url) -> Promise<number>
        net.setObject(JSValue(newAsyncFunctionIn: ctx) { ctx, obj, args in
            guard args.count >= 1 else {
                return JSValue(double: -1.0, in: ctx)
            }
            let urlString: String = args[0].toString()
            guard let url = URL(string: urlString) else {
                return JSValue(double: -1.0, in: ctx)
            }
            let (_, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse {
                return JSValue(double: Double(httpResponse.statusCode), in: ctx)
            }
            return JSValue(double: -1.0, in: ctx)
        }, forKeyedSubscript: "fetchStatus")

        ctx.setObject(net, forKeyedSubscript: "net")
        return ctx
    }

    /// Creates a JSContext pre-configured with a `device` namespace object providing
    /// cross-platform device and environment information properties and functions.
    private func makeDeviceInfoContext() -> JSContext {
        let ctx = JSContext()
        let device = JSValue(newObjectIn: ctx)

        let isAndroidDevice = ProcessInfo.processInfo.environment["ANDROID_ROOT"] != nil

        // Determine OS name at runtime to work on both platforms
        var osName = "unknown"
        if isAndroidDevice {
            osName = "Android"
        } else {
            #if os(macOS)
            osName = "macOS"
            #elseif os(iOS)
            osName = "iOS"
            #elseif os(tvOS)
            osName = "tvOS"
            #elseif os(watchOS)
            osName = "watchOS"
            #endif
        }

        // Static properties
        device.setObject(JSValue(string: osName, in: ctx), forKeyedSubscript: "osName")
        device.setObject(JSValue(string: ProcessInfo.processInfo.operatingSystemVersionString, in: ctx), forKeyedSubscript: "osVersion")
        device.setObject(JSValue(double: Double(ProcessInfo.processInfo.processorCount), in: ctx), forKeyedSubscript: "processorCount")
        device.setObject(JSValue(string: ProcessInfo.processInfo.hostName, in: ctx), forKeyedSubscript: "hostName")
        device.setObject(JSValue(bool: isAndroidDevice, in: ctx), forKeyedSubscript: "isAndroid")
        device.setObject(JSValue(string: ProcessInfo.processInfo.globallyUniqueString, in: ctx), forKeyedSubscript: "uniqueId")
        device.setObject(JSValue(string: FileManager.default.temporaryDirectory.path, in: ctx), forKeyedSubscript: "tempDir")

        // device.getEnv(key) -> string
        device.setObject(JSValue(newFunctionIn: ctx) { ctx, obj, args in
            guard args.count >= 1 else { return JSValue(string: "", in: ctx) }
            let key: String = args[0].toString()
            let value = ProcessInfo.processInfo.environment[key] ?? ""
            return JSValue(string: value, in: ctx)
        }, forKeyedSubscript: "getEnv")

        ctx.setObject(device, forKeyedSubscript: "device")
        return ctx
    }

    // MARK: - File System Tests

    func testFileSystemFunctions() async throws {
        let ctx = makeFileSystemContext()

        // Test: complete file lifecycle from JavaScript
        let result = ctx.evaluateScript("""
            var dir = fs.tempDir();
            var testFile = dir + '/skip_scriptlet_fs_' + Date.now() + '.txt';

            // Write a new file
            if (!fs.writeFile(testFile, 'Hello from JavaScript!'))
                throw new Error('writeFile failed');

            // Verify it exists
            if (!fs.fileExists(testFile))
                throw new Error('File should exist after writing');

            // Read it back and verify content
            var content = fs.readFile(testFile);
            if (content !== 'Hello from JavaScript!')
                throw new Error('Content mismatch: ' + content);

            // Append to the file
            if (!fs.appendFile(testFile, ' More text.'))
                throw new Error('appendFile failed');

            // Read the appended content
            var updated = fs.readFile(testFile);
            if (updated !== 'Hello from JavaScript! More text.')
                throw new Error('Appended content mismatch: ' + updated);

            // Overwrite the file with new content
            if (!fs.writeFile(testFile, 'Replaced.'))
                throw new Error('overwrite writeFile failed');
            var replaced = fs.readFile(testFile);
            if (replaced !== 'Replaced.')
                throw new Error('Replaced content mismatch: ' + replaced);

            // Delete the file
            if (!fs.deleteFile(testFile))
                throw new Error('deleteFile failed');

            // Verify it is gone
            if (fs.fileExists(testFile))
                throw new Error('File should not exist after deletion');

            // Reading a deleted file should return null
            var gone = fs.readFile(testFile);
            if (gone !== null)
                throw new Error('readFile of deleted file should be null');

            'success';
        """)
        XCTAssertNil(ctx.exception, "JS exception: \(ctx.exception?.toString() ?? "")")
        XCTAssertEqual("success", result?.toString())
    }

    // MARK: - Async Network Tests

    func testAsyncNetworkFunctions() async throws {
        let ctx = makeNetworkContext()

        // Test 1: Fetch a well-known page and verify its content
        do {
            let promise = try XCTUnwrap(ctx.evaluateScript("net.fetch('https://example.com')"))
            XCTAssertNil(ctx.exception, "JS exception from net.fetch: \(ctx.exception?.toString() ?? "")")
            let result = try await ctx.awaitPromise(promise)
            let body: String = result.toString()
            XCTAssertTrue(body.contains("Example Domain"), "Response should contain 'Example Domain'")
        }

        // Test 2: Verify HTTP status code
        do {
            let promise = try XCTUnwrap(ctx.evaluateScript("net.fetchStatus('https://example.com')"))
            XCTAssertNil(ctx.exception, "JS exception from net.fetchStatus: \(ctx.exception?.toString() ?? "")")
            let result = try await ctx.awaitPromise(promise)
            XCTAssertEqual(200.0, result.toDouble())
        }

        // Test 3: Chain async calls in JavaScript using an async IIFE
        do {
            let promise = try XCTUnwrap(ctx.evaluateScript("""
                (async function() {
                    var body = await net.fetch('https://example.com');
                    var status = await net.fetchStatus('https://example.com');
                    var result = {};
                    result.hasTitle = body.indexOf('<title>') !== -1;
                    result.hasBody = body.length > 0;
                    result.statusOk = status === 200;
                    return result.hasTitle + '|' + result.hasBody + '|' + result.statusOk;
                })()
            """))
            XCTAssertNil(ctx.exception, "JS exception from async IIFE: \(ctx.exception?.toString() ?? "")")
            let result = try await ctx.awaitPromise(promise)
            XCTAssertEqual("true|true|true", result.toString())
        }
    }

    // MARK: - Device Info Tests

    func testDeviceInfoFuctions() async throws {
        let ctx = makeDeviceInfoContext()

        // Test: query and validate device properties from JavaScript
        let result = ctx.evaluateScript("""
            // Verify all properties exist and have expected types
            if (typeof device.osName !== 'string' || device.osName.length === 0)
                throw new Error('osName should be a non-empty string, got: ' + device.osName);

            if (typeof device.osVersion !== 'string' || device.osVersion.length === 0)
                throw new Error('osVersion should be a non-empty string, got: ' + device.osVersion);

            if (typeof device.processorCount !== 'number' || device.processorCount < 1)
                throw new Error('processorCount should be >= 1, got: ' + device.processorCount);

            if (typeof device.hostName !== 'string')
                throw new Error('hostName should be a string, got: ' + typeof device.hostName);

            if (typeof device.isAndroid !== 'boolean')
                throw new Error('isAndroid should be a boolean, got: ' + typeof device.isAndroid);

            if (typeof device.uniqueId !== 'string' || device.uniqueId.length === 0)
                throw new Error('uniqueId should be a non-empty string');

            if (typeof device.tempDir !== 'string' || device.tempDir.length === 0)
                throw new Error('tempDir should be a non-empty string');

            // Platform-specific validation
            if (device.isAndroid) {
                if (device.osName !== 'Android')
                    throw new Error('osName should be Android on Android, got: ' + device.osName);
            } else {
                var knownPlatforms = ['macOS', 'iOS', 'tvOS', 'watchOS'];
                if (knownPlatforms.indexOf(device.osName) === -1)
                    throw new Error('Unexpected osName on Apple platform: ' + device.osName);
            }

            // Test the getEnv function returns a string
            var envResult = device.getEnv('PATH');
            if (typeof envResult !== 'string')
                throw new Error('getEnv should return a string, got: ' + typeof envResult);

            'success';
        """)
        XCTAssertNil(ctx.exception, "JS exception: \(ctx.exception?.toString() ?? "")")
        XCTAssertEqual("success", result?.toString())

        // Test: use device info to construct a platform summary in JS
        let summary = ctx.evaluateScript("""
            var parts = [];
            parts.push(device.osName + ' ' + device.osVersion);
            parts.push(device.processorCount + ' cores');
            parts.push('host: ' + device.hostName);
            parts.join(', ');
        """)
        XCTAssertNil(ctx.exception, "JS exception: \(ctx.exception?.toString() ?? "")")
        let summaryStr = try XCTUnwrap(summary?.toString())
        logger.info("Device summary from JS: \(summaryStr)")
        XCTAssertTrue(summaryStr.contains("cores"), "Summary should mention cores: \(summaryStr)")

        // Test: use device info for conditional logic in JS
        let conditional = ctx.evaluateScript("""
            var greeting;
            if (device.isAndroid) {
                greeting = 'Hello from Android ' + device.osVersion;
            } else {
                greeting = 'Hello from ' + device.osName + ' ' + device.osVersion;
            }
            greeting;
        """)
        XCTAssertNil(ctx.exception, "JS exception: \(ctx.exception?.toString() ?? "")")
        let greetingStr = try XCTUnwrap(conditional?.toString())
        XCTAssertTrue(greetingStr.hasPrefix("Hello from"), "Greeting should start with 'Hello from': \(greetingStr)")
    }
}
