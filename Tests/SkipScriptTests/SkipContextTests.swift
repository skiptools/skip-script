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
        if isAndroid {
            throw XCTSkip("FIXME: crashes on Android emulator in CI") // also fails in local emulator
            /*
07-05 13:33:26.736  4484  4502 I TestRunner: started: testCallFunctionNoArgs$SkipScript_debugAndroidTest(skip.script.SkipContextTests)
JNI DETECTED ERROR IN APPLICATION: JNI GetObjectField called with pending exception java.lang.IllegalArgumentException: Structure field "callAsFunction" was declared as interface com.sun.jna.Callback, which is not supported within a Structure
  at void com.sun.jna.Structure.writeField(com.sun.jna.Structure$StructField, java.lang.Object) (Structure.java:909)
  at void com.sun.jna.Structure.writeField(com.sun.jna.Structure$StructField) (Structure.java:852)
  at void com.sun.jna.Structure.write() (Structure.java:803)
  at void com.sun.jna.Structure.autoWrite() (Structure.java:2285)
  at com.sun.jna.Pointer skip.script.JavaScriptCoreLibrary.JSClassCreate(skip.script.JSClassDefinition) (JSContext.kt:-2)
  at void skip.script.JSValue.<init>(skip.script.JSContext, kotlin.jvm.functions.Function3) (JSContext.kt:267)
  at void skip.script.SkipContextTests.testCallFunctionNoArgs$SkipScript_debugAndroidTest() (SkipContextTests.kt:32)
  at java.lang.Object java.lang.reflect.Method.invoke(java.lang.Object, java.lang.Object[]) (Method.java:-2)
  at java.lang.Object org.junit.runners.model.FrameworkMethod$1.runReflectiveCall() (FrameworkMethod.java:59)
  at java.lang.Object org.junit.internal.runners.model.ReflectiveCallable.run() (ReflectiveCallable.java:12)
  at java.lang.Object org.junit.runners.model.FrameworkMethod.invokeExplosively(java.lang.Object, java.lang.Object[]) (FrameworkMethod.java:56)
  at void org.junit.internal.runners.statements.InvokeMethod.evaluate() (InvokeMethod.java:17)
  at void androidx.test.internal.runner.junit4.statement.RunBefores.evaluate() (RunBefores.java:80)
  at void androidx.test.internal.runner.junit4.statement.RunAfters.evaluate() (RunAfters.java:61)
  at void org.junit.runners.ParentRunner$3.evaluate() (ParentRunner.java:306)
  at void org.junit.runners.BlockJUnit4ClassRunner$1.evaluate() (BlockJUnit4ClassRunner.java:100)
  at void org.junit.runners.ParentRunner.runLeaf(org.junit.runners.model.Statement, org.junit.runner.Description, org.junit.runner.notification.RunNotifier) (ParentRunner.java:366)
  at void org.junit.runners.BlockJUnit4ClassRunner.runChild(org.junit.runners.model.FrameworkMethod, org.junit.runner.notification.RunNotifier) (BlockJUnit4ClassRunner.java:103)
  at void org.junit.runners.BlockJUnit4ClassRunner.runChild(java.lang.Object, org.junit.runner.notification.RunNotifier) (BlockJUnit4ClassRunner.java:63)
  at void org.junit.runners.ParentRunner$4.run() (ParentRunner.java:331)
  at void org.junit.runners.ParentRunner$1.schedule(java.lang.Runnable) (ParentRunner.java:79)
  at void org.junit.runners.ParentRunner.runChildren(org.junit.runner.notification.RunNotifier) (ParentRunner.java:329)
  at void org.junit.runners.ParentRunner.access$100(org.junit.runners.ParentRunner, org.junit.runner.notification.RunNotifier) (ParentRunner.java:66)
  at void org.junit.runners.ParentRunner$2.evaluate() (ParentRunner.java:293)
  at void org.junit.runners.ParentRunner$3.evaluate() (ParentRunner.java:306)
  at void org.junit.runners.ParentRunner.run(org.junit.runner.notification.RunNotifier) (ParentRunner.java:413)
  at void org.junit.runners.Suite.runChild(org.junit.runner.Runner, org.junit.runner.notification.RunNotifier) (Suite.java:128)
  at void org.junit.runners.Suite.runChild(java.lang.Object, org.junit.runner.notification.RunNotifier) (Suite.java:27)
  at void org.junit.runners.ParentRunner$4.run() (ParentRunner.java:331)
  at void org.junit.runners.ParentRunner$1.schedule(java.lang.Runnable) (ParentRunner.java:79)
  at void org.junit.runners.ParentRunner.runChildren(org.junit.runner.notification.RunNotifier) (ParentRunner.java:329)
  at void org.junit.runners.ParentRunner.access$100(org.junit.runners.ParentRunner, org.junit.runner.notification.RunNotifier) (ParentRunner.java:66)
  at void org.junit.runners.ParentRunner$2.evaluate() (ParentRunner.java:293)
  at void org.junit.runners.ParentRunner$3.evaluate() (ParentRunner.java:306)
  at void org.junit.runners.ParentRunner.run(org.junit.runner.notification.RunNotifier) (ParentRunner.java:413)
  at org.junit.runner.Result org.junit.runner.JUnitCore.run(org.junit.runner.Runner) (JUnitCore.java:137)
  at org.junit.runner.Result org.junit.runner.JUnitCore.run(org.junit.runner.Request) (JUnitCore.java:115)
  at android.os.Bundle androidx.test.internal.runner.TestExecutor.execute(org.junit.runner.JUnitCore, org.junit.runner.Request) (TestExecutor.java:68)
  at android.os.Bundle androidx.test.internal.runner.TestExecutor.execute(org.junit.runner.Request) (TestExecutor.java:59)
  at void androidx.test.runner.AndroidJUnitRunner.onStart() (AndroidJUnitRunner.java:463)
  at void android.app.Instrumentation$InstrumentationThread.run() (Instrumentation.java:2402)
Caused by: java.lang.IllegalArgumentException: Callback must implement a single public method, or one public method named 'callback'
  at java.lang.reflect.Method com.sun.jna.CallbackReference.getCallbackMethod(java.lang.Class) (CallbackReference.java:427)
  at java.lang.reflect.Method com.sun.jna.CallbackReference.getCallbackMethod(com.sun.jna.Callback) (CallbackReference.java:397)
  at void com.sun.jna.CallbackReference.<init>(com.sun.jna.Callback, int, boolean) (CallbackReference.java:289)
  at com.sun.jna.Pointer com.sun.jna.CallbackReference.getFunctionPointer(com.sun.jna.Callback, boolean) (CallbackReference.java:512)
  at com.sun.jna.Pointer com.sun.jna.CallbackReference.getFunctionPointer(com.sun.jna.Callback) (CallbackReference.java:489)
  at void com.sun.jna.Pointer.setValue(long, java.lang.Object, java.lang.Class) (Pointer.java:885)
  at void com.sun.jna.Structure.writeField(com.sun.jna.Structure$StructField, java.lang.Object) (Structure.java:901)
  at void com.sun.jna.Structure.writeField(com.sun.jna.Structure$StructField) (Structure.java:852)
  at void com.sun.jna.Structure.write() (Structure.java:803)
  at void com.sun.jna.Structure.autoWrite() (Structure.java:2285)
  at com.sun.jna.Pointer skip.script.JavaScriptCoreLibrary.JSClassCreate(skip.script.JSClassDefinition) (JSContext.kt:-2)
  at void skip.script.JSValue.<init>(skip.script.JSContext, kotlin.jvm.functions.Function3) (JSContext.kt:267)
  at void skip.script.SkipContextTests.testCallFunctionNoArgs$SkipScript_debugAndroidTest() (SkipContextTests.kt:32)
  at java.lang.Object java.lang.reflect.Method.invoke(java.lang.Object, java.lang.Object[]) (Method.java:-2)
  at java.lang.Object org.junit.runners.model.FrameworkMethod$1.runReflectiveCall() (FrameworkMethod.java:59)
  at java.lang.Object org.junit.internal.runners.model.ReflectiveCallable.run() (ReflectiveCallable.java:12)
  at java.lang.Object org.junit.runners.model.FrameworkMethod.invokeExplosively(java.lang.Object, java.lang.Object[]) (FrameworkMethod.java:56)
  at void org.junit.internal.runners.statements.InvokeMethod.evaluate() (InvokeMethod.java:17)
  at void androidx.test.internal.runner.junit4.statement.RunBefores.evaluate() (RunBefores.java:80)
  at void androidx.test.internal.runner.junit4.statement.RunAfters.evaluate() (RunAfters.java:61)
  at void org.junit.runners.ParentRunner$3.evaluate() (ParentRunner.java:306)
  at void org.junit.runners.BlockJUnit4ClassRunner$1.evaluate() (BlockJUnit4ClassRunner.java:100)
  at void org.junit.runners.ParentRunner.runLeaf(org.junit.runners.model.Statement, org.junit.runner.Description, org.junit.runner.notification.RunNotifier) (ParentRunner.java:366)
  at void org.junit.runners.BlockJUnit4ClassRunner.runChild(org.junit.runners.model.FrameworkMethod, org.junit.runner.notification.RunNotifier) (BlockJUnit4ClassRunner.java:103)
  at void org.junit.runners.BlockJUnit4ClassRunner.runChild(java.lang.Object, org.junit.runner.notification.RunNotifier) (BlockJUnit4ClassRunner.java:63)
  at void org.junit.runners.ParentRunner$4.run() (ParentRunner.java:331)
  at void org.junit.runners.ParentRunner$1.schedule(java.lang.Runnable) (ParentRunner.java:79)
  at void org.junit.runners.ParentRunner.runChildren(org.junit.runner.notification.RunNotifier) (ParentRunner.java:329)
  at void org.junit.runners.ParentRunner.access$100(org.junit.runners.ParentRunner, org.junit.runner.notification.RunNotifier) (ParentRunner.java:66)
  at void org.junit.runners.ParentRunner$2.evaluate() (ParentRunner.java:293)
  at void org.junit.runners.ParentRunner$3.evaluate() (ParentRunner.java:306)
  at void org.junit.runners.ParentRunner.run(org.junit.runner.notification.RunNotifier) (ParentRunner.java:413)
  at void org.junit.runners.Suite.runChild(org.junit.runner.Runner, org.junit.runner.notification.RunNotifier) (Suite.java:128)
  at void org.junit.runners.Suite.runChild(java.lang.Object, org.junit.runner.notification.RunNotifier) (Suite.java:27)
  at void org.junit.runners.ParentRunner$4.run() (ParentRunner.java:331)
  at void org.junit.runners.ParentRunner$1.schedule(java.lang.Runnable) (ParentRunner.java:79)
  at void org.junit.runners.ParentRunner.runChildren(org.junit.runner.notification.RunNotifier) (ParentRunner.java:329)
  at void org.junit.runners.ParentRunner.access$100(org.junit.runners.ParentRunner, org.junit.runner.notification.RunNotifier) (ParentRunner.java:66)
  at void org.junit.runners.ParentRunner$2.evaluate() (ParentRunner.java:293)
  at void org.junit.runners.ParentRunner$3.evaluate() (ParentRunner.java:306)
  at void org.junit.runners.ParentRunner.run(org.junit.runner.notification.RunNotifier) (ParentRunner.java:413)
  at org.junit.runner.Result org.junit.runner.JUnitCore.run(org.junit.runner.Runner) (JUnitCore.java:137)
  at org.junit.runner.Result org.junit.runner.JUnitCore.run(org.junit.runner.Request) (JUnitCore.java:115)
  at android.os.Bundle androidx.test.internal.runner.TestExecutor.execute(org.junit.runner.JUnitCore, org.junit.runner.Request) (TestExecutor.java:68)
  at android.os.Bundle androidx.test.internal.runner.TestExecutor.execute(org.junit.runner.Request) (TestExecutor.java:59)
  at void androidx.test.runner.AndroidJUnitRunner.onStart() (AndroidJUnitRunner.java:463)
  at void android.app.Instrumentation$InstrumentationThread.run() (Instrumentation.java:2402)
             */
        }
        let ctx = JSContext()
        let fun = JSValue(newFunctionIn: ctx) { ctx, obj, args in
            JSValue(double: .pi, in: ctx)
        }

        XCTAssertEqual(.pi, try fun.call(withArguments: []).toDouble())
    }

    func testCallFunction() throws {
        if isAndroid {
            throw XCTSkip("FIXME: crashes on Android emulator in CI") // but not when testing against a local emulator
        }

        // we run this many times in order to ensure that neither JavaScript GC nor Java GC will cause the function's struct/class being freed
        for i in 1...10 {
            let ctx = JSContext()
            for j in 1...100 {
                let sum = JSValue(newFunctionIn: ctx) { ctx, obj, args in
                    JSValue(double: args.reduce(0.0, { $0 + $1.toDouble() }), in: ctx)
                }
                for k in 1...100 {
                    let num = Double.random(in: 0.0...1000.0)
                    let args = [JSValue(double: 3.0, in: ctx), JSValue(double: num, in: ctx)]
                    XCTAssertEqual(num + 3.0, try sum.call(withArguments: args).toDouble(), "\(i)-\(j)-\(k) failure")
                }
            }
        }
    }

    func testFunctionProperty() throws {
        if isAndroid {
            throw XCTSkip("FIXME: crashes on Android emulator in CI") // also fails in local emulator
        }

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
