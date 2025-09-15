#import "UDPDirectJSI.h"
#import "UDPSocketManager.h"
#import <React/RCTLog.h>
#import <jsi/jsi.h>
#include <memory>
#include <mutex>
#include <unordered_map>

namespace facebook {
namespace react {

using namespace facebook::jsi;

// Global weak references
static void* g_socketManager = nullptr;
static std::weak_ptr<CallInvoker> g_jsInvoker;

// MutableBuffer implementation for NSData
class NSDataBuffer : public MutableBuffer {
public:
    NSDataBuffer(NSData* data) : data_(data) {}
    
    ~NSDataBuffer() override {}
    
    size_t size() const override {
        return data_.length;
    }
    
    uint8_t* data() override {
        return (uint8_t*)data_.mutableBytes;
    }
    
private:
    NSMutableData* data_;
};

void UDPDirectJSI::install(Runtime& runtime, void* socketManager, std::shared_ptr<CallInvoker> jsInvoker) {
    NSLog(@"[UDPDirectJSI] Installing JSI bindings with CallInvoker");
    
    // Store references
    g_socketManager = socketManager;
    g_jsInvoker = jsInvoker;
    
    // Install udpSendDirect function
    auto udpSendDirectFunc = Function::createFromHostFunction(
        runtime,
        PropNameID::forAscii(runtime, "udpSendDirect"),
        6, // socketId, buffer, offset, length, port, address
        UDPDirectJSI::udpSendDirect
    );
    runtime.global().setProperty(runtime, "udpSendDirect", std::move(udpSendDirectFunc));
    
    // Install UDP namespace with additional functions
    auto udpNamespace = Object(runtime);
    
    // Create socket function
    auto createSocketFunc = Function::createFromHostFunction(
        runtime,
        PropNameID::forAscii(runtime, "createSocket"),
        1, // options
        UDPDirectJSI::createUdpSocket
    );
    udpNamespace.setProperty(runtime, "createSocket", std::move(createSocketFunc));
    
    // Bind socket function
    auto bindSocketFunc = Function::createFromHostFunction(
        runtime,
        PropNameID::forAscii(runtime, "bind"),
        3, // socketId, port, address
        UDPDirectJSI::bindSocket
    );
    udpNamespace.setProperty(runtime, "bind", std::move(bindSocketFunc));
    
    // Close socket function
    auto closeSocketFunc = Function::createFromHostFunction(
        runtime,
        PropNameID::forAscii(runtime, "close"),
        1, // socketId
        UDPDirectJSI::closeSocket
    );
    udpNamespace.setProperty(runtime, "close", std::move(closeSocketFunc));
    
    // Set event handler function
    auto setEventHandlerFunc = Function::createFromHostFunction(
        runtime,
        PropNameID::forAscii(runtime, "setEventHandler"),
        2, // socketId, handler
        UDPDirectJSI::setEventHandler
    );
    udpNamespace.setProperty(runtime, "setEventHandler", std::move(setEventHandlerFunc));
    
    // Install UDP namespace globally
    runtime.global().setProperty(runtime, "_udpJSI", std::move(udpNamespace));
    
    NSLog(@"[UDPDirectJSI] JSI bindings installed successfully");
}

void* UDPDirectJSI::getSocketManager(Runtime& runtime) {
    if (!g_socketManager) {
        throw JSError(runtime, "UDP socket manager not initialized");
    }
    return g_socketManager;
}

Value UDPDirectJSI::udpSendDirect(
    Runtime& runtime,
    const Value& thisValue,
    const Value* arguments,
    size_t count
) {
    if (count != 6) {
        throw JSError(runtime, "udpSendDirect expects 6 arguments: socketId, buffer, offset, length, port, address");
    }
    
    @try {
        // Extract arguments
        if (!arguments[0].isString()) {
            throw JSError(runtime, "socketId must be a string");
        }
        std::string socketIdStr = arguments[0].getString(runtime).utf8(runtime);
        NSNumber *socketId = @(std::stoi(socketIdStr));
        
        // Handle ArrayBuffer
        if (!arguments[1].isObject()) {
            throw JSError(runtime, "buffer must be an ArrayBuffer");
        }
        
        auto bufferObj = arguments[1].asObject(runtime);
        if (!bufferObj.isArrayBuffer(runtime)) {
            throw JSError(runtime, "buffer must be an ArrayBuffer");
        }
        
        auto arrayBuffer = bufferObj.getArrayBuffer(runtime);
        
        // Extract offset and length
        if (!arguments[2].isNumber()) {
            throw JSError(runtime, "offset must be a number");
        }
        size_t offset = (size_t)arguments[2].asNumber();
        
        if (!arguments[3].isNumber()) {
            throw JSError(runtime, "length must be a number");
        }
        size_t length = (size_t)arguments[3].asNumber();
        
        // Validate offset and length
        if (offset + length > arrayBuffer.size(runtime)) {
            throw JSError(runtime, "offset + length exceeds buffer size");
        }
        
        // Create NSData with the specified range
        uint8_t* dataPtr = arrayBuffer.data(runtime) + offset;
        NSData *data = [NSData dataWithBytesNoCopy:dataPtr
                                             length:length
                                       freeWhenDone:NO];
        
        // Extract port and address
        if (!arguments[4].isNumber()) {
            throw JSError(runtime, "port must be a number");
        }
        uint16_t port = (uint16_t)arguments[4].asNumber();
        
        if (!arguments[5].isString()) {
            throw JSError(runtime, "address must be a string");
        }
        NSString *address = [NSString stringWithUTF8String:arguments[5].getString(runtime).utf8(runtime).c_str()];
        
        // Get socket manager and send
        UDPSocketManager *manager = (__bridge UDPSocketManager *)getSocketManager(runtime);
        [manager sendData:data onSocket:socketId toHost:address port:port tag:0];
        
        NSLog(@"[UDPDirectJSI] Zero-copy send %zu bytes (offset=%zu) from socket %@ to %@:%d", 
              data.length, offset, socketId, address, port);
        
        return Value::undefined();
        
    } @catch (NSException *exception) {
        std::string error = "Native exception: " + std::string([exception.reason UTF8String]);
        throw JSError(runtime, error);
    }
}

Value UDPDirectJSI::createUdpSocket(
    Runtime& runtime,
    const Value& thisValue,
    const Value* arguments,
    size_t count
) {
    if (count != 1 || !arguments[0].isObject()) {
        throw JSError(runtime, "createSocket expects 1 object argument");
    }
    
    @try {
        auto options = arguments[0].asObject(runtime);
        NSMutableDictionary *nsOptions = [NSMutableDictionary dictionary];
        
        // Extract options
        if (options.hasProperty(runtime, "type")) {
            auto type = options.getProperty(runtime, "type").getString(runtime).utf8(runtime);
            nsOptions[@"type"] = [NSString stringWithUTF8String:type.c_str()];
        } else {
            nsOptions[@"type"] = @"udp4"; // Default
        }
        
        if (options.hasProperty(runtime, "reuseAddr")) {
            nsOptions[@"reuseAddr"] = @(options.getProperty(runtime, "reuseAddr").getBool());
        }
        
        if (options.hasProperty(runtime, "reusePort")) {
            nsOptions[@"reusePort"] = @(options.getProperty(runtime, "reusePort").getBool());
        }
        
        if (options.hasProperty(runtime, "broadcast")) {
            nsOptions[@"broadcast"] = @(options.getProperty(runtime, "broadcast").getBool());
        }
        
        // Create socket
        UDPSocketManager *manager = (__bridge UDPSocketManager *)getSocketManager(runtime);
        NSError *error = nil;
        NSNumber *socketId = [manager createSocketWithOptions:nsOptions error:&error];
        
        if (!socketId) {
            std::string errorMsg = "Failed to create socket";
            if (error) {
                errorMsg += ": " + std::string([[error localizedDescription] UTF8String]);
            }
            throw JSError(runtime, errorMsg);
        }
        
        NSLog(@"[UDPDirectJSI] Created socket with ID: %@", socketId);
        
        // Return socket ID as string
        return String::createFromUtf8(runtime, [[socketId stringValue] UTF8String]);
        
    } @catch (NSException *exception) {
        std::string error = "Native exception: " + std::string([exception.reason UTF8String]);
        throw JSError(runtime, error);
    }
}

Value UDPDirectJSI::bindSocket(
    Runtime& runtime,
    const Value& thisValue,
    const Value* arguments,
    size_t count
) {
    if (count != 3) {
        throw JSError(runtime, "bind expects 3 arguments: socketId, port, address");
    }
    
    @try {
        // Extract arguments
        std::string socketIdStr = arguments[0].getString(runtime).utf8(runtime);
        NSNumber *socketId = @(std::stoi(socketIdStr));
        uint16_t port = (uint16_t)arguments[1].asNumber();
        NSString *address = [NSString stringWithUTF8String:arguments[2].getString(runtime).utf8(runtime).c_str()];
        
        // Bind socket
        UDPSocketManager *manager = (__bridge UDPSocketManager *)getSocketManager(runtime);
        NSError *error = nil;
        BOOL success = [manager bindSocket:socketId toPort:port address:address error:&error];
        
        if (!success) {
            std::string errorMsg = "Failed to bind socket";
            if (error) {
                errorMsg += ": " + std::string([[error localizedDescription] UTF8String]);
            }
            throw JSError(runtime, errorMsg);
        }
        
        NSLog(@"[UDPDirectJSI] Bound socket %@ to %@:%d", socketId, address, port);
        return Value::undefined();
        
    } @catch (NSException *exception) {
        std::string error = "Native exception: " + std::string([exception.reason UTF8String]);
        throw JSError(runtime, error);
    }
}

Value UDPDirectJSI::closeSocket(
    Runtime& runtime,
    const Value& thisValue,
    const Value* arguments,
    size_t count
) {
    if (count != 1 || !arguments[0].isString()) {
        throw JSError(runtime, "close expects 1 string argument: socketId");
    }
    
    @try {
        std::string socketIdStr = arguments[0].getString(runtime).utf8(runtime);
        NSNumber *socketId = @(std::stoi(socketIdStr));
        
        UDPSocketManager *manager = (__bridge UDPSocketManager *)getSocketManager(runtime);
        [manager closeSocket:socketId];
        
        NSLog(@"[UDPDirectJSI] Closed socket %@", socketId);
        return Value::undefined();
        
    } @catch (NSException *exception) {
        std::string error = "Native exception: " + std::string([exception.reason UTF8String]);
        throw JSError(runtime, error);
    }
}

Value UDPDirectJSI::setEventHandler(
    Runtime& runtime,
    const Value& thisValue,
    const Value* arguments,
    size_t count
) {
    if (count != 2 || !arguments[0].isString() || !arguments[1].isObject()) {
        throw JSError(runtime, "setEventHandler expects socketId and handler object");
    }
    
    @try {
        std::string socketIdStr = arguments[0].getString(runtime).utf8(runtime);
        NSNumber *socketId = @(std::stoi(socketIdStr));
        
        auto handlerObj = arguments[1].asObject(runtime);
        
        // Store handlers as shared pointers to keep them alive
        std::shared_ptr<Function> onMessage;
        std::shared_ptr<Function> onError;
        std::shared_ptr<Function> onClose;
        
        if (handlerObj.hasProperty(runtime, "onMessage")) {
            auto msgHandler = handlerObj.getProperty(runtime, "onMessage");
            if (msgHandler.isObject() && msgHandler.asObject(runtime).isFunction(runtime)) {
                onMessage = std::make_shared<Function>(msgHandler.asObject(runtime).asFunction(runtime));
            }
        }
        
        if (handlerObj.hasProperty(runtime, "onError")) {
            auto errHandler = handlerObj.getProperty(runtime, "onError");
            if (errHandler.isObject() && errHandler.asObject(runtime).isFunction(runtime)) {
                onError = std::make_shared<Function>(errHandler.asObject(runtime).asFunction(runtime));
            }
        }
        
        if (handlerObj.hasProperty(runtime, "onClose")) {
            auto closeHandler = handlerObj.getProperty(runtime, "onClose");
            if (closeHandler.isObject() && closeHandler.asObject(runtime).isFunction(runtime)) {
                onClose = std::make_shared<Function>(closeHandler.asObject(runtime).asFunction(runtime));
            }
        }
        
        // Set up native callbacks that invoke JSI functions
        UDPSocketManager *manager = (__bridge UDPSocketManager *)getSocketManager(runtime);
        
        if (onMessage) {
            // Capture the handler
            auto messageHandler = onMessage;
            
            manager.onDataReceived = ^(NSNumber* sockId, NSData* data, NSString* host, uint16_t port, NSNumber* bufferId) {
                // Capture the data we need
                std::string socketIdStr = [[sockId stringValue] UTF8String];
                std::string hostStr = [host UTF8String];
                uint16_t portNum = port;
                
                // Create a mutable copy for the buffer
                NSMutableData *mutableData = [data mutableCopy];
                
                // Get the JS invoker
                auto jsInvoker = g_jsInvoker.lock();
                if (!jsInvoker) {
                    NSLog(@"[UDPDirectJSI] JS invoker no longer available");
                    return;
                }
                
                // Use the JS invoker to run on the JS thread
                jsInvoker->invokeAsync([&runtime, messageHandler, socketIdStr, hostStr, portNum, mutableData]() {
                    try {
                        // Create a MutableBuffer that wraps NSData
                        auto buffer = std::make_shared<NSDataBuffer>(mutableData);
                        
                        // Create ArrayBuffer from the MutableBuffer
                        auto arrayBuffer = ArrayBuffer(runtime, buffer);
                        
                        // Create event object
                        auto event = Object(runtime);
                        event.setProperty(runtime, "socketId", String::createFromUtf8(runtime, socketIdStr));
                        event.setProperty(runtime, "data", std::move(arrayBuffer));
                        event.setProperty(runtime, "address", String::createFromUtf8(runtime, hostStr));
                        event.setProperty(runtime, "port", Value((double)portNum));
                        
                        // Call handler
                        messageHandler->call(runtime, event);
                        
                        NSLog(@"[UDPDirectJSI] Zero-copy message delivered: %zu bytes from %s:%d", 
                              mutableData.length, hostStr.c_str(), portNum);
                              
                        // The buffer will be automatically released when the ArrayBuffer is GC'd
                    } catch (const std::exception& e) {
                        NSLog(@"[UDPDirectJSI] Error in message handler: %s", e.what());
                    }
                });
            };
        }
        
        if (onError) {
            manager.onSendFailure = ^(NSNumber* sockId, long tag, NSError* error) {
                auto event = Object(runtime);
                event.setProperty(runtime, "socketId", String::createFromUtf8(runtime, [[sockId stringValue] UTF8String]));
                event.setProperty(runtime, "error", String::createFromUtf8(runtime, [[error localizedDescription] UTF8String]));
                
                onError->call(runtime, event);
            };
        }
        
        if (onClose) {
            manager.onSocketClosed = ^(NSNumber* sockId, NSError* _Nullable error) {
                auto event = Object(runtime);
                event.setProperty(runtime, "socketId", String::createFromUtf8(runtime, [[sockId stringValue] UTF8String]));
                if (error) {
                    event.setProperty(runtime, "error", String::createFromUtf8(runtime, [[error localizedDescription] UTF8String]));
                }
                
                onClose->call(runtime, event);
            };
        }
        
        // Start receiving
        [manager startReceivingOnBoundSockets];
        
        NSLog(@"[UDPDirectJSI] Event handlers set for socket %@", socketId);
        return Value::undefined();
        
    } @catch (NSException *exception) {
        std::string error = "Native exception: " + std::string([exception.reason UTF8String]);
        throw JSError(runtime, error);
    }
}

} // namespace react
} // namespace facebook