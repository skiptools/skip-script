// Copyright 2023 Skip
//
// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org
import OSLog
import Foundation
import SkipScript // this import means we're testing SkipScript.JSContext()
import XCTest

// The difference between this test and JSContextTests is that
// SkipContextTests uses SkipScript.JSContext and
// JSContextTests uses JavaScriptCore.JSContext

@available(macOS 11, iOS 14, watchOS 7, tvOS 14, *)
class SkipContextTests : XCTestCase {
    let logger: Logger = Logger(subsystem: "test", category: "SkipContextTests")

    func testSkipContext() {
        let ctx = SkipScript.JSContext()
        let _ = ctx.context
    }

    func testFunctionCallback() throws {
        for _ in 0...100 {
            let ctx = JSContext()
            let add = JSValue(newFunctionIn: ctx) { ctx, obj, args in
                JSValue(double: args.reduce(0.0, { $0 + $1.toDouble() }), in: ctx)
            }
            for _ in 0...100 {

                let num = Double.random(in: 0.0...1000.0)
                XCTAssertEqual(num + 3.0, add.call(withArguments: [JSValue(double: 3.0, in: ctx), JSValue(double: num, in: ctx)]).toDouble())

                #if !SKIP
                try ctx.global.setProperty("add", add)
                let result = try XCTUnwrap(ctx.evaluateScript("add(1, 2, 3.4, 9.9)"))
                XCTAssertFalse(result.isUndefined)
                XCTAssertEqual(16.3, result.toDouble())
                #endif
            }
        }
    }

//    func testSlice() throws {
//        let jsc = JSContext()
//
//        let bytes: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8]
//        try jsc.global.setProperty("buffer", JSValue(newArrayBufferWithBytes: bytes, in: jsc))
//
//        XCTAssertEqual(try jsc.eval("buffer.slice(2, 4)").copyBytes().map(Array.init), [3, 4])
//    }

}
