// Include our module headers
#include "UDPDirectModuleCompat.h"

// Include necessary C++20 headers
#include <memory>
#include <functional>

/**
 * ========================================================================
 * IMPORTANT: iOS CUSTOM MODULES STAGING AREA
 * ========================================================================
 * 
 * This file is part of the ios-custom-modules directory which serves as a 
 * STAGING AREA for Expo prebuild process. 
 * 
 * During the Expo prebuild process, files from this directory will be copied 
 * into the generated iOS project. This allows us to maintain custom native 
 * modules separately from the auto-generated iOS code.
 * 
 * DO NOT modify files directly in the generated iOS project as those changes
 * will be overwritten on subsequent prebuilds. Instead, make changes here
 * and then run the prebuild process again.
 * 
 * ========================================================================
 * 
 * SharedBufferHostObject.mm - Implementation of the SharedBuffer JSI host object
 * This file implements a JavaScript Interface (JSI) host object that provides
 * direct access to native memory buffers for high-performance data transfer.
 */

// Redundant: UDPModuleCompat.h is included by SharedBufferHostObject.h
// #include "../UDPModule/UDPModuleCompat.h"

#import <React/RCTLog.h>
#import "UDPDirectModuleCompat.h"
#import "SharedBufferHostObject.h"
#import "UDPSocketManager.h"
#import "ExternalMutableBuffer.h"

// For jsi::Function::createFromHostFunction and other JSI utilities
#include <jsi/jsi.h>
#include <vector>
#include <string>
#include <memory>

// Add necessary C++ compatibility workarounds
#include <React/RCTBridge+Private.h>
#include <ReactCommon/CallInvoker.h>
#include <ReactCommon/RuntimeExecutor.h>

using namespace facebook;
using namespace facebook::jsi;

#pragma mark - Helper Functions

/**
 * Utility function to convert NSData to a JSI ArrayBuffer
 * This allows efficient passing of binary data between native and JS
 * 
 * @param rt The JSI Runtime instance
 * @param data The NSData to convert
 * @return JSI Value containing the ArrayBuffer
 */
/*
static Value convertNSDataToArrayBuffer(Runtime& rt, NSData* _Nullable data) {
    if (!data) {
        return Value::null();
    }
    
    // Create an ArrayBuffer of the same size as the NSData
    auto arrayBuffer = ArrayBuffer(rt, data.length);
    
    // Copy the data into the ArrayBuffer
    memcpy(arrayBuffer.data(rt), data.bytes, data.length);
    
    // Return the ArrayBuffer as a JSI Value
    return Value(rt, arrayBuffer);
}
*/

/**
 * Helper to convert a JSI buffer object to NSData
 *
 * @param rt The JSI runtime
 * @param jsiBufferObject A JSI object that might be an ArrayBuffer or Buffer
 * @return NSData or nil if conversion fails
 */
static NSData* _Nullable __unused convertJSIBufferToNSData(Runtime& rt, const Object& jsiBufferObject) {
    // Check if it's an ArrayBuffer directly
    if (jsiBufferObject.isArrayBuffer(rt)) {
        ArrayBuffer arrayBuffer = jsiBufferObject.getArrayBuffer(rt);
        return [NSData dataWithBytesNoCopy:arrayBuffer.data(rt) 
                                    length:arrayBuffer.size(rt) 
                              freeWhenDone:NO]; // No copy if JS manages lifetime
    }

    // Check for TypedArray (e.g., Uint8Array) by looking for a 'buffer' property
    if (jsiBufferObject.hasProperty(rt, "buffer")) {
        Value underlyingBufferValue = jsiBufferObject.getProperty(rt, "buffer");
        if (underlyingBufferValue.isObject() && underlyingBufferValue.asObject(rt).isArrayBuffer(rt)) {
            ArrayBuffer arrayBuffer = underlyingBufferValue.asObject(rt).getArrayBuffer(rt);
            
            // Get byteOffset and byteLength for the view
            size_t byteOffset = 0;
            if (jsiBufferObject.hasProperty(rt, "byteOffset")) {
                Value offsetVal = jsiBufferObject.getProperty(rt, "byteOffset");
                if (offsetVal.isNumber()) {
                    byteOffset = static_cast<size_t>(offsetVal.asNumber());
            }
            }
            
            size_t byteLength = arrayBuffer.size(rt) - byteOffset; // Default to rest of buffer
            if (jsiBufferObject.hasProperty(rt, "byteLength")) {
                Value lengthVal = jsiBufferObject.getProperty(rt, "byteLength");
                if (lengthVal.isNumber()) {
                    byteLength = static_cast<size_t>(lengthVal.asNumber());
                }
            }

            if (byteOffset + byteLength > arrayBuffer.size(rt)) {
                 RCTLogError(@"SharedBufferHostObject: TypedArray view extends beyond underlying ArrayBuffer.");
                 return nil; // Invalid bounds
            }
            
            // Create NSData pointing to the TypedArray's view (no copy)
            return [NSData dataWithBytesNoCopy:static_cast<uint8_t*>(arrayBuffer.data(rt)) + byteOffset 
                                        length:byteLength 
                                  freeWhenDone:NO];
        }
    }
    
    RCTLogError(@"SharedBufferHostObject: convertJSIBufferToNSData expects an ArrayBuffer or a TypedArray view.");
    return nil;
}

#pragma mark - SharedBufferHostObject Implementation

// Constructor - store given CallInvoker if provided.
SharedBufferHostObject::SharedBufferHostObject(
    facebook::jsi::Runtime& runtime,
    UDPSocketManager *manager, 
    int bufferId,
    std::shared_ptr<facebook::react::CallInvoker> jsCallInvoker
)
    : runtime_(runtime), socketManager_(manager), bufferId_(bufferId) {
    if (jsCallInvoker) {
        jsCallInvoker_ = jsCallInvoker;
    }
}

// Destructor
SharedBufferHostObject::~SharedBufferHostObject() {
    // Destructor can be used for logging or cleanup if necessary,
    // but primary buffer release notification is handled by the ArrayBuffer's finalizer mechanism.
    // UDP_LOG_VERBOSE(@"SharedBufferHostObject for buffer ID %d is being destroyed.", bufferId_);
}

// Helper to get the native buffer
NSMutableData* SharedBufferHostObject::getNativeBuffer() {
  if (!socketManager_) {
    RCTLogError(@"SharedBufferHostObject: socketManager_ is null in getNativeBuffer for bufferId %d", bufferId_);
    return nil;
  }
  return [socketManager_ getModifiableBufferWithId:@(bufferId_)];
}

// JSI getProperty anmes
std::vector<PropNameID> SharedBufferHostObject::getPropertyNames(Runtime& rt) {
    std::vector<PropNameID> names;
    names.push_back(PropNameID::forUtf8(rt, "bufferId"));
    names.push_back(PropNameID::forUtf8(rt, "getDirectArrayBuffer"));
    // Add other properties or methods if needed
    return names;
}

// JSI get method
Value SharedBufferHostObject::get(Runtime& rt, const PropNameID& name) {
    std::string propName = name.utf8(rt);

    if (propName == "bufferId") {
        return Value((double)bufferId_); // Expose bufferId as a number
    }

    if (propName == "getDirectArrayBuffer") {
        // Return a JSI Function that, when called, will produce the ArrayBuffer
        return Function::createFromHostFunction(
            rt,
            PropNameID::forUtf8(rt, "getDirectArrayBufferInternal"),
            0, // Argument count for the JS function getDirectArrayBuffer()
            // Lambda for the host function:
            [this](Runtime& runtime, const Value& thisVal, const Value* args, size_t count) -> Value {
                // Critical: Ensure socketManager_ is valid before use
                if (!socketManager_) {
                    throw JSError(runtime, "SharedBufferHostObject: Native socket manager instance is null.");
                }

                // For simplicity here, we assume getModifiableBufferWithId is safe or dispatched internally by module.
                // However, for mutable operations or state access, dispatching is safer:
                // Example of dispatching (conceptual, actual implementation might vary based on jsCallInvoker_):
                // std::weak_ptr<CallInvoker> weakJsCallInvoker = jsCallInvoker_;
                // auto strongModule = module_; // Capture module by value if it could be nilled, or ensure it cannot.
                
                // Obtain native buffer
                NSMutableData* buffer = [socketManager_ getModifiableBufferWithId:@(bufferId_)];
                if (!buffer) {
                    throw JSError(runtime, "Buffer not found or no longer available");
                }

                void* data = buffer.mutableBytes;
                size_t size = buffer.length;

                // Create the finalizer function first to avoid lambda capture issues
                auto finalizer = [manager = socketManager_, idCopy = bufferId_]() {
                    if (manager) {
                        [manager jsDidReleaseBufferId:@(idCopy)];
                    }
                };
                
                // Use direct allocation to avoid std::construct_at issues
                std::shared_ptr<ExternalMutableBuffer> externalBuffer = 
                    std::shared_ptr<ExternalMutableBuffer>(new ExternalMutableBuffer(data, size, std::move(finalizer)));

                // Construct ArrayBuffer backed by external buffer
                auto arrayBuffer = ArrayBuffer(runtime, externalBuffer);
                return arrayBuffer;
            }
        );
    }

    // Default case
    return Value::undefined();
}

// JSI set method
void SharedBufferHostObject::set(Runtime& rt, const PropNameID& name, const Value& value) {
    // Most properties are read-only, but we could implement setters here if needed
    std::string propName = name.utf8(rt);
    
    // Currently no writable properties
}

#pragma clang diagnostic pop  // Close the pragma directive opened at the top 