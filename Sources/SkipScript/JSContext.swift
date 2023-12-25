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
        return JSValue(jsValueRef: result!, in: self)
    }

    public func setObject(_ object: Any, forKeyedSubscript key: String) {
        let propName = JavaScriptCore.JSStringCreateWithUTF8CString("key")
        defer { JavaScriptCore.JSStringRelease(propName) }
        let exception = ExceptionPtr(nil)
        let valueRef = JSValue(object: object, in: self).value
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
}

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

    deinit {
        // this has been seen to raise an exception on the Android emulator:
        // java.util.concurrent.TimeoutException: skip.script.JSValue.finalize() timed out after 10 seconds
        JavaScriptCore.JSValueUnprotect(context.context, value)
    }
}


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
typealias JSValuePointer = UnsafeMutableRawPointer

typealias JSValueRef = OpaqueJSValue
typealias JSStringRef = OpaqueJSValue
typealias JSObjectRef = OpaqueJSValue
typealias JSContextRef = OpaqueJSValue


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

    func JSObjectMakeFunctionWithCallback(_ ctx: JSContextRef, _ name: JSStringRef, _ callAsFunction: com.sun.jna.Callback) -> JSObjectRef

    func JSObjectCallAsFunction(_ ctx: JSContextRef, _ object: OpaquePointer?, _ thisObject: OpaquePointer?, _ argumentCount: Int32, _ arguments: UnsafeMutableRawPointer?, _ exception: UnsafeMutableRawPointer?) -> JSValueRef
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
