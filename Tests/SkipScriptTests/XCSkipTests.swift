// Copyright 2023 Skip
//
// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org
#if os(macOS)
import SkipTest

/// This test case will run the transpiled tests for the Skip module.
@available(macOS 13, macCatalyst 16, *)
final class XCSkipTests: XCTestCase, XCGradleHarness {
    public func testSkipModule() async throws {
        // Run the transpiled tests for the current test module.
        // The tests will run in the Robolectric Android simulation environment.
        // Device or emulator tests can be run against an `adb devices` identifier
        // by specifying it in the `device` parameter or the
        // `ANDROID_SERIAL` environment variable in the scheme's Run settings.
        // Note that it isn't currently possible to filter the tests to run.
        try await runGradleTests(device: .none)
    }
}
#endif
