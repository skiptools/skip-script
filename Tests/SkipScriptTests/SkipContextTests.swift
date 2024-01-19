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

    func testCallFunctionNoArgs() throws {
        // we run this many times in order to ensure that neither JavaScript not Java GC will cause the function to be missing
        for i in 1...10 {
            let ctx = JSContext()
            for j in 1...1_000 {
                let fun = JSValue(newFunctionIn: ctx) { ctx, obj, args in
                    JSValue(double: Double(i * j), in: ctx)
                }

                XCTAssertEqual(Double(i * j), try fun.call(withArguments: []).toDouble(), "#\(i)-\(j) failure") // e.g., 1-55577
            }
        }
    }

    func testCallFunction() throws {
        let ctx = JSContext()
        let sum = JSValue(newFunctionIn: ctx) { ctx, obj, args in
            JSValue(double: args.reduce(0.0, { $0 + $1.toDouble() }), in: ctx)
        }
        let num = Double.random(in: 0.0...1000.0)
        let args = [JSValue(double: 3.0, in: ctx), JSValue(double: num, in: ctx)]
        XCTAssertEqual(num + 3.0, try sum.call(withArguments: args).toDouble())

        #if !SKIP
        try ctx.global.setProperty("sum", sum)
        let result = try XCTUnwrap(ctx.evaluateScript("sum(1, 2, 3.4, 9.9)"))
        XCTAssertFalse(result.isUndefined)
        XCTAssertEqual(16.3, result.toDouble())
        #endif
    }
}
