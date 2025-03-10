// Copyright 2023–2025 Skip
// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception
import OSLog
import Foundation
import JavaScriptCore // this import means we're testing JavaScriptCore.JSContext()
import XCTest
#if SKIP
import SkipFFI
#endif

/// Constant for callback testing
let callbackResult = Double.pi


@available(macOS 11, iOS 14, watchOS 7, tvOS 14, *)
class JSContextTests : XCTestCase {
    let logger: Logger = Logger(subsystem: "test", category: "JSContextTests")

    fileprivate final class JSEvalException : Error {
        var exception: JSValue?

        init(exception: JSValue? = nil) {
            self.exception = exception
        }
    }

    func testJSCAPIHigh() throws {
        let ctx = try XCTUnwrap(JSContext())
        let num = try XCTUnwrap(ctx.evaluateScript("1 + 2.3"))

        XCTAssertEqual(3.3, num.toDouble())
        #if SKIP
        let className = "\(type(of: num))" // could be: "class skip.foundation.SkipJSValue (Kotlin reflection is not available)"
        XCTAssertTrue(className.contains("skip.script.JSValue"), "unexpected class name: \(className)")
        #endif
        XCTAssertEqual("3.3", num.toString())

        func eval(_ script: String) throws -> JSValue {
            let result = ctx.evaluateScript(script)
            if let exception = ctx.exception {
                throw JSEvalException(exception: exception)
            }
            if let result = result {
                return result
            } else {
                throw JSEvalException()
            }
        }

        XCTAssertEqual("q", ctx.evaluateScript("'q'")?.toString())
        XCTAssertEqual("Ƕe110", try eval(#"'Ƕ'+"e"+1+1+0"#).toString())

        XCTAssertEqual(true, try eval("[] + {}").isString)
        XCTAssertEqual("[object Object]", try eval("[] + {}").toString())

        XCTAssertEqual(true, try eval("[] + []").isString)
        XCTAssertEqual(true, try eval("{} + {}").isNumber)
        XCTAssertEqual(true, try eval("{} + {}").toDouble().isNaN)

        XCTAssertEqual(true, try eval("{} + []").isNumber)
        XCTAssertEqual(0.0, try eval("{} + []").toDouble())

        XCTAssertEqual(true, try eval("1.0 === 1.0000000000000001").toBool())

        XCTAssertEqual(",,,,,,,,,,,,,,,", try eval("Array(16)").toString())
        XCTAssertEqual("watwatwatwatwatwatwatwatwatwatwatwatwatwatwat", try eval("Array(16).join('wat')").toString())
        XCTAssertEqual("wat1wat1wat1wat1wat1wat1wat1wat1wat1wat1wat1wat1wat1wat1wat1", try eval("Array(16).join('wat' + 1)").toString())
        XCTAssertEqual("NaNNaNNaNNaNNaNNaNNaNNaNNaNNaNNaNNaNNaNNaNNaN Batman!", try eval("Array(16).join('wat' - 1) + ' Batman!'").toString())

        XCTAssertEqual(1, try eval("let y = {}; y[[]] = 1; Object.keys(y)").toArray().count)
        XCTAssertEqual(10.0, try eval("['10', '10', '10'].map(parseInt)").toArray().first as? Double)
        XCTAssertEqual(2.0, try eval("['10', '10', '10'].map(parseInt)").toArray().last as? Double)

        do {
            let _ = try eval("throw 'Error message';")
            XCTFail("eval should have thrown")
        } catch {
            // TODO: verify error message for skip.script.JSContextTests$JSEvalException
            //XCTAssertEqual("", error.localizedDescription)
        }
    }

    func testIntl() throws {
        // the Skip side uses jsc-android rather than jsc-android-intl for size savings
        // TODO: provide a separate SkipScriptIntl target that depends on jsc-android-intl
        #if !SKIP
        let ctx = try XCTUnwrap(JSContext())

        XCTAssertEqual("12,34 €", ctx.evaluateScript("new Intl.NumberFormat('de-DE', { style: 'currency', currency: 'EUR' }).format(12.34)")?.toString())
        XCTAssertEqual("65.4", ctx.evaluateScript("new Intl.NumberFormat('en-IN', { maximumSignificantDigits: 3 }).format(65.4321)")?.toString())
        //XCTAssertEqual("٦٥٫٤٣٢١", ctx.evaluateScript("new Intl.NumberFormat('ar-AR', { maximumSignificantDigits: 6 }).format(65.432123456789)")?.toString())

        let yen = "new Intl.NumberFormat('ja-JP', { style: 'currency', currency: 'JPY' }).format(45.678)"
        // these seem to be different values because they use combining marks differently
        #if os(Linux)
        XCTAssertEqual("￥46", ctx.evaluateScript(yen)?.toString())
        #else
        if isAndroid {
            XCTAssertEqual("￥46", ctx.evaluateScript(yen)?.toString())
        } else {
            XCTAssertEqual("¥46", ctx.evaluateScript(yen)?.toString())
        }
        #endif

        XCTAssertEqual("10/24/2022", ctx.evaluateScript("new Intl.DateTimeFormat('en-US', {timeZone: 'UTC'}).format(new Date('2022-10-24'))")?.toString())
        XCTAssertEqual("24/10/2022", ctx.evaluateScript("new Intl.DateTimeFormat('fr-FR', {timeZone: 'UTC'}).format(new Date('2022-10-24'))")?.toString())
        #endif
    }

    func testProxy() throws {
        let ctx = try XCTUnwrap(JSContext())

        // create a proxy that acts as a map what sorted an uppercase form of the string
        let value: JSValue? = ctx.evaluateScript("""
        var proxyMap = new Proxy(new Map(), {
          // The 'get' function allows you to modify the value returned
          // when accessing properties on the proxy
          get: function(target, name) {
            if (name === 'set') {
              // Return a custom function for Map.set that sets
              // an upper-case version of the value.
              return function(key, value) {
                return target.set(key, value.toUpperCase());
              };
            }
            else {
              var value = target[name];
              // If the value is a function, return a function that
              // is bound to the original target. Otherwise the function
              // would be called with the Proxy as 'this' and Map
              // functions do not work unless the 'this' is the Map.
              if (value instanceof Function) {
                return value.bind(target);
              }
              // Return the normal property value for everything else
              return value;
            }
          }
        });

        proxyMap.set(0, 'foo');
        proxyMap.get(0);
        """)

        XCTAssertEqual("FOO", value?.toString())
    }

    func testJSCProperties() throws {
        let ctx = try XCTUnwrap(JSContext())

        ctx.setObject(10.1, forKeyedSubscript: "doubleProp" as NSString)
        XCTAssertEqual(10.1, ctx.objectForKeyedSubscript("doubleProp").toObject() as? Double)

        ctx.setObject(10, forKeyedSubscript: "intProp" as NSString)
        XCTAssertEqual(10.0, ctx.objectForKeyedSubscript("intProp").toObject() as? Double)

        XCTAssertEqual(nil, ctx.objectForKeyedSubscript("stringProp").toObject() as? String)
        ctx.setObject("XYZ", forKeyedSubscript: "stringProp" as NSString)
        XCTAssertEqual("XYZ", ctx.objectForKeyedSubscript("stringProp").toObject() as? String)

        ctx.setObject(true, forKeyedSubscript: "boolProp" as NSString)
        XCTAssertEqual(true, ctx.objectForKeyedSubscript("boolProp").toObject() as? Bool)

        ctx.setObject(false, forKeyedSubscript: "boolProp" as NSString)
        XCTAssertEqual(false, ctx.objectForKeyedSubscript("boolProp").toObject() as? Bool)
    }

    func testJSCAPILow() throws {
        let ctx = JavaScriptCore.JSGlobalContextCreate(nil)
        defer { JavaScriptCore.JSGlobalContextRelease(ctx) }

        /// Executes the given script using either iOS's bilt-in JavaScriptCore or via Java JNA/JNI linkage to the jar dependencies
        func js(_ script: String) throws -> JSValueRef {
            let scriptValue = JavaScriptCore.JSStringCreateWithUTF8CString(script)
            defer { JavaScriptCore.JSStringRelease(scriptValue) }

            #if SKIP
            var exception = JSValuePointer()
            assert(exception.value == nil)
            #else
            var exception = UnsafeMutablePointer<JSValueRef?>(nil)
            assert(exception?.pointee == nil)
            #endif

            let result = JavaScriptCore.JSEvaluateScript(ctx, scriptValue, nil, nil, 1, exception)

            #if SKIP
            if let error: JavaScriptCore.JSValueRef = exception.value as? com.sun.jna.Pointer {
                //XCTFail("JavaScript exception occurred: \(error)")
                throw ScriptEvalError() // TODO: get error message, and check for underlying Swift error from native callbacks
            }
            #else
            if let error: JavaScriptCore.JSValueRef = exception?.pointee {
                //XCTFail("JavaScript exception occurred: \(error)")
                throw ScriptEvalError()
            }
            #endif

            guard let result = result else {
                throw NoScriptResultError()
            }
            return result
        }

        XCTAssertTrue(JavaScriptCore.JSValueIsUndefined(ctx, try js("undefined")))
        XCTAssertTrue(JavaScriptCore.JSValueIsNull(ctx, try js("null")))
        XCTAssertTrue(JavaScriptCore.JSValueIsBoolean(ctx, try js("true||false")))
        XCTAssertTrue(JavaScriptCore.JSValueIsString(ctx, try js("'1'+1")))
        XCTAssertTrue(JavaScriptCore.JSValueIsArray(ctx, try js("[true, null, 1.234, {}, []]")))
        XCTAssertTrue(JavaScriptCore.JSValueIsDate(ctx, try js("new Date()")))
        XCTAssertTrue(JavaScriptCore.JSValueIsObject(ctx, try js(#"new Object()"#)))

        do {
            _ = try js("XXX()")
            XCTFail("Expected error")
        } catch {
            // e.g.: skip.lib.ErrorThrowable: java.lang.AssertionError: JavaScript exception occurred: native@0x168020ea8
            // TODO: extract error message and verify
        }

        XCTAssertTrue(JavaScriptCore.JSValueIsNumber(ctx, try js("""
        function sumArray(arr) {
          let sum = 0;
          for (let i = 0; i < arr.length; i++) {
            sum += arr[i];
          }
          return sum;
        }

        const largeArray = new Array(100000).fill(1);
        sumArray(largeArray);
        """)))

    }
}

struct ScriptEvalError : Error { }
struct NoScriptResultError : Error { }

