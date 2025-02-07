// Copyright 2023 Skip
//
// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org
#if !SKIP
import Foundation
// Non-Skip uses the JavaScriptCore symbols directly
import JavaScriptCore
#else
import SkipFFI

/// Global pointer to the JSC library, equivalent to the Swift `JavaScriptCore` framework (`libjsc.so` on Android)
let JavaScriptCore: JavaScriptCoreLibrary = JavaScriptCoreLibrary.instance
#endif

public typealias ExceptionPtr = UnsafeMutablePointer<JSValueRef?>

/// JIT needs to be disabled on Android to avoid random crashes in `JSValueUnprotect`
/// See: https://github.com/WebKit/WebKit/blob/main/Tools/Scripts/run-jsc-benchmarks
private func disableJIT() {
    // JSC_useWasmIPInt=0 JSC_useWasmLLInt=1 JSC_useWebAssembly=1 JSC_useJIT=0
    #if SKIP
    android.system.Os.setenv("JSC_useJIT", "false", true)
    #else
    //setenv("JSC_useJIT", "false", 1) // no need: iOS doesn't support JIT anyway :)
    #endif
}

/// A context for evaluating JavaScipt.
public class JSContext {
    public let context: JSContextRef
    public private(set) var exception: JSValue? = nil
    private var tryingRecursionGuard = false

    public init(jsGlobalContextRef context: JSContextRef) {
        disableJIT()
        self.context = context
        JavaScriptCore.JSGlobalContextRetain(context)
    }

    public init() {
        disableJIT()
        self.context = JavaScriptCore.JSGlobalContextCreate(nil)
    }

    deinit {
        JavaScriptCore.JSGlobalContextRelease(context)
    }

    @discardableResult fileprivate func clearException(_ exception: ExceptionPtr? = nil) -> Bool {
        if let exception = exception {
            // errors are handled by returning nil and setting the current exception poinrts
            #if SKIP
            let errorPtr: JavaScriptCore.JSValueRef? = exception.value
            #else
            let errorPtr: JavaScriptCore.JSValueRef? = exception.pointee
            #endif

            if let error = errorPtr {
                self.exception = JSValue(jsValueRef: error, in: self)
                return false
            } else {
                // clear the current exception
                self.exception = nil
            }
        } else {
            // clear the current exception
            self.exception = nil
        }

        return true
    }

    public func evaluateScript(_ script: String) -> JSValue? {
        let scriptValue = JavaScriptCore.JSStringCreateWithUTF8CString(script)
        defer { JavaScriptCore.JSStringRelease(scriptValue) }

        let exception = ExceptionPtr(nil)
        let result = JavaScriptCore.JSEvaluateScript(context, scriptValue, nil, nil, 1, exception)
        if !clearException(exception) {
            return nil
        }
        guard let result = result else {
            return JSValue(undefinedIn: self)
        }
        return JSValue(jsValueRef: result, in: self)
    }

    /// Attempts the operation whose failure is expected to set the given error pointer.
    ///
    /// When the error pointer is set, a ``JSError`` will be thrown.
    func trying<T>(function: (ExceptionPtr) throws -> T) throws -> T {
        #if !SKIP
        var errorPointer: JSValueRef?
        let result = try function(&errorPointer)
        if let errorPointer = errorPointer {
            // Creating a JSError from the errorPointer may involve calling functions that throw errors,
            // though the errors are all handled internally. Guard against infinite recursion by short-
            // circuiting those cases
            if tryingRecursionGuard {
                return result
            } else {
                tryingRecursionGuard = true
                defer { tryingRecursionGuard = false }
                let error = JSValue(jsValueRef: errorPointer, in: self)
                throw JSError(jsError: error)
            }
        } else {
            return result
        }
        #else
        let ptr = ExceptionPtr()
        let result = try function(ptr)
        // TODO: handle error pointer on Java side
        return result
        #endif
    }

    #if !SKIP

    /// Checks for syntax errors in a string of JavaScript.
    ///
    /// - Parameters:
    ///   - script: The script to check for syntax errors.
    ///   - source: The script's source file. This is only used when reporting exceptions. Pass `nil` to omit source file information in exceptions.
    ///   - startingLineNumber: An integer value specifying the script's starting line number in the file located at sourceURL. This is only used when reporting exceptions.
    /// - Returns: true if the script is syntactically correct; otherwise false.
    public func checkSyntax(_ script: String, source: String? = nil, startingLineNumber: Int = 0) throws -> Bool {
        let script = script.withCString(JSStringCreateWithUTF8CString)
        defer { JSStringRelease(script) }

        let sourceString = source?.withCString(JSStringCreateWithUTF8CString)
        defer { sourceString.map(JSStringRelease) }

        return try trying {
            JSCheckScriptSyntax(context, script, sourceString, Int32(startingLineNumber), $0)
        }
    }

    #endif

    /// The global object.
    public var global: JSValue {
        JSValue(jsValueRef: JavaScriptCore.JSContextGetGlobalObject(context), in: self)
    }

    /// Performs a JavaScript garbage collection.
    ///
    /// During JavaScript execution, you are not required to call this function; the JavaScript engine will garbage collect as needed.
    /// JavaScript values created within a context group are automatically destroyed when the last reference to the context group is released.
    public func garbageCollect() {
        JavaScriptCore.JSGarbageCollect(context)
    }

}


public protocol JSInstance {
    var valueRef: JSValueRef { get }
    var contextRef: JSContextRef { get }
}

extension JSContext : JSInstance {
    public var valueRef: JSValueRef { self.global.value }
    public var contextRef: JSContextRef { self.context }
}


extension JSValue : JSInstance {
    public var valueRef: JSValueRef { self.value }
    public var contextRef: JSContextRef { self.context.context }
}


extension JSInstance {

    public func setObject(_ object: Any, forKeyedSubscript key: String) {
        let propName = JavaScriptCore.JSStringCreateWithUTF8CString(key)
        defer { JavaScriptCore.JSStringRelease(propName) }
        let exception = ExceptionPtr(nil)
        let value = (object as? JSValue) ?? JSValue(object: object, in: JSContext(jsGlobalContextRef: self.contextRef))
        let valueRef = value.value
        JavaScriptCore.JSObjectSetProperty(self.contextRef, self.valueRef, propName, valueRef, JSPropertyAttributes(kJSPropertyAttributeNone), exception)
    }

    public func objectForKeyedSubscript(_ key: String) -> JSValue {
        let propName = JavaScriptCore.JSStringCreateWithUTF8CString(key)
        defer { JavaScriptCore.JSStringRelease(propName) }
        let exception = ExceptionPtr(nil)
        let ctx = JSContext(jsGlobalContextRef: self.contextRef)
        let value = JavaScriptCore.JSObjectGetProperty(self.contextRef, self.valueRef, propName, exception)
        if !ctx.clearException(exception) {
            return JSValue(undefinedIn: ctx)
        } else if let value = value {
            return JSValue(jsValueRef: value, in: ctx)
        } else {
            return JSValue(nullIn: ctx)
        }
    }

}

/// A JSValue is a reference to a JavaScript value.
///
/// Every JSValue originates from a JSContext and holds a strong reference to it.
public class JSValue {
    public let context: JSContext
    public let value: JSValueRef

    public init(jsValueRef: JSValueRef, in context: JSContext) {
        self.context = context
        self.value = jsValueRef
        JavaScriptCore.JSValueProtect(context.context, self.value)
    }

    public init(nullIn context: JSContext) {
        self.context = context
        self.value = JavaScriptCore.JSValueMakeNull(context.context)
        JavaScriptCore.JSValueProtect(context.context, self.value)
    }

    public init(object obj: Any, in context: JSContext) {
        self.context = context
        switch obj {
        case let bol as Bool:
            self.value = JavaScriptCore.JSValueMakeBoolean(context.context, bol)

        case let num as Double:
            self.value = JavaScriptCore.JSValueMakeNumber(context.context, num)
        case let num as Float:
            self.value = JavaScriptCore.JSValueMakeNumber(context.context, Double(num))

        case let num as Int8:
            self.value = JavaScriptCore.JSValueMakeNumber(context.context, Double(num))
        case let num as Int16:
            self.value = JavaScriptCore.JSValueMakeNumber(context.context, Double(num))
        case let num as Int32:
            self.value = JavaScriptCore.JSValueMakeNumber(context.context, Double(num))
        case let num as Int64:
            self.value = JavaScriptCore.JSValueMakeNumber(context.context, Double(num))

        case let num as UInt8:
            self.value = JavaScriptCore.JSValueMakeNumber(context.context, Double(num))
        case let num as UInt16:
            self.value = JavaScriptCore.JSValueMakeNumber(context.context, Double(num))
        case let num as UInt32:
            self.value = JavaScriptCore.JSValueMakeNumber(context.context, Double(num))
        case let num as UInt64:
            self.value = JavaScriptCore.JSValueMakeNumber(context.context, Double(num))

        case let str as String:
            let jstr = JavaScriptCore.JSStringCreateWithUTF8CString(str)
            defer { JavaScriptCore.JSStringRelease(jstr) }
            self.value = JavaScriptCore.JSValueMakeString(context.context, jstr)

        default:
            self.value = JavaScriptCore.JSValueMakeNull(context.context)
        }
        JavaScriptCore.JSValueProtect(context.context, self.value)
    }

    /// Creates a JavaScript value of the function type.
    ///
    /// - Parameters:
    ///   - context: The execution context to use.
    ///   - callback: The callback function.
    /// - Note: This object is callable as a function (due to `JSClassDefinition.callAsFunction`), but the JavaScript runtime doesn't treat it exactly like a function. For example, you cannot call "apply" on it. It could be better to use `JSObjectMakeFunctionWithCallback`, which may act more like a "true" JavaScript function.
    public init(newFunctionIn context: JSContext, callback: @escaping JSFunction) {
        var def = JSClassDefinition()
        def.finalize = JSFunctionFinalize // JNA: JSFunctionFinalizeImpl()
        def.callAsConstructor = JSFunctionConstructor // JNA: JSFunctionConstructorImpl()
        def.callAsFunction = JSFunctionCallback // JNA: JSFunctionCallbackImpl()
        def.hasInstance = JSFunctionInstanceOf // JNA: JSFunctionInstanceOf()

        let callbackInfo = JSFunctionInfo(context: context, callback: callback)

        #if !SKIP
        let info = UnsafeMutablePointer<JSFunctionInfo>.allocate(capacity: 1)
        info.initialize(to: callbackInfo)
        let cls = JavaScriptCore.JSClassCreate(&def)
        #else
        let info = callbackInfo.getPointer()
        let cls = JavaScriptCore.JSClassCreate(def)
        #endif

        defer { JavaScriptCore.JSClassRelease(cls) }

        let jsValueRef = JavaScriptCore.JSObjectMake(context.context, cls, info)
        self.context = context
        self.value = jsValueRef!
        JavaScriptCore.JSValueProtect(context.context, self.value)
    }

    #if !SKIP

    /// Creates a JavaScript `Error` object, as if by invoking the built-in `Error` constructor.
    ///
    /// - Parameters:
    ///   - message: The error message.
    ///   - context: The execution context to use.
    convenience init(newErrorFromCause cause: Error, in context: JSContext) {
        let msg = JavaScriptCore.JSStringCreateWithUTF8CString(cause.localizedDescription)
        defer { JavaScriptCore.JSStringRelease(msg) }
        let err = JavaScriptCore.JSObjectMakeError(context.context, 1, [msg], nil)
        self.init(jsValueRef: err.unsafelyUnwrapped, in: context)

        // TODO: add the error as the cause
        // If the cause itself has a cause, use that as the JS error message so that if this is a JSError
        // caused by a native error, any JS catch block can test for the original native error message,
        // without the added JS context
        //let rootCause = (cause as? JSError)?.cause ?? cause
        //let messageValue = context.string("\(rootCause)")
        // Error's second constructor param is an options object with a 'cause' property of any type.
        // Use this to transfer the original cause as a peer
        //let causeValue = context.object()
        //try causeValue.setProperty("cause", context.object(peer: JSErrorPeer(error: cause)))
        //let arguments = [messageValue, causeValue]
        //let object = try context.trying {
        //    JSObjectMakeError(context.contextRef, arguments.count, arguments.map { $0.valueRef }, $0)
        //}
    }

    /// The value of the property.
    public subscript(propertyName: String) -> JSValue {
        get throws {
            if !isObject { return JSValue(undefinedIn: context) }
            let property = JSStringCreateWithUTF8CString(propertyName)
            defer { JSStringRelease(property) }
            let resultRef = try context.trying {
                JSObjectGetProperty(context.context, value, property, $0)
            }
            return resultRef.map { JSValue(jsValueRef: $0, in: context) } ?? JSValue(undefinedIn: context)
        }
    }


    /// Sets the property of the object to the given value.
    ///
    /// - Parameters:
    ///   - key: The key name to set.
    ///   - newValue: The value of the property.
    /// - Returns: The value itself.
    @discardableResult public func setProperty(_ key: String, _ newValue: JSValue) throws -> JSValue {
        if !isObject {
            throw JSCError(message: "setProperty called on a non-object type")
        }

        let property = JSStringCreateWithUTF8CString(key)
        defer { JSStringRelease(property) }
        try context.trying {
            JSObjectSetProperty(context.context, value, property, newValue.value, 0, $0)
        }
        return newValue
    }

    #endif


    public var isUndefined: Bool {
        JavaScriptCore.JSValueIsUndefined(context.context, value)
    }

    public var isNull: Bool {
        JavaScriptCore.JSValueIsNull(context.context, value)
    }

    public var isBoolean: Bool {
        JavaScriptCore.JSValueIsBoolean(context.context, value)
    }

    public var isNumber: Bool {
        JavaScriptCore.JSValueIsNumber(context.context, value)
    }

    public var isString: Bool {
        JavaScriptCore.JSValueIsString(context.context, value)
    }

    public var isObject: Bool {
        JavaScriptCore.JSValueIsObject(context.context, value)
    }

    public var isArray: Bool {
        JavaScriptCore.JSValueIsArray(context.context, value)
    }

    public var isDate: Bool {
        JavaScriptCore.JSValueIsDate(context.context, value)
    }

    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    public var isSymbol: Bool {
        JavaScriptCore.JSValueIsSymbol(context.context, value)
    }

    /// Tests whether an object can be called as a function.
    public var isFunction: Bool {
        isObject && JavaScriptCore.JSObjectIsFunction(context.context, value)
    }


//    /// Tests whether a JavaScript value’s type is the `Promise` type by seeing it if is an instance of ``JXContext//promisePrototype``.
//    ///
//    /// See: [MDN Promise Documentation](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Promise)
//    public var isPromise: Bool {
//        get throws {
//            try isInstance(of: context.promisePrototype)
//        }
//    }
//
//    /// Tests whether a JavaScript value’s type is the error type.
//    public var isError: Bool {
//        get throws {
//            try isInstance(of: context.errorPrototype)
//        }
//    }



    public func toBool() -> Bool {
        JavaScriptCore.JSValueToBoolean(context.context, value)
    }

    public func toDouble() -> Double {
        let exception = ExceptionPtr(nil)
        let result = JavaScriptCore.JSValueToNumber(context.context, value, exception)
        context.clearException(exception)
        return result
    }

    // SKIP DECLARE: override fun toString(): String
    public func toString() -> String! {
        guard let ref: JSStringRef = JavaScriptCore.JSValueToStringCopy(context.context, value, nil) else {
            return ""
        }

        let chars = JavaScriptCore.JSStringGetCharactersPtr(ref)
        let len = JavaScriptCore.JSStringGetLength(ref)
        #if SKIP
        let buffer = CharArray(len)
        for i in 0..<len {
            buffer[i] = chars.getChar((i * 2).toLong())
        }
        return buffer.concatToString()
        #else
        return String(utf16CodeUnits: chars!, count: len)
        #endif
    }

    public func toArray() -> [Any?] {
        let len = getArrayLength()
        if len == 0 { return [] }

        var result: [Any?] = []

        let exception = ExceptionPtr(nil)
        for index in 0..<len {
            guard let elementValue = JavaScriptCore.JSObjectGetPropertyAtIndex(context.context, value, .init(index), exception) else {
                return []
            }
            let element = JSValue(jsValueRef: elementValue, in: context)
            if !context.clearException(exception) {
                // any exceptions will short-circuit and return an empty array
                return []
            }
            result.append(element.toObject())
        }

        return result
    }

    public func toObject() -> Any? {
        if JavaScriptCore.JSValueIsArray(context.context, value) {
            return toArray()
        }
        if JavaScriptCore.JSValueIsDate(context.context, value) {
            return nil // TODO
        }

        switch JavaScriptCore.JSValueGetType(context.context, value).rawValue {
            case 0: // kJSTypeUndefined
                return nil
            case 1: // kJSTypeNull
                return nil
            case 2: // kJSTypeBoolean
                return toBool()
            case 3: // kJSTypeNumber
                return toDouble()
            case 4: // kJSTypeString
                return toString()
            case 5: // kJSTypeObject
                return nil // TODO: return an object as a dictionary
            case 6: // kJSTypeSymbol
                return nil // TODO
            default:
                return nil // TODO
        }
    }

//    public func toDate() -> Date {
//        fatalError("WIP")
//    }

//    public func toDictionary() -> [AnyHashable: Any] {
//        fatalError("WIP")
//    }

    func getArrayLength() -> Int {
        let lengthProperty = JavaScriptCore.JSStringCreateWithUTF8CString("length")
        defer { JavaScriptCore.JSStringRelease(lengthProperty) }

        let exception = ExceptionPtr(nil)
        let lengthValue = JavaScriptCore.JSObjectGetProperty(context.context, value, lengthProperty, exception)
        if !context.clearException(exception) { return 0 }
        let length = Int(JavaScriptCore.JSValueToNumber(context.context, lengthValue, exception))
        if !context.clearException(exception) { return 0 }
        return length
    }

    /// Calls an object as a function.
    ///
    /// - Parameters:
    ///   - arguments: The arguments to pass to the function.
    ///   - this: The object to use as `this`, or `nil` to use the global object as `this`.
    /// - Returns: The object that results from calling object as a function
    @discardableResult public func call(withArguments arguments: [JSValue] = [], this: JSValue? = nil) throws -> JSValue {
        if !isFunction {
            throw JSCError(message: "call invoked on a non-function type")
        }

        #if !SKIP
        let args: Array<JSValueRef?>? = arguments.isEmpty ? nil : arguments.map(\.value)
        #else
        //com.sun.jna.Native.setProtected(true)

        // this should work as the argument since JNA should convert the pointer array, but it crashes
        //let args: kotlin.Array<JSValueRef?>? = arguments.isEmpty ? nil : arguments.map(\.value).collection.toTypedArray()

        let pointerSize: Int32 = com.sun.jna.Native.POINTER_SIZE
        let size = Int64(arguments.count * pointerSize)
        let args = arguments.count == 0 ? nil : com.sun.jna.Memory(size)
        defer { args?.clear(size) }
        for i in (0..<arguments.count) {
            args!.setPointer(i.toLong() * pointerSize, arguments[i].value)
        }
        #endif

        let ctx = self.context
        return try context.trying { (exception: ExceptionPtr) in
            guard let result = JavaScriptCore.JSObjectCallAsFunction(ctx.context, self.value, nil, arguments.count, arguments.count == 0 ? nil : args, exception) else {
                return JSValue(undefinedIn: ctx)
            }

            return JSValue(jsValueRef: result, in: ctx)
        }
    }

    deinit {
        // this has been seen to raise an exception on the Android emulator when not setting `JSC_useJIT`:
        // java.util.concurrent.TimeoutException: skip.script.JSValue.finalize() timed out after 10 seconds
        // it has also led to crashes:
        /*
         02-06 14:33:12.996  2016  2016 F DEBUG   :       #00 pc 000000000028ff90  /data/app/~~HElSLsP99NS9XFzsCODJmA==/skip.script.test-v4AHg-MWsLEjjHmmm5YC7w==/base.apk!libjsc.so (offset 0x2aa8000) (JSValueUnprotect+16) (BuildId: ca8f87b98242c913dfdaa146cce2a24b070804a2)
         02-06 14:33:12.996  2016  2016 F DEBUG   :       #01 pc 0000000000012051  /data/app/~~HElSLsP99NS9XFzsCODJmA==/skip.script.test-v4AHg-MWsLEjjHmmm5YC7w==/base.apk (offset 0x2a88000) (BuildId: 93b2f9545d27a84372ca7fba3b2b473c2f9c6edd)
         02-06 14:33:12.996  2016  2016 F DEBUG   :       #02 pc 0000000000011032  /data/app/~~HElSLsP99NS9XFzsCODJmA==/skip.script.test-v4AHg-MWsLEjjHmmm5YC7w==/base.apk (offset 0x2a88000) (BuildId: 93b2f9545d27a84372ca7fba3b2b473c2f9c6edd)
         02-06 14:33:12.996  2016  2016 F DEBUG   :       #03 pc 000000000001174b  /data/app/~~HElSLsP99NS9XFzsCODJmA==/skip.script.test-v4AHg-MWsLEjjHmmm5YC7w==/base.apk (offset 0x2a88000) (ffi_call+219) (BuildId: 93b2f9545d27a84372ca7fba3b2b473c2f9c6edd)
         02-06 14:33:12.996  2016  2016 F DEBUG   :       #04 pc 0000000000007264  /data/app/~~HElSLsP99NS9XFzsCODJmA==/skip.script.test-v4AHg-MWsLEjjHmmm5YC7w==/base.apk (offset 0x2a88000) (BuildId: 93b2f9545d27a84372ca7fba3b2b473c2f9c6edd)
         02-06 14:33:12.996  2016  2016 F DEBUG   :       #05 pc 0000000000011a17  /data/app/~~HElSLsP99NS9XFzsCODJmA==/skip.script.test-v4AHg-MWsLEjjHmmm5YC7w==/base.apk (offset 0x2a88000) (BuildId: 93b2f9545d27a84372ca7fba3b2b473c2f9c6edd)
         02-06 14:33:12.997  2016  2016 F DEBUG   :       #06 pc 00000000000121e7  /data/app/~~HElSLsP99NS9XFzsCODJmA==/skip.script.test-v4AHg-MWsLEjjHmmm5YC7w==/base.apk (offset 0x2a88000) (BuildId: 93b2f9545d27a84372ca7fba3b2b473c2f9c6edd)
         02-06 14:33:12.997  2016  2016 F DEBUG   :       #07 pc 000000000200d1de  /memfd:jit-cache (deleted) (offset 0x2000000) (art_jni_trampoline+222)
         02-06 14:33:12.997  2016  2016 F DEBUG   :       #08 pc 000000000202ee59  /memfd:jit-cache (deleted) (offset 0x2000000) (skip.script.JSValue.finalize+121)
         02-06 14:33:12.997  2016  2016 F DEBUG   :       #09 pc 000000000202f070  /memfd:jit-cache (deleted) (offset 0x2000000) (java.lang.Daemons$FinalizerDaemon.doFinalize+112)
         02-06 14:33:12.997  2016  2016 F DEBUG   :       #10 pc 000000000202b42f  /memfd:jit-cache (deleted) (offset 0x2000000) (java.lang.Daemons$FinalizerDaemon.runInternal+511)
         02-06 14:33:12.997  2016  2016 F DEBUG   :       #11 pc 0000000000185e6b  /apex/com.android.art/lib64/libart.so (art_quick_osr_stub+27) (BuildId: 1dfb27162fe62a7ac7a10ea361233369)
         02-06 14:33:12.997  2016  2016 F DEBUG   :       #12 pc 00000000003d27ba  /apex/com.android.art/lib64/libart.so (art::jit::Jit::MaybeDoOnStackReplacement(art::Thread*, art::ArtMethod*, unsigned int, int, art::JValue*)+410) (BuildId: 1dfb27162fe62a7ac7a10ea361233369)
         */
        JavaScriptCore.JSValueUnprotect(context.context, value)
    }
}

extension JSValue {

    /// Creates a JavaScript value of the `undefined` type.
    ///
    /// - Parameters:
    ///   - context: The execution context to use.
    public convenience init(undefinedIn context: JSContext) {
        #if !SKIP
        self.init(jsValueRef: JavaScriptCore.JSValueMakeUndefined(context.context), in: context)
        #else
        // Workaround for Skip error: "In Kotlin, delegating calls to 'self' or 'super' constructors can not use local variables other than the parameters passed to this constructor"
        self.init(jsValueRef: JavaScriptCoreLibrary.instance.JSValueMakeUndefined(context.context), in: context)
        #endif
    }

    /// Creates a JavaScript value of the `null` type.
    ///
    /// - Parameters:
    ///   - context: The execution context to use.
//    public convenience init(nullIn context: JSContext) {
//        self.init(jsValueRef: JSValueMakeNull(context.context), in: context)
//    }

    /// Creates a JavaScript `Boolean` value.
    ///
    /// - Parameters:
    ///   - value: The value to assign to the object.
    ///   - context: The execution context to use.
    public convenience init(bool value: Bool, in context: JSContext) {
        #if !SKIP
        self.init(jsValueRef: JavaScriptCore.JSValueMakeBoolean(context.context, value), in: context)
        #else
        // Workaround for Skip error: "In Kotlin, delegating calls to 'self' or 'super' constructors can not use local variables other than the parameters passed to this constructor"
        self.init(jsValueRef: JavaScriptCoreLibrary.instance.JSValueMakeBoolean(context.context, value), in: context)
        #endif
    }

    /// Creates a JavaScript value of the `Number` type.
    ///
    /// - Parameters:
    ///   - value: The value to assign to the object.
    ///   - context: The execution context to use.
    public convenience init(double value: Double, in context: JSContext) {
        #if !SKIP
        self.init(jsValueRef: JavaScriptCore.JSValueMakeNumber(context.context, value), in: context)
        #else
        // Workaround for Skip error: "In Kotlin, delegating calls to 'self' or 'super' constructors can not use local variables other than the parameters passed to this constructor"
        self.init(jsValueRef: JavaScriptCoreLibrary.instance.JSValueMakeNumber(context.context, value), in: context)
        #endif
    }

    #if !SKIP
    /// Creates a JavaScript value of the `String` type.
    ///
    /// - Parameters:
    ///   - value: The value to assign to the object.
    ///   - context: The execution context to use.
    public convenience init(string value: String, in context: JSContext) {
        let str = value.withCString(JavaScriptCore.JSStringCreateWithUTF8CString)
        defer { JavaScriptCore.JSStringRelease(str) }
        self.init(jsValueRef: JavaScriptCore.JSValueMakeString(context.context, str), in: context) // In Kotlin, delegating calls to 'self' or 'super' constructors can not use local variables other than the parameters passed to this constructor
    }

    /// Creates a JavaScript value of the `Symbol` type.
    ///
    /// - Parameters:
    ///   - value: The value to assign to the object.
    ///   - context: The execution context to use.
    public convenience init(symbol value: String, in context: JSContext) {
        let sym = value.withCString(JavaScriptCore.JSStringCreateWithUTF8CString)
        defer { JavaScriptCore.JSStringRelease(sym) }
        self.init(jsValueRef: JavaScriptCore.JSValueMakeSymbol(context.context, sym), in: context) // In Kotlin, delegating calls to 'self' or 'super' constructors can not use local variables other than the parameters passed to this constructor
    }
    #endif

    /// Creates a JavaScript value of the parsed `JSON`.
    ///
    /// - Parameters:
    ///   - value: The JSON value to parse
    ///   - context: The execution context to use.
//    convenience init?(json value: String, in context: JSContext) {
//        let value = value.withCString(JSStringCreateWithUTF8CString)
//        defer { JSStringRelease(value) }
//        guard let json = JavaScriptCore.JSValueMakeFromJSONString(context.contextRef, value) else {
//            return nil // We just return nil since there is no error parameter
//        }
//        self.init(context: context, valueRef: json)
//    }

    /// Creates a JavaScript `Date` object, as if by invoking the built-in `JSObjectMakeDate` constructor.
    ///
    /// - Parameters:
    ///   - value: The value to assign to the object.
    ///   - context: The execution context to use.
//    public convenience init(date value: Date, in context: JSContext) throws {
//        let arguments = [JavaScriptCore.JSValue(string: JSValue.rfc3339.string(from: value), in: context)]
//        let object = try context.trying {
//            JavaScriptCore.JSObjectMakeDate(context.contextRef, 1, arguments.map { $0.valueRef }, $0)
//        }
//        self.init(context: context, valueRef: object!)
//    }

    /// Creates a JavaScript `RegExp` object, as if by invoking the built-in `RegExp` constructor.
    ///
    /// - Parameters:
    ///   - pattern: The pattern of regular expression.
    ///   - flags: The flags pass to the constructor.
    ///   - context: The execution context to use.
//    public convenience init(newRegularExpressionFromPattern pattern: String, flags: String, in context: JavaScriptCore.JSContext) throws {
//        let arguments = [JavaScriptCore.JSValue(string: pattern, in: context), JavaScriptCore.JSValue(string: flags, in: context)]
//        let object = try context.trying {
//            JavaScriptCore.JSObjectMakeRegExp(context.contextRef, 2, arguments.map { $0.valueRef }, $0)
//        }
//        self.init(context: context, valueRef: object!)
//    }

    /// Creates a JavaScript `Object`.
    ///
    /// - Parameters:
    ///   - context: The execution context to use.
    public convenience init(newObjectIn context: JSContext) {
        #if !SKIP
        self.init(jsValueRef: JavaScriptCore.JSObjectMake(context.context, nil, nil), in: context)
        #else
        // Workaround for Skip error: "In Kotlin, delegating calls to 'self' or 'super' constructors can not use local variables other than the parameters passed to this constructor"
        self.init(jsValueRef: JavaScriptCoreLibrary.instance.JSObjectMake(context.context, nil, nil), in: context)
        #endif
    }

    /// Creates a JavaScript `Object` with prototype.
    ///
    /// - Parameters:
    ///   - context: The execution context to use.
    ///   - prototype: The prototype to be used.
//    public convenience init(newObjectIn context: JSContext, prototype: JSValue) throws {
//        let obj = try context.objectPrototype.invokeMethod("create", withArguments: [prototype])
//        self.init(jsValueRef: obj.valueRef, in: context)
//    }

    /// Creates a JavaScript `Array` object.
    ///
    /// - Parameters:
    ///   - context: The execution context to use.
//    public convenience init(newArrayIn context: JSContext, values: [JSValue]? = nil) throws {
//        let array = JavaScriptCore.JSObjectMakeArray(context.contextRef, 0, nil, context)
//        self.init(jsValueRef: array!, in: context)
//        if let values = values {
//            for (index, element) in values.enumerated() {
//                try self.setElement(element, at: index)
//            }
//        }
//    }
}

#if SKIP
// workaround for inability to implement this as a convenience constructor due to needing local variables: In Kotlin, delegating calls to 'self' or 'super' constructors can not use local variables other than the parameters passed to this constructor
public func JSValue(string value: String, in context: JSContext) -> JSValue {
    let str = JavaScriptCore.JSStringCreateWithUTF8CString(value)
    defer { JavaScriptCore.JSStringRelease(str) }
    return JSValue(jsValueRef: JavaScriptCore.JSValueMakeString(context.context, str), in: context)
}
#endif


public struct JSCError : Error {
    let errorDescription: String

    init(message errorDescription: String) {
        self.errorDescription = errorDescription
    }
}


/// An error thrown from JavaScript
public struct JSError: Error, CustomStringConvertible {
    public var errorMessage: String
    public var errorCause: Error?
    public var jsErrorString: String?
    public var script: String?

    public init(message: String, script: String? = nil, cause: Error? = nil, jsErrorString: String? = nil) {
        self.errorMessage = message
        self.script = script
        self.errorCause = cause
        self.jsErrorString = jsErrorString
    }

    #if !SKIP
    // No support for JSErrorPeer from Skip at this point
    public init(jsError: JSValue, script: String? = nil) {
        if let cause = jsError.cause {
            self.errorMessage = String(describing: cause)
            self.script = script
            self.errorCause = cause
        } else {
            self.errorMessage = jsError.toString()
            self.script = script
        }
    }
    #endif

    public init(cause: Error, script: String? = nil) {
        if let jserror = cause as? JSError {
            self.errorMessage = jserror.errorMessage
            self.script = jserror.script
            self.jsErrorString = jserror.jsErrorString
            self.script = jserror.script
            if let script {
                self.script = script
            }
        } else {
            self.errorMessage = String(describing: cause)
            self.script = script
            self.errorCause = cause
        }
    }

//    public var localizedDescription: String {
//        return description
//    }

    public var description: String {
        return errorMessage // + scriptDescription
    }
}



/// A function definition, used when defining callbacks.
public typealias JSFunction = (_ ctx: JSContext, _ obj: JSValue?, _ args: [JSValue]) throws -> JSValue
public typealias JSPromise = (promise: JSValue, resolveFunction: JSValue, rejectFunction: JSValue)

private struct _JSFunctionInfoHandle {
    unowned let context: JSContext
    let callback: JSFunction
}

#if !SKIP
/// The pointer we store is the actual handle to the context and callback, which we can do in Swift but not Java/JNA.
private typealias JSFunctionInfo = _JSFunctionInfoHandle
#else
/// In Swift we stash the pointer to the `JSFunctionInfo` struct in the function object's private data, and then re-create it when we need it.
/// We can't do that in JNA, since there isn't any way to recreate a Java instance from a JNA com.sun.jna.ptr.PointerByReference.
/// So instead we use the private data of the function object to store an index in a global synchronized weak hash map.
/// Note that we intentionally key on the created JSFunctionInfo, because if it is garbage collected by Java, the underlying JSC representation will be backed by an empty value.
private let _functionCallbacks: [JSFunctionInfo: _JSFunctionInfoHandle?] = [:]
/// Internal global counter of all the registered functions, used as the key for the `_functionCallbacks` map.
/// We start at 1 to ensure that the value is never zero (indicating that the underlying Java instance was garbage collected).
private var _functionCounter: Int64 = 1

// SKIP INSERT: @com.sun.jna.Structure.FieldOrder("id")
public final class JSFunctionInfo : com.sun.jna.Structure {
    // SKIP INSERT: @JvmField
    public var id: Int64 = 0

    /// Lookup the context by the global id
    var context: JSContext? {
        synchronized(_functionCallbacks) {
            return _functionCallbacks[self]?.context
        }
    }

    /// Lookup the callback by the global id
    var callback: JSFunction? {
        synchronized(_functionCallbacks) {
            return _functionCallbacks[self]?.callback
        }
    }

    fileprivate init(ptr: OpaquePointer) {
        super.init(ptr)
        read() // read id from the struct
    }

    init(context: JSContext, callback: JSFunction) {
        // ideally, we'd at least keep this in a per-context map rather than a global map, but then we'd have the same problem with restoring a java JSContext instance from a pointer, so we'd need to keep another global map around
        synchronized(_functionCallbacks) {
            self.id = _functionCounter
            _functionCounter += 1
            _functionCallbacks[self] = _JSFunctionInfoHandle(context: context, callback: callback)
        }
        write() // save id to the struct
    }

    public override func equals(other: Any?) -> Bool {
        (other as? JSFunctionInfo)?.id == self.id
    }

    public override func hashCode() -> Int {
        id.hashCode()
    }

    /// Clear the global function pointer callback for this instance
    func clearCallback() {
        synchronized(_functionCallbacks) {
            _functionCallbacks[self] = nil
        }
    }


}
#endif


// MARK: JSFunctionCallback

#if !SKIP

private func JSFunctionCallback(_ jsc: JSContextRef?, _ object: JSObjectRef?, _ this: JSObjectRef?, _ argumentCount: Int, _ arguments: UnsafePointer<JSValueRef?>?, _ exception: UnsafeMutablePointer<JSValueRef?>?) -> JSValueRef? {

    let info = JSObjectGetPrivate(object).assumingMemoryBound(to: JSFunctionInfo.self)
    let context = info.pointee.context

    do {
        let this = this.map { JSValue(jsValueRef: $0, in: context) }
        let arguments = (0..<argumentCount).map { JSValue(jsValueRef: arguments![$0]!, in: context) }
        let result = try info.pointee.callback(context, this, arguments)
        return result.value
    } catch {
        let error = JSValue(newErrorFromCause: error, in: context)
        exception?.pointee = error.value
        return nil
    }
}

#else

private let JSFunctionCallback = JSFunctionCallbackImpl()

private final class JSFunctionCallbackImpl : JSCallbackFunction {
    init() {
    }

    public func callback(_ jsc: JSContextRef?, _ object: JSObjectRef?, _ this: JSObjectRef?, _ argumentCount: Int, _ arguments: UnsafePointer<JSValueRef?>?, _ exception: UnsafeMutablePointer<JSValueRef?>?) -> JSValueRef? {
        guard let object = object,
              let data = JavaScriptCore.JSObjectGetPrivate(object) else {
            preconditionFailure("SkipScript: unable to find private object data for \(object)")
            return nil
        }

        let info = JSFunctionInfo(ptr: data)
        guard let context = info.context,
              let callback = info.callback else {
            preconditionFailure("SkipScript: unable to find context or callback for private object pointer \(data)")
            return nil
        }

        let argptrs = argumentCount == 0 ? nil : arguments!.getPointerArray(0, argumentCount)
        let args: [JSValue] = (0..<argumentCount).map {
            JSValue(jsValueRef: argptrs![$0], in: context)
        }
        let this = this.map { JSValue(jsValueRef: $0, in: context) }
        let value: JSValue = callback(context, this, args)
        return value.value
    }
}

#endif

// MARK: JSFunctionFinalize

#if !SKIP

private func JSFunctionFinalize(_ object: JSObjectRef?) -> Void {
    let info = JSObjectGetPrivate(object).assumingMemoryBound(to: JSFunctionInfo.self)
    info.deinitialize(count: 1)
    info.deallocate()
}

#else

private let JSFunctionFinalize = JSFunctionFinalizeImpl()
private final class JSFunctionFinalizeImpl : JSCallbackFunction {
    init() {
    }

    public func callback(_ object: JSObjectRef?) -> Void {
        guard let object = object,
              let data = JavaScriptCore.JSObjectGetPrivate(object) else {
            preconditionFailure("SkipScript: unable to find private object data for \(object)")
            return
        }
        let info = JSFunctionInfo(ptr: data)
        if info.id == Int64(0) {
            preconditionFailure("SkipScript: JSFunctionInfo id=0 from pointer: \(data)")
        }

        // clear the info from the global map so we can finalize the function instance (and any references it contains)
        info.clearCallback()
    }
}

#endif


// MARK: JSFunctionInstanceOf

#if !SKIP

private func JSFunctionInstanceOf(_ jsc: JSContextRef?, _ constructor: JSObjectRef?, _ possibleInstance: JSValueRef?, _ exception: UnsafeMutablePointer<JSValueRef?>?) -> Bool {
    let info = JSObjectGetPrivate(constructor).assumingMemoryBound(to: JSFunctionInfo.self)
    let context = info.pointee.context
    let pt1 = JSObjectGetPrototype(context.context, constructor)
    let pt2 = JSObjectGetPrototype(context.context, possibleInstance)
    return JSValueIsStrictEqual(context.context, pt1, pt2)
}

#else

private let JSFunctionInstanceOf = JSFunctionInstanceOfImpl()
private final class JSFunctionInstanceOfImpl : JSCallbackFunction {
    init() {
    }

    public func callback(_ jsc: JSContextRef?, _ constructor: JSObjectRef?, _ possibleInstance: JSValueRef?, _ exception: UnsafeMutablePointer<JSValueRef?>?) -> Bool {
        fatalError("### TODO: JSFunctionInstanceOf")
        return false
    }
}

#endif

// MARK: JSFunctionConstructor

#if !SKIP

private func JSFunctionConstructor(_ jsc: JSContextRef?, _ object: JSObjectRef?, _ argumentCount: Int, _ arguments: UnsafePointer<JSValueRef?>?, _ exception: UnsafeMutablePointer<JSValueRef?>?) -> JSObjectRef? {

    let info = JSObjectGetPrivate(object).assumingMemoryBound(to: JSFunctionInfo.self)
    let context = info.pointee.context

    do {
        let arguments = (0..<argumentCount).map { JSValue(jsValueRef: arguments![$0]!, in: context) }
        let result = try info.pointee.callback(context, nil, arguments)

        let prototype = JSObjectGetPrototype(context.context, object)
        JSObjectSetPrototype(context.context, result.value, prototype)

        return result.value
    } catch {
        let error = JSValue(newErrorFromCause: error, in: context)
        exception?.pointee = error.value
        return nil
    }
}

#else

private let JSFunctionConstructor = JSFunctionConstructorImpl()
private final class JSFunctionConstructorImpl : JSCallbackFunction {
    init() {
    }

    public func callback(_ jsc: JSContextRef?, _ object: JSObjectRef?, _ argumentCount: Int, _ arguments: UnsafePointer<JSValueRef?>?, _ exception: UnsafeMutablePointer<JSValueRef?>?) -> JSObjectRef? {
        fatalError("### TODO: JSFunctionConstructor")
        return nil
    }
}

#endif


#if !SKIP

/// Used internally to piggyback a native error as the peer of its wrapping JSValue error object.
class JSErrorPeer {
    let error: Error

    init(error: Error) {
        self.error = error
    }
}

extension JSValue {
    /// A peer is an instance of `AnyObject` that is created from ``JXContext/object(peer:)`` with a peer argument.
    ///
    /// The peer cannot be changed once an object has been initialized with it.
    public var peer: AnyObject? {
        get {
            guard isObject, !isFunction, let ptr = JSObjectGetPrivate(value) else {
                return nil
            }
            return ptr.assumingMemoryBound(to: AnyObject?.self).pointee
        }
    }

    /// The cause passed to ``JXContext/error(_:)``.
    public var cause: Error? {
        get {
            guard let causeValue = try? self["cause"], let errorPeer = causeValue.peer as? JSErrorPeer else {
                return nil
            }
            return errorPeer.error
        }
    }
}

#endif

#if SKIP
fileprivate extension Int {
    // stub extension to allow us to handle when JSType is an enum and a bare int
    var rawValue: Int { self }
}
#endif



#if SKIP

// workaround for Skip converting "JavaScriptCode.self.javaClass" to "(JavaScriptCoreLibrary::class.companionObjectInstance as JavaScriptCoreLibrary.Companion).java)"
// SKIP INSERT: fun <T : Any> javaClass(kotlinClass: kotlin.reflect.KClass<T>): Class<T> { return kotlinClass.java }

/// A JavaScript value. The base type for all JavaScript values, and polymorphic functions on them.
typealias OpaqueJSValue = OpaquePointer
typealias VoidPointer = OpaquePointer

typealias JSValuePointer = UnsafeMutableRawPointer

typealias JSValueRef = OpaqueJSValue
typealias JSStringRef = OpaqueJSValue
typealias JSObjectRef = OpaqueJSValue
typealias JSContextRef = OpaqueJSValue
typealias JSClassRef = OpaqueJSValue

public typealias JSCallbackFunction = com.sun.jna.Callback

public typealias JSClassAttributes = Int32 // typedef unsigned JSClassAttributes

public typealias JSObjectInitializeCallback = JSCallbackFunction // (*JSObjectInitializeCallback) (JSContextRef ctx, JSObjectRef object)
public typealias JSObjectFinalizeCallback = JSCallbackFunction // (*JSObjectFinalizeCallback) (JSObjectRef object)
public typealias JSObjectHasPropertyCallback = JSCallbackFunction // (*JSObjectHasPropertyCallback) (JSContextRef ctx, JSObjectRef object, JSStringRef propertyName)
public typealias JSObjectGetPropertyCallback = JSCallbackFunction // (*JSObjectGetPropertyCallback) (JSContextRef ctx, JSObjectRef object, JSStringRef propertyName, JSValueRef* exception)
public typealias JSObjectSetPropertyCallback = JSCallbackFunction // (*JSObjectSetPropertyCallback) (JSContextRef ctx, JSObjectRef object, JSStringRef propertyName, JSValueRef value, JSValueRef* exception)
public typealias JSObjectDeletePropertyCallback = JSCallbackFunction // (*JSObjectDeletePropertyCallback) (JSContextRef ctx, JSObjectRef object, JSStringRef propertyName, JSValueRef* exception)
public typealias JSObjectGetPropertyNamesCallback = JSCallbackFunction // (*JSObjectGetPropertyNamesCallback) (JSContextRef ctx, JSObjectRef object, JSPropertyNameAccumulatorRef propertyNames)
public typealias JSObjectCallAsFunctionCallback = JSCallbackFunction // (*JSObjectCallAsFunctionCallback) (JSContextRef ctx, JSObjectRef function, JSObjectRef thisObject, size_t argumentCount, const JSValueRef arguments[], JSValueRef* exception)
public typealias JSObjectCallAsConstructorCallback = JSCallbackFunction // (*JSObjectCallAsConstructorCallback) (JSContextRef ctx, JSObjectRef constructor, size_t argumentCount, const JSValueRef arguments[], JSValueRef* exception)
public typealias JSObjectHasInstanceCallback = JSCallbackFunction // (*JSObjectHasInstanceCallback)  (JSContextRef ctx, JSObjectRef constructor, JSValueRef possibleInstance, JSValueRef* exception)
public typealias JSObjectConvertToTypeCallback = JSCallbackFunction // (*JSObjectConvertToTypeCallback) (JSContextRef ctx, JSObjectRef object, JSType type, JSValueRef* exception)


/// A partial implementation of the JavaScriptCore C interface exposed as a JNA library.
final class JavaScriptCoreLibrary : com.sun.jna.Library {
    public static let instance = JavaScriptCoreLibrary()

    /* SKIP EXTERN */ public func JSStringRetain(_ string: JSStringRef) -> JSStringRef
    /* SKIP EXTERN */ public func JSStringRelease(_ string: JSStringRef)
    /* SKIP EXTERN */ public func JSStringIsEqual(_ string1: JSStringRef, _ string2: JSStringRef) -> Bool
    /* SKIP EXTERN */ public func JSStringGetLength(_ string: JSStringRef) -> Int
    /* SKIP EXTERN */ public func JSStringGetMaximumUTF8CStringSize(_ string: JSStringRef) -> Int
    /* SKIP EXTERN */ public func JSStringGetCharactersPtr(_ string: JSStringRef) -> OpaquePointer
    /* SKIP EXTERN */ public func JSStringGetUTF8CString(_ string: JSStringRef, _ buffer: OpaquePointer, _ bufferSize: Int) -> Int
    /* SKIP EXTERN */ public func JSStringCreateWithUTF8CString(_ string: String) -> JSStringRef
    /* SKIP EXTERN */ public func JSStringIsEqualToUTF8CString(_ stringRef: JSStringRef, _ string: String) -> Bool

    /* SKIP EXTERN */ public func JSGlobalContextCreate(_ globalObjectClass: JSValueRef?) -> JSContextRef
    /* SKIP EXTERN */ public func JSGlobalContextRetain(_ ctx: JSContextRef)
    /* SKIP EXTERN */ public func JSGlobalContextRelease(_ ctx: JSContextRef)
    /* SKIP EXTERN */ public func JSContextGetGlobalObject(_ ctx: JSContextRef) -> JSObjectRef

    /* SKIP EXTERN */ public func JSEvaluateScript(_ ctx: JSContextRef, script: JSStringRef, thisObject: JSValueRef?, sourceURL: String?, startingLineNumber: Int, exception: ExceptionPtr?) -> JSValueRef

    /* SKIP EXTERN */ public func JSGarbageCollect(_ ctx: JSContextRef)
    /* SKIP EXTERN */ public func JSValueProtect(_ ctx: JSContextRef, _ value: JSValueRef)
    /* SKIP EXTERN */ public func JSValueUnprotect(_ ctx: JSContextRef, _ value: JSValueRef)
    /* SKIP EXTERN */ public func JSValueGetType(_ ctx: JSContextRef, _ value: JSValueRef) -> Int

    /* SKIP EXTERN */ public func JSValueIsUndefined(_ ctx: JSContextRef, _ value: JSValueRef) -> Bool
    /* SKIP EXTERN */ public func JSValueIsNull(_ ctx: JSContextRef, _ value: JSValueRef) -> Bool
    /* SKIP EXTERN */ public func JSValueIsBoolean(_ ctx: JSContextRef, _ value: JSValueRef) -> Bool
    /* SKIP EXTERN */ public func JSValueIsNumber(_ ctx: JSContextRef, _ value: JSValueRef) -> Bool
    /* SKIP EXTERN */ public func JSValueIsString(_ ctx: JSContextRef, _ value: JSValueRef) -> Bool
    /* SKIP EXTERN */ public func JSValueIsSymbol(_ ctx: JSContextRef, _ value: JSValueRef) -> Bool
    /* SKIP EXTERN */ public func JSObjectIsFunction(_ ctx: JSContextRef, _ value: JSValueRef) -> Bool
    /* SKIP EXTERN */ public func JSValueIsObject(_ ctx: JSContextRef, _ value: JSValueRef) -> Bool
    /* SKIP EXTERN */ public func JSValueIsArray(_ ctx: JSContextRef, _ value: JSValueRef) -> Bool
    /* SKIP EXTERN */ public func JSValueIsDate(_ ctx: JSContextRef, _ value: JSValueRef) -> Bool

    /* SKIP EXTERN */ public func JSValueIsEqual(_ ctx: JSContextRef, _ a: JSValueRef, _ b: JSValueRef, _ exception: ExceptionPtr?) -> Boolean
    /* SKIP EXTERN */ public func JSValueIsStrictEqual(_ ctx: JSContextRef, _ a: JSValueRef, _ b: JSValueRef) -> Boolean

    /* SKIP EXTERN */ public func JSValueIsInstanceOfConstructor(_ ctx: JSContextRef, _ value: JSValueRef, _ constructor: JSObjectRef, _ exception: ExceptionPtr?) -> Boolean

    /* SKIP EXTERN */ public func JSValueToBoolean(_ ctx: JSContextRef, _ value: JSValueRef) -> Boolean
    /* SKIP EXTERN */ public func JSValueToNumber(_ ctx: JSContextRef, _ value: JSValueRef, _ exception: ExceptionPtr?) -> Double
    /* SKIP EXTERN */ public func JSValueToStringCopy(_ ctx: JSContextRef, _ value: JSValueRef, _ exception: ExceptionPtr?) -> JSStringRef
    /* SKIP EXTERN */ public func JSValueToObject(_ ctx: JSContextRef, _ value: JSValueRef, _ exception: ExceptionPtr?) -> JSObjectRef

    /* SKIP EXTERN */ public func JSValueMakeUndefined(_ ctx: JSContextRef) -> JSValueRef
    /* SKIP EXTERN */ public func JSValueMakeNull(_ ctx: JSContextRef) -> JSValueRef
    /* SKIP EXTERN */ public func JSValueMakeBoolean(_ ctx: JSContextRef, _ value: Boolean) -> JSValueRef
    /* SKIP EXTERN */ public func JSValueMakeNumber(_ ctx: JSContextRef, _ value: Double) -> JSValueRef
    /* SKIP EXTERN */ public func JSValueMakeString(_ ctx: JSContextRef, _ value: JSStringRef) -> JSValueRef
    /* SKIP EXTERN */ public func JSValueMakeSymbol(_ ctx: JSContextRef, _ value: JSStringRef) -> JSValueRef
    /* SKIP EXTERN */ public func JSValueMakeFromJSONString(_ ctx: JSContextRef, _ json: JSStringRef) -> JSValueRef
    /* SKIP EXTERN */ public func JSValueCreateJSONString(_ ctx: JSContextRef, _ value: JSValueRef, _ indent: Int32, _ exception: ExceptionPtr?) -> JSStringRef

    /* SKIP EXTERN */ public func JSObjectGetProperty(_ ctx: JSContextRef, _ obj: JSValueRef, _ propertyName: JSStringRef, _ exception: ExceptionPtr?) -> JSValueRef
    /* SKIP EXTERN */ public func JSObjectSetProperty(_ ctx: JSContextRef, _ obj: JSValueRef, propertyName: JSStringRef, _ value: JSValueRef, _ attributes: JSPropertyAttributes, _ exception: ExceptionPtr?)

    /* SKIP EXTERN */ public func JSObjectGetPropertyAtIndex(_ ctx: JSContextRef, _ obj: JSValueRef, _ propertyIndex: Int, _ exception: ExceptionPtr?) -> JSValueRef
    /* SKIP EXTERN */ public func JSObjectSetPropertyAtIndex(_ ctx: JSContextRef, _ obj: JSValueRef, propertyIndex: Int, _ value: JSValueRef, _ exception: ExceptionPtr?)

    /* SKIP EXTERN */ public func JSObjectMakeFunctionWithCallback(_ ctx: JSContextRef, _ name: JSStringRef, _ callAsFunction: JSObjectCallAsFunctionCallback) -> JSObjectRef
    /* SKIP EXTERN */ public func JSObjectMake(_ ctx: JSContextRef, _ jsClass: JSClassRef?, _ data: OpaqueJSValue?) -> JSObjectRef

    /* SKIP EXTERN */ public func JSObjectCallAsFunction(_ ctx: JSContextRef, _ object: OpaquePointer?, _ thisObject: OpaquePointer?, _ argumentCount: Int32, _ arguments: OpaquePointer?, _ exception: ExceptionPtr?) -> JSValueRef

    /* SKIP EXTERN */ public func JSClassCreate(_ cls: JSClassDefinition) -> JSClassRef
    /* SKIP EXTERN */ public func JSClassRetain(_ cls: JSClassRef) -> JSClassRef
    /* SKIP EXTERN */ public func JSClassRelease(_ cls: JSClassRef) -> Void

    /* SKIP EXTERN */ public func JSObjectSetPrivate(_ jsObject: JSObjectRef, _ privateData: VoidPointer?)
    /* SKIP EXTERN */ public func JSObjectGetPrivate(_ jsObject: JSObjectRef) -> VoidPointer?

    private init() {
        #if SKIP
        let isAndroid = System.getProperty("java.vm.vendor") == "The Android Project"
        // on Android we use the embedded libjsc.so; on macOS host, use the system JavaScriptCore
        let jscName = isAndroid ? "jsc" : "JavaScriptCore"
        if isAndroid {
            System.loadLibrary("c++_shared") // io.github.react-native-community:jsc-android-intl requires this, provided in com.facebook.fbjni:fbjni
        }
        com.sun.jna.Native.register((JavaScriptCoreLibrary.self as kotlin.reflect.KClass).java, jscName)
        #endif
    }
}

// SKIP INSERT: @com.sun.jna.Structure.FieldOrder("version", "attributes", "className", "parentClass", "staticValues", "staticFunctions", "initialize", "finalize", "hasProperty", "getProperty", "setProperty", "deleteProperty", "getPropertyNames", "callAsFunction", "callAsConstructor", "hasInstance", "convertToType")
public final class JSClassDefinition : SkipFFIStructure {

    public init(version: Int32 = 0, attributes: JSClassAttributes = Int32(0), className: OpaquePointer? = nil, parentClass: JSClassRef? = nil, staticValues: OpaquePointer? = nil, staticFunctions: OpaquePointer? = nil, initialize: JSObjectInitializeCallback? = nil, finalize: JSObjectFinalizeCallback? = nil, hasProperty: JSObjectHasPropertyCallback? = nil, getProperty: JSObjectGetPropertyCallback? = nil, setProperty: JSObjectSetPropertyCallback? = nil, deleteProperty: JSObjectDeletePropertyCallback? = nil, getPropertyNames: JSObjectGetPropertyNamesCallback? = nil, callAsFunction: JSObjectCallAsFunctionCallback? = nil, callAsConstructor: JSObjectCallAsConstructorCallback? = nil, hasInstance: JSObjectHasInstanceCallback? = nil, convertToType: JSObjectConvertToTypeCallback? = nil) {
        self.version = version
        self.attributes = attributes
        self.className = className
        self.parentClass = parentClass
        self.staticValues = staticValues
        self.staticFunctions = staticFunctions
        self.initialize = initialize
        self.finalize = finalize
        self.hasProperty = hasProperty
        self.getProperty = getProperty
        self.setProperty = setProperty
        self.deleteProperty = deleteProperty
        self.getPropertyNames = getPropertyNames
        self.callAsFunction = callAsFunction
        self.callAsConstructor = callAsConstructor
        self.hasInstance = hasInstance
        self.convertToType = convertToType
    }

    // SKIP INSERT: @JvmField
    public var version: Int32 /* current (and only) version is 0 */

    // SKIP REPLACE: @JvmField var attributes: JSClassAttributes?
    public var attributes: JSClassAttributes

    // SKIP REPLACE: @JvmField var className: OpaquePointer?
    public var className: UnsafePointer<CChar>!

    // SKIP REPLACE: @JvmField var parentClass: OpaquePointer?
    public var parentClass: JSClassRef!


    // SKIP REPLACE: @JvmField var staticValues: OpaquePointer?
    public var staticValues: UnsafePointer<JSStaticValue>!

    // SKIP REPLACE: @JvmField var staticFunctions: OpaquePointer?
    public var staticFunctions: UnsafePointer<JSStaticFunction>!

    // SKIP REPLACE: @JvmField var initialize: JSObjectInitializeCallback?
    public var initialize: JSObjectInitializeCallback!

    // SKIP REPLACE: @JvmField var finalize: JSObjectFinalizeCallback?
    public var finalize: JSObjectFinalizeCallback!

    // SKIP REPLACE: @JvmField var hasProperty: JSObjectHasPropertyCallback?
    public var hasProperty: JSObjectHasPropertyCallback!

    // SKIP REPLACE: @JvmField var getProperty: JSObjectGetPropertyCallback?
    public var getProperty: JSObjectGetPropertyCallback!

    // SKIP REPLACE: @JvmField var setProperty: JSObjectSetPropertyCallback?
    public var setProperty: JSObjectSetPropertyCallback!

    // SKIP REPLACE: @JvmField var deleteProperty: JSObjectDeletePropertyCallback?
    public var deleteProperty: JSObjectDeletePropertyCallback!

    // SKIP REPLACE: @JvmField var getPropertyNames: JSObjectGetPropertyNamesCallback?
    public var getPropertyNames: JSObjectGetPropertyNamesCallback!

    // SKIP REPLACE: @JvmField var callAsFunction: JSObjectCallAsFunctionCallback?
    public var callAsFunction: JSObjectCallAsFunctionCallback!

    // SKIP REPLACE: @JvmField var callAsConstructor: JSObjectCallAsConstructorCallback?
    public var callAsConstructor: JSObjectCallAsConstructorCallback!

    // SKIP REPLACE: @JvmField var hasInstance: JSObjectHasInstanceCallback?
    public var hasInstance: JSObjectHasInstanceCallback!

    // SKIP REPLACE: @JvmField var convertToType: JSObjectConvertToTypeCallback?
    public var convertToType: JSObjectConvertToTypeCallback!
}

public typealias JSPropertyAttributes = Int32

/// Specifies that a property has no special attributes.
public let kJSPropertyAttributeNone: JSPropertyAttributes = Int32(0)
/// Specifies that a property is read-only.
public let kJSPropertyAttributeReadOnly: JSPropertyAttributes = Int32(1) << 1
/// Specifies that a property should not be enumerated by JSPropertyEnumerators and JavaScript for...in loops.
public let kJSPropertyAttributeDontEnum: JSPropertyAttributes = Int32(1) << 2
/// Specifies that the delete operation should fail on a property.
public let kJSPropertyAttributeDontDelete: JSPropertyAttributes = Int32(1) << 3

#endif
