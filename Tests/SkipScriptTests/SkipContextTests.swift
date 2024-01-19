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
        let ctx = JSContext()
        let fun = JSValue(newFunctionIn: ctx) { ctx, obj, args in
            JSValue(double: .pi, in: ctx)
        }

        XCTAssertEqual(.pi, try fun.call(withArguments: []).toDouble())
    }

    func testCallFunction() throws {
        // we run this many times in order to ensure that neither JavaScript not Java GC will cause the function to be missing
        for i in 1...10 {
            let ctx = JSContext()
            for j in 1...1_00 {
                let sum = JSValue(newFunctionIn: ctx) { ctx, obj, args in
                    JSValue(double: args.reduce(0.0, { $0 + $1.toDouble() }), in: ctx)
                }
                for k in 1...1_00 {
                    let num = Double.random(in: 0.0...1000.0)
                    let args = [JSValue(double: 3.0, in: ctx), JSValue(double: num, in: ctx)]
                    XCTAssertEqual(num + 3.0, try sum.call(withArguments: args).toDouble(), "\(i)-\(j)-\(k) failure")
                }
            }
        }
    }

    func testFunctionProperty() throws {
        let ctx = JSContext()
        let sum = JSValue(newFunctionIn: ctx) { ctx, obj, args in
            JSValue(double: args.reduce(0.0, { $0 + $1.toDouble() }), in: ctx)
        }

        ctx.setObject(sum, forKeyedSubscript: "sum")
        XCTAssertNil(ctx.exception)


        //do {
        //    let r0 = try XCTUnwrap(ctx.evaluateScript("sum('1')"))
        //    XCTAssertNil(ctx.exception)
        //    XCTAssertFalse(r0.isUndefined)
        //    XCTAssertEqual(1.0, r0.toDouble())
        //}

        //do {
        //    let r1 = try XCTUnwrap(ctx.evaluateScript("sum(1)"))
        //    XCTAssertNil(ctx.exception)
        //    XCTAssertFalse(r1.isUndefined)
        //    XCTAssertEqual(1.0, r1.toDouble())
        //}

        //do {
        //    let r2 = try XCTUnwrap(ctx.evaluateScript("sum(1, 2, 3.4, 9.9)"))
        //    XCTAssertNil(ctx.exception)
        //    XCTAssertFalse(r2.isUndefined)
        //    XCTAssertEqual(16.3, r2.toDouble())
        //}

        XCTAssertTrue(sum.isFunction)
    }
}
