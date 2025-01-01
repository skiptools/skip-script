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
        // we run this many times in order to ensure that neither JavaScript GC nor Java GC will cause the function's struct/class being freed
        for i in 1...100 {
            let ctx = JSContext()
            for j in 1...100 {
                do {
                    let sum = JSValue(newFunctionIn: ctx) { ctx, obj, args in
                        JSValue(double: args.reduce(Double(i), { $0 + $1.toDouble() }), in: ctx)
                    }
                    ctx.setObject(sum, forKeyedSubscript: "sum")
                }
                for k in 1...100 {
                    let num = Double.random(in: 0.0...1000.0)
                    let args = [JSValue(double: Double(j), in: ctx), JSValue(double: Double(k), in: ctx), JSValue(double: num, in: ctx)]
                    let result = try ctx.objectForKeyedSubscript("sum").call(withArguments: args)
                    XCTAssertEqual(Double(i) + Double(j) + Double(k) + num, result.toDouble(), "\(i)-\(j)-\(k) failure")
                }
            }
        }
    }

    func testStringArgsFunctionProperty() throws {
        let ctx = JSContext()
        let stringify = JSValue(newFunctionIn: ctx) { ctx, obj, args in
            JSValue(string: args.compactMap({ $0.toString() }).joined(), in: ctx)
        }

        ctx.setObject(stringify, forKeyedSubscript: "stringify")
        XCTAssertEqual("", ctx.evaluateScript("stringify()")?.toString())

        XCTAssertEqual("", ctx.evaluateScript("stringify('')")?.toString())
        XCTAssertEqual("ABC", ctx.evaluateScript("stringify('A', 'BC')")?.toString())
        XCTAssertEqual("true12X", ctx.evaluateScript("stringify(true, 1, 2, 'X')")?.toString())
    }

    func testDoubleArgsFunctionProperty() throws {
        let ctx = JSContext()
        let sum = JSValue(newFunctionIn: ctx) { ctx, obj, args in
            JSValue(double: args.reduce(0.0, { $0 + $1.toDouble() }), in: ctx)
        }

        let ob = JSValue(newObjectIn: ctx)
        ob.setObject(sum, forKeyedSubscript: "sum")

        ctx.setObject(ob, forKeyedSubscript: "ob")
        XCTAssertNil(ctx.exception)

        for _ in 1...999 {
            let r1 = try XCTUnwrap(ctx.evaluateScript("ob.sum()"))
            XCTAssertNil(ctx.exception)
            XCTAssertFalse(r1.isUndefined)
            XCTAssertEqual(0.0, r1.toDouble())

            do {
                let r1 = try XCTUnwrap(ctx.evaluateScript("ob.sum(1)"))
                XCTAssertNil(ctx.exception)
                XCTAssertFalse(r1.isUndefined)
                XCTAssertEqual(1.0, r1.toDouble())
            }

            do {
                let r2 = try XCTUnwrap(ctx.evaluateScript("ob.sum(1, 2, 3.4, 9.9)"))
                XCTAssertNil(ctx.exception)
                XCTAssertFalse(r2.isUndefined)
                XCTAssertEqual(16.3, r2.toDouble())
            }

            do {
                let r0 = try XCTUnwrap(ctx.evaluateScript("ob.sum('1')"))
                XCTAssertNil(ctx.exception)
                XCTAssertFalse(r0.isUndefined)
                XCTAssertEqual(1.0, r0.toDouble())
            }

            do {
                // call with many args
                XCTAssertTrue(sum.isFunction)
                let sumf = ctx.objectForKeyedSubscript("ob").objectForKeyedSubscript("sum")
                XCTAssertTrue(sumf.isFunction)
                let args = (1..<1_000).map({ JSValue(double: Double($0), in: ctx) })
                let result = try sumf.call(withArguments: args)
                XCTAssertEqual(499_500.0, result.toDouble())
            }
        }
    }
}
