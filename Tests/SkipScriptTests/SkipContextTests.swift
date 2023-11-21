// Copyright 2023 Skip
//
// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org
import OSLog
import Foundation
import SkipScript
import XCTest

@available(macOS 11, iOS 14, watchOS 7, tvOS 14, *)
class SkipContextTests : XCTestCase {
    let logger: Logger = Logger(subsystem: "test", category: "SkipContextTests")

    func testSkipContext() {
        let ctx = SkipScript.JSContext()
        let _ = ctx.context

    }
}
