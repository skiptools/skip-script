// Copyright 2023 Skip
//
// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org
#if !SKIP
import Foundation
// Non-Skip uses the JavaScriptCore symbols directly
import JavaScriptCore
public typealias ExceptionPtr = UnsafeMutablePointer<JSValueRef?>
#else
import SkipFFI
typealias ExceptionPtr = JSValuePointer
#endif

/// A context for evaluating JavaScipt.
public class JSContext {
    public let context: JSContextRef
    public private(set) var exception: JSValue? = nil

    public init(jsGlobalContextRef context: JSContextRef) {
        self.context = context
    }

    public init() {
        self.context = JavaScriptCore.JSGlobalContextCreate(nil)
    }

    deinit {
        JavaScriptCore.JSGlobalContextRelease(context)
    }

    @discardableResult fileprivate func clearException(_ exception: ExceptionPtr? = nil) -> Bool {
        if let exception = exception {
            // errors are handled by returning nil and setting the current exception poinrts
            #if SKIP
            let errorPtr: OpaquePointer? = exception.value
            #else
            let errorPtr: JavaScriptCore.JSValueRef? = exception.pointee
            #endif

            if let error = errorPtr {
                self.exception = JSValue(jsValueRef: error, in: self)
                return false
            }
        }

        // clear the current exception
        self.exception = nil
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

    public func setObject(_ object: Any, forKeyedSubscript key: String) {
        let propName = JavaScriptCore.JSStringCreateWithUTF8CString("key")
        defer { JavaScriptCore.JSStringRelease(propName) }
        let exception = ExceptionPtr(nil)
        let valueRef = (object as? JSValue)?.value ?? JSValue(object: object, in: self).value
        JavaScriptCore.JSObjectSetProperty(context, context, propName, valueRef, JSPropertyAttributes(kJSPropertyAttributeNone), exception)
    }

    public func objectForKeyedSubscript(_ key: String) -> JSValue {
        let propName = JavaScriptCore.JSStringCreateWithUTF8CString("key")
        defer { JavaScriptCore.JSStringRelease(propName) }

        let exception = ExceptionPtr(nil)
        let value = JavaScriptCore.JSObjectGetProperty(context, context, propName, exception)
        if !clearException(exception) {
            return JSValue(nullIn: self)
        } else if let value = value {
            return JSValue(jsValueRef: value, in: self)
        } else {
            return JSValue(nullIn: self)
        }
    }

    #if !SKIP
    private var tryingRecursionGuard = false

    /// Attempts the operation whose failure is expected to set the given error pointer.
    ///
    /// When the error pointer is set, a ``JSError`` will be thrown.
    func trying<T>(function: (UnsafeMutablePointer<JSValueRef?>) throws -> T?) throws -> T! {
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
    }

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

    /// Performs a JavaScript garbage collection.
    ///
    /// During JavaScript execution, you are not required to call this function; the JavaScript engine will garbage collect as needed.
    /// JavaScript values created within a context group are automatically destroyed when the last reference to the context group is released.
    public func garbageCollect() { JSGarbageCollect(context) }

    /// The global object.
    public var global: JSValue {
        JSValue(jsValueRef: JSContextGetGlobalObject(context), in: self)
    }
    #endif
}

/// A JSValue is a reference to a JavaScript value. 
///
/// Every JSValue originates from a JSContext and holds a strong reference to it.
public class JSValue {
    public let context: JSContext
    public let value: JSValueRef

    public init(jsValueRef: JSValueRef, in context: JSContext) {
        JavaScriptCore.JSValueProtect(context.context, jsValueRef)
        self.context = context
        self.value = jsValueRef
    }

    public init(nullIn context: JSContext) {
        self.context = context
        self.value = JavaScriptCore.JSValueMakeNull(context.context)
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

            // FIXME: crash
//        case let str as String:
//            self.value = JavaScriptCore.JSStringCreateWithUTF8CString(str)

        default:
            self.value = JavaScriptCore.JSValueMakeNull(context.context)
        }
    }

    /// Creates a JavaScript value of the function type.
    ///
    /// - Parameters:
    ///   - context: The execution context to use.
    ///   - callback: The callback function.
    /// - Note: This object is callable as a function (due to `JSClassDefinition.callAsFunction`), but the JavaScript runtime doesn't treat it exactly like a function. For example, you cannot call "apply" on it. It could be better to use `JSObjectMakeFunctionWithCallback`, which may act more like a "true" JavaScript function.
    public init(newFunctionIn context: JSContext, callback: @escaping JSFunction) {
        var def = JSClassDefinition()
        let callbackInfo = JSFunctionInfo(context: context, callback: callback)
        def.finalize = JSFunctionFinalize // JNA: JSFunctionFinalizeImpl()
        def.callAsConstructor = JSFunctionConstructor // JNA: JSFunctionConstructorImpl()
        def.callAsFunction = JSFunctionCallback // JNA: JSFunctionCallbackImpl()
        def.hasInstance = JSFunctionInstanceOf // JNA: JSFunctionInstanceOf()

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
        //self.init(jsValueRef: value, in: context)
        JavaScriptCore.JSValueProtect(context.context, jsValueRef)
        self.context = context
        self.value = jsValueRef!

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
//        if !isObject {
//            throw JSError.valueNotPropertiesObject(self, property: key)
//        }

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
                return nil // TODO
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
    @discardableResult public func call(withArguments arguments: [JSValue] = [], this: JSValue? = nil) -> JSValue {
//        if !isFunction {
//            // we should have already validated that it is a function
//            throw JSError.valueNotFunction(self)
//        }
//        do {
//            let resultRef = try context.trying {
//                JSObjectCallAsFunction(context.contextRef, valueRef, this?.valueRef, arguments.count, arguments.isEmpty ? nil : arguments.map { $0.valueRef }, $0)
//            }
//            return resultRef.map({ JSValue(context: context, valueRef: $0) }) ?? JSValue(undefinedIn: context)
//        } catch {
//            throw JSError(cause: error, script: (try? self.string))
//        }

        // TODO: handle error
        #if !SKIP
        guard let result = JavaScriptCore.JSObjectCallAsFunction(self.context.context, self.value, nil, arguments.count, arguments.map({ $0.value }), nil) else {
            return JSValue(nullIn: self.context)
        }
        #else
        let pointerSize: Int32 = com.sun.jna.Native.POINTER_SIZE
        let size = Int64(arguments.count * pointerSize)
        let argptr = com.sun.jna.Memory(size)
        defer { argptr.clear(size) }
        for i in (0..<arguments.count) {
            argptr.setPointer(i.toLong() * pointerSize, arguments[i].value)
        }
        guard let result = JavaScriptCore.JSObjectCallAsFunction(self.context.context, self.value, nil, arguments.count, com.sun.jna.ptr.PointerByReference(argptr), nil) else {
            return JSValue(nullIn: self.context)
        }
        #endif

        return JSValue(jsValueRef: result, in: self.context)
    }

    deinit {
        // this has been seen to raise an exception on the Android emulator:
        // java.util.concurrent.TimeoutException: skip.script.JSValue.finalize() timed out after 10 seconds
        JavaScriptCore.JSValueUnprotect(context.context, value)
    }
}

extension JSValue {

    /// Creates a JavaScript value of the `undefined` type.
    ///
    /// - Parameters:
    ///   - context: The execution context to use.
    public convenience init(undefinedIn context: JSContext) {
        self.init(jsValueRef: JavaScriptCore.JSValueMakeUndefined(context.context), in: context)
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
        self.init(jsValueRef: JavaScriptCore.JSValueMakeBoolean(context.context, value), in: context)
    }

    /// Creates a JavaScript value of the `Number` type.
    ///
    /// - Parameters:
    ///   - value: The value to assign to the object.
    ///   - context: The execution context to use.
    public convenience init(double value: Double, in context: JSContext) {
        self.init(jsValueRef: JavaScriptCore.JSValueMakeNumber(context.context, value), in: context)
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
        self.init(jsValueRef: JavaScriptCore.JSObjectMake(context.context, nil, nil), in: context)
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
/// So instead we use the private data of the function object to store an index in a global synchronized weak hash map. Ugh.
// SKIP NOWARN
private let _functionCallbacks = java.util.Collections.synchronizedMap(java.util.HashMap<Int64, _JSFunctionInfoHandle>())

// SKIP INSERT: @com.sun.jna.Structure.FieldOrder("id")
public final class JSFunctionInfo : com.sun.jna.Structure {
    // SKIP INSERT: @JvmField
    public var id: Int64 = 0

    /// Lookup the context by the global id
    var context: JSContext? { _functionCallbacks[self.id]?.context }

    /// Lookup the callback by the global id
    var callback: JSFunction? { _functionCallbacks[self.id]?.callback }

    fileprivate init(ptr: OpaquePointer) {
        super.init(ptr)
        read() // read id from the struct
    }

    /// Clear the global function pointer callback for this instance
    func clearCallback() {
        _functionCallbacks[id] = nil
    }

    init(context: JSContext, callback: JSFunction) {
        self.id = kotlin.random.Random.nextLong()
        write() // save id to the struct
        // ideally, we'd at least keep this in a per-context map rather than a global map, but then we'd have the same problem with restoring a java JSContext instance from a pointer, so we'd need to keep another global map around
        _functionCallbacks[self.id] = _JSFunctionInfoHandle(context: context, callback: callback)
    }
}
#endif


#if SKIP

private let JSFunctionCallback = JSFunctionCallbackImpl()
private final class JSFunctionCallbackImpl : JSCallbackFunction {
    init() {
    }

    public func JSFunctionCallback(_ jsc: JSContextRef?, _ object: JSObjectRef?, _ this: JSObjectRef?, _ argumentCount: Int, _ arguments: UnsafePointer<JSValueRef?>?, _ exception: UnsafeMutablePointer<JSValueRef?>?) -> JSValueRef? {
        guard let object = object,
              let data = JavaScriptCore.JSObjectGetPrivate(object) else {
            return nil
        }

        let info = JSFunctionInfo(ptr: data)
        guard let context = info.context,
              let callback = info.callback else {
            return nil
        }

        let argptrs = arguments?.value.getPointerArray(0, argumentCount)
        let args = (0..<argumentCount).map { JSValue(jsValueRef: argptrs![$0], in: context) }
        let this = this.map { JSValue(jsValueRef: $0, in: context) }
        let value: JSValue = callback(context, this, args)
        return value.value
    }
}

private let JSFunctionFinalize = JSFunctionFinalizeImpl()
private final class JSFunctionFinalizeImpl : JSCallbackFunction {
    init() {
    }

    public func JSFunctionFinalize(_ object: JSObjectRef?) -> Void {
        guard let object = object,
              let data = JavaScriptCore.JSObjectGetPrivate(object) else {
            return
        }
        let info = JSFunctionInfo(ptr: data)
        // clear the info from the global map so we can finalize the function instance (and any references it contains)
        info.clearCallback()
    }
}

private let JSFunctionInstanceOf = JSFunctionInstanceOfImpl()
private final class JSFunctionInstanceOfImpl : JSCallbackFunction {
    init() {
    }

    public func JSFunctionInstanceOf(_ jsc: JSContextRef?, _ constructor: JSObjectRef?, _ possibleInstance: JSValueRef?, _ exception: UnsafeMutablePointer<JSValueRef?>?) -> Bool {
        print("### TODO: JSFunctionInstanceOf")
        return false
    }
}

private let JSFunctionConstructor = JSFunctionConstructorImpl()
private final class JSFunctionConstructorImpl : JSCallbackFunction {
    init() {
    }

    public func JSFunctionConstructor(_ jsc: JSContextRef?, _ object: JSObjectRef?, _ argumentCount: Int, _ arguments: UnsafePointer<JSValueRef?>?, _ exception: UnsafeMutablePointer<JSValueRef?>?) -> JSObjectRef? {
        print("### TODO: JSFunctionConstructor")
        return nil
    }
}


#else

// MARK: Support for JSValue(newFunctionIn:…)

private func JSFunctionFinalize(_ object: JSObjectRef?) -> Void {
    let info = JSObjectGetPrivate(object).assumingMemoryBound(to: JSFunctionInfo.self)
    info.deinitialize(count: 1)
    info.deallocate()
}

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

private func JSFunctionInstanceOf(_ jsc: JSContextRef?, _ constructor: JSObjectRef?, _ possibleInstance: JSValueRef?, _ exception: UnsafeMutablePointer<JSValueRef?>?) -> Bool {
    let info = JSObjectGetPrivate(constructor).assumingMemoryBound(to: JSFunctionInfo.self)
    let context = info.pointee.context
    let pt1 = JSObjectGetPrototype(context.context, constructor)
    let pt2 = JSObjectGetPrototype(context.context, possibleInstance)
    return JSValueIsStrictEqual(context.context, pt1, pt2)
}

/// Used internally to piggyback a native error as the peer of its wrapping JSValue error object.
class JSErrorPeer {
    let error: Error

    init(error: Error) {
        self.error = error
    }
}

extension JSValue {

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


    /// Tests whether an object can be called as a function.
    public var isFunction: Bool {
        isObject && JSObjectIsFunction(context.context, value)
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


/// An error thrown from JavaScript
public struct JSError: Error, CustomStringConvertible, @unchecked Sendable {
    public var message: String
    public var cause: Error?
    public var jsErrorString: String?
    public var script: String?

    public init(message: String, script: String? = nil) {
        self.message = message
        self.script = script
    }

    public init(jsError: JSValue, script: String? = nil) {
        if let cause = jsError.cause {
            self.init(cause: cause, script: script)
        } else {
            self.init(message: jsError.toString(), script: script)
        }
    }

    public init(cause: Error, script: String? = nil) {
        if let jserror = cause as? JSError {
            self = jserror
            if let script {
                self.script = script
            }
        } else {
            self.init(message: String(describing: cause), script: script)
            self.cause = cause
        }
    }

    public var localizedDescription: String {
        return description
    }

    public var description: String {
        return message // + scriptDescription
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

/// Global pointer to the JSC library, equivalent to the Swift `JavaScriptCore` framework (`libjsc.so` on Android?)
let JavaScriptCore: JavaScriptCoreLibrary = {
    let isAndroid = System.getProperty("java.vm.vendor") == "The Android Project"
    if isAndroid {
        //System.loadLibrary("icu")
    }

    // on Android we use the embedded libjsc.so; on macOS host, use the system JavaScriptCore
    let jscName = isAndroid ? "jsc" : "JavaScriptCore"
    return com.sun.jna.Native.load(jscName, javaClass(JavaScriptCoreLibrary.self))
}()

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
protocol JavaScriptCoreLibrary : com.sun.jna.Library {
    func JSStringRetain(_ string: JSStringRef) -> JSStringRef
    func JSStringRelease(_ string: JSStringRef)
    func JSStringIsEqual(_ string1: JSStringRef, _ string2: JSStringRef) -> Bool
    func JSStringGetLength(_ string: JSStringRef) -> Int
    func JSStringGetMaximumUTF8CStringSize(_ string: JSStringRef) -> Int
    func JSStringGetCharactersPtr(_ string: JSStringRef) -> OpaquePointer
    func JSStringGetUTF8CString(_ string: JSStringRef, _ buffer: OpaquePointer, _ bufferSize: Int) -> Int
    func JSStringCreateWithUTF8CString(_ string: String) -> JSStringRef
    func JSStringIsEqualToUTF8CString(_ stringRef: JSStringRef, _ string: String) -> Bool

    func JSGlobalContextCreate(_ globalObjectClass: JSValueRef?) -> JSContextRef
    func JSGlobalContextRelease(_ ctx: JSContextRef)
    func JSEvaluateScript(_ ctx: JSContextRef, script: JSStringRef, thisObject: JSValueRef?, sourceURL: String?, startingLineNumber: Int, exception: JSValuePointer) -> JSValueRef

    func JSValueProtect(_ ctx: JSContextRef, _ value: JSValueRef)
    func JSValueUnprotect(_ ctx: JSContextRef, _ value: JSValueRef)
    func JSValueGetType(_ ctx: JSContextRef, _ value: JSValueRef) -> Int

    func JSValueIsUndefined(_ ctx: JSContextRef, _ value: JSValueRef) -> Bool
    func JSValueIsNull(_ ctx: JSContextRef, _ value: JSValueRef) -> Bool
    func JSValueIsBoolean(_ ctx: JSContextRef, _ value: JSValueRef) -> Bool
    func JSValueIsNumber(_ ctx: JSContextRef, _ value: JSValueRef) -> Bool
    func JSValueIsString(_ ctx: JSContextRef, _ value: JSValueRef) -> Bool
    func JSValueIsSymbol(_ ctx: JSContextRef, _ value: JSValueRef) -> Bool
    func JSValueIsObject(_ ctx: JSContextRef, _ value: JSValueRef) -> Bool
    func JSValueIsArray(_ ctx: JSContextRef, _ value: JSValueRef) -> Bool
    func JSValueIsDate(_ ctx: JSContextRef, _ value: JSValueRef) -> Bool

    func JSValueIsEqual(_ ctx: JSContextRef, _ a: JSValueRef, _ b: JSValueRef, _ exception: JSValuePointer) -> Boolean
    func JSValueIsStrictEqual(_ ctx: JSContextRef, _ a: JSValueRef, _ b: JSValueRef) -> Boolean

    func JSValueIsInstanceOfConstructor(_ ctx: JSContextRef, _ value: JSValueRef, _ constructor: JSObjectRef, _ exception: JSValuePointer) -> Boolean

    func JSValueToBoolean(_ ctx: JSContextRef, _ value: JSValueRef) -> Boolean
    func JSValueToNumber(_ ctx: JSContextRef, _ value: JSValueRef, _ exception: JSValuePointer?) -> Double
    func JSValueToStringCopy(_ ctx: JSContextRef, _ value: JSValueRef, _ exception: JSValuePointer?) -> JSStringRef
    func JSValueToObject(_ ctx: JSContextRef, _ value: JSValueRef, _ exception: JSValuePointer?) -> JSObjectRef

    func JSValueMakeUndefined(_ ctx: JSContextRef) -> JSValueRef
    func JSValueMakeNull(_ ctx: JSContextRef) -> JSValueRef
    func JSValueMakeBoolean(_ ctx: JSContextRef, _ value: Boolean) -> JSValueRef
    func JSValueMakeNumber(_ ctx: JSContextRef, _ value: Double) -> JSValueRef
    func JSValueMakeString(_ ctx: JSContextRef, _ value: JSStringRef) -> JSValueRef
    func JSValueMakeSymbol(_ ctx: JSContextRef, _ value: JSStringRef) -> JSValueRef
    func JSValueMakeFromJSONString(_ ctx: JSContextRef, _ json: JSStringRef) -> JSValueRef
    func JSValueCreateJSONString(_ ctx: JSContextRef, _ value: JSValueRef, _ indent: UInt32, _ exception: JSValuePointer?) -> JSStringRef

    func JSObjectGetProperty(_ ctx: JSContextRef, _ obj: JSValueRef, _ propertyName: JSStringRef, _ exception: JSValuePointer?) -> JSValueRef
    func JSObjectSetProperty(_ ctx: JSContextRef, _ obj: JSValueRef, propertyName: JSValueRef, _ value: JSValueRef, _ attributes: JSPropertyAttributes, _ exception: JSValuePointer?)

    func JSObjectGetPropertyAtIndex(_ ctx: JSContextRef, _ obj: JSValueRef, _ propertyIndex: Int, _ exception: JSValuePointer?) -> JSValueRef
    func JSObjectSetPropertyAtIndex(_ ctx: JSContextRef, _ obj: JSValueRef, propertyIndex: Int, _ value: JSValueRef, _ exception: JSValuePointer?)

    func JSObjectMakeFunctionWithCallback(_ ctx: JSContextRef, _ name: JSStringRef, _ callAsFunction: JSObjectCallAsFunctionCallback) -> JSObjectRef
    func JSObjectMake(_ ctx: JSContextRef, _ jsClass: JSClassRef?, _ data: OpaqueJSValue?) -> JSObjectRef

    func JSObjectCallAsFunction(_ ctx: JSContextRef, _ object: OpaquePointer?, _ thisObject: OpaquePointer?, _ argumentCount: Int32, _ arguments: UnsafePointer<JSValueRef?>?, _ exception: UnsafeMutableRawPointer?) -> JSValueRef

    func JSClassCreate(_ cls: JSClassDefinition) -> JSClassRef
    func JSClassRetain(_ cls: JSClassRef) -> JSClassRef
    func JSClassRelease(_ cls: JSClassRef) -> Void

    func JSObjectSetPrivate(_ jsObject: JSObjectRef, _ privateData: VoidPointer?)
    func JSObjectGetPrivate(_ jsObject: JSObjectRef) -> VoidPointer?

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
