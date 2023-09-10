// Copyright 2023 Skip
//
// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org
#if SKIP
public typealias JSContext = SkipJSContext
public typealias JSValue = SkipJSValue

/// Public constructor optional init
//public func JSContext() -> JSContext? {
//    SkipJSContext()
//}

typealias ExceptionPtr = JSValuePointer
#else
typealias ExceptionPtr = UnsafeMutablePointer<JSValueRef?>
#endif

// override the Kotlin type to be public while keeping the Swift version internal:
// SKIP DECLARE: open class SkipJSContext
internal class SkipJSContext {
    public let context: JSContextRef
    public private(set) var exception: SkipJSValue? = nil

    public init(context: JSContextRef) {
        self.context = context
    }

    public init() {
        self.context = JavaScriptCore.JSGlobalContextCreate(nil)
    }

    @discardableResult fileprivate func clearException(_ exception: ExceptionPtr? = nil) -> Bool {
        if let exception = exception {
            // errors are handled by returning nil and setting the current exception poinrts
            #if SKIP
            if let error: com.sun.jna.Pointer = exception.value {
                self.exception = SkipJSValue(context: self, value: error)
                return false
            }
            #else
            if let error: JavaScriptCore.JSValueRef = exception.pointee {
                self.exception = SkipJSValue(context: self, value: error)
                return false
            }
            #endif
        }

        // clear the current exception
        self.exception = nil
        return true
    }

    public func evaluateScript(_ script: String) -> SkipJSValue? {
        let scriptValue = JavaScriptCore.JSStringCreateWithUTF8CString(script)
        defer { JavaScriptCore.JSStringRelease(scriptValue) }

        let exception = ExceptionPtr(nil)
        let result = JavaScriptCore.JSEvaluateScript(context, scriptValue, nil, nil, 1, exception)
        if !clearException(exception) {
            return nil
        }
        return SkipJSValue(context: self, value: result!)
    }
}

// override the Kotlin type to be public while keeping the Swift version internal:
// SKIP DECLARE: public class SkipJSValue
internal class SkipJSValue {
    public let context: SkipJSContext
    public let value: JSValueRef

    public init(context: SkipJSContext, value: JSValueRef) {
        JavaScriptCore.JSValueProtect(context.context, value)
        self.context = context
        self.value = value
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
            let element = SkipJSValue(context: context, value: elementValue)
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
        JavaScriptCore.JSValueUnprotect(context.context, value)
    }
}


#if SKIP
fileprivate extension Int {
    // stub extension to allow us to handle when JSType is an enum and a bare int
    var rawValue: Int { self }
}
#endif

#if !SKIP
// Non-Skip uses the JavaScriptCore symbols directly
import JavaScriptCore
typealias JSValue = JavaScriptCore.JSValue
#else

// workaround for Skip converting "JavaScriptCode.self.javaClass" to "(JavaScriptCoreLibrary::class.companionObjectInstance as JavaScriptCoreLibrary.Companion).java)"
// SKIP INSERT: fun <T : Any> javaClass(kotlinClass: kotlin.reflect.KClass<T>): Class<T> { return kotlinClass.java }


/// Global pointer to the JSC library, equivalent to the Swift `JavaScriptCore` framework (`libjsc.so` on Android?)
let JavaScriptCore: JavaScriptCoreLibrary = {
    System.loadLibrary("icu")
    // on Android we use the embedded libjsc.so; on macOS host, use the system JavaScriptCore
    let jscName = System.getProperty("java.vm.vendor") == "The Android Project" ? "jsc" : "JavaScriptCore"
    return com.sun.jna.Native.load(jscName, javaClass(JavaScriptCoreLibrary.self))
}()

typealias Pointer = com.sun.jna.Pointer

/// A JavaScript value. The base type for all JavaScript values, and polymorphic functions on them.
typealias OpaqueJSValue = Pointer
typealias JSValuePointer = com.sun.jna.ptr.PointerByReference

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
    func JSStringGetCharactersPtr(_ string: JSStringRef) -> Pointer
    func JSStringGetUTF8CString(_ string: JSStringRef, _ buffer: Pointer, _ bufferSize: Int) -> Int
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
    func JSObjectGetPropertyAtIndex(_ ctx: JSContextRef, _ obj: JSValueRef, _ propertyIndex: Int, _ exception: JSValuePointer?) -> JSValueRef
    func JSObjectSetPropertyAtIndex(_ ctx: JSContextRef, _ obj: JSValueRef, propertyIndex: Int, _ value: JSValueRef, _ exception: JSValuePointer?)
}

#endif

