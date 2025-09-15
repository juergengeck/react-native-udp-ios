// Standard imports
#import "UDPDirectModuleCxxImpl.h"
#import "UDPSocketManager.h"
#import "UDPDirectJSI.h"

#import <React/RCTUtils.h>
#import <jsi/jsi.h>
#import <ReactCommon/TurboModuleUtils.h>
#include <memory>
#include <functional>

namespace facebook {
namespace react {

using namespace facebook::jsi;

// Constructor - use the template base class constructor  
UDPDirectModuleCxxImpl::UDPDirectModuleCxxImpl(std::shared_ptr<CallInvoker> jsInvoker)
  : NativeUDPDirectModuleCxxSpec<UDPDirectModuleCxxImpl>(jsInvoker),
    socketManager_(nullptr),
    isBeingDestroyed_(false),
    jsInvoker_(jsInvoker),
    jsiInstalled_(false) {
    
    NSLog(@"[UDPDirectModuleCxxImpl] Lightweight TurboModule initialization - deferring resource allocation");
    // Note: Socket manager will be created lazily when first needed
}

UDPDirectModuleCxxImpl::~UDPDirectModuleCxxImpl() {
    NSLog(@"[UDPDirectModuleCxxImpl] Destructor called");
    
    // Set destruction flag IMMEDIATELY to prevent any callback execution
    isBeingDestroyed_ = true;
    
    // Simple cleanup - socket manager may not even exist if never used
    if (socketManager_) {
        NSLog(@"[UDPDirectModuleCxxImpl] Releasing socket manager");
        UDPSocketManager *manager = (__bridge_transfer UDPSocketManager *)socketManager_;
        // Clear callbacks to prevent any lingering references
        manager.onDataReceived = nil;
        manager.onSocketClosed = nil;
        manager.onSendSuccess = nil;
        manager.onSendFailure = nil;
        // Let ARC handle the rest - no complex synchronous operations
        manager = nil;
        socketManager_ = nullptr;
        NSLog(@"[UDPDirectModuleCxxImpl] Socket manager released via ARC");
    } else {
        NSLog(@"[UDPDirectModuleCxxImpl] No socket manager to clean up");
    }
}

// Helper to get the socket manager - creates it lazily when first needed
UDPSocketManager* UDPDirectModuleCxxImpl::getSocketManager() {
    NSLog(@"[UDPDirectModuleCxxImpl] getSocketManager called");
    
    // Check if we're shutting down
    if (isBeingDestroyed_) {
        NSLog(@"[UDPDirectModuleCxxImpl] Module is being destroyed, refusing to create socket manager");
        return nil;
    }
    
    // Lazy initialization - only create when first needed
    if (!socketManager_) {
        NSLog(@"[UDPDirectModuleCxxImpl] Lazy initialization of socket manager");
        
        // Create the Objective-C socket manager with a dedicated queue
        dispatch_queue_t udpQueue = dispatch_queue_create("com.lama.udp.socket.queue", DISPATCH_QUEUE_SERIAL);
        UDPSocketManager *manager = [[UDPSocketManager alloc] initWithDelegateQueue:udpQueue];
        
        // Initialize with safe default callbacks
        manager.onDataReceived = ^(NSNumber* socketId, NSData* data, NSString* host, uint16_t port, NSNumber* bufferId) {
            NSLog(@"[UDPDirectModuleCxxImpl] Default data callback - socket %@", socketId);
        };
        
        manager.onSocketClosed = ^(NSNumber* socketId, NSError* _Nullable error) {
            NSLog(@"[UDPDirectModuleCxxImpl] Default close callback - socket %@", socketId);
        };
        
        manager.onSendSuccess = ^(NSNumber* socketId, long tag) {
            NSLog(@"[UDPDirectModuleCxxImpl] Default success callback - socket %@", socketId);
        };
        
        manager.onSendFailure = ^(NSNumber* socketId, long tag, NSError* error) {
            NSLog(@"[UDPDirectModuleCxxImpl] Default failure callback - socket %@: %@", socketId, error.localizedDescription);
        };
        
        socketManager_ = (__bridge_retained void *)manager;
        NSLog(@"[UDPDirectModuleCxxImpl] Socket manager created lazily: %p", socketManager_);
    }
    
    @try {
        UDPSocketManager *manager = (__bridge UDPSocketManager *)socketManager_;
        if (!manager) {
            NSLog(@"[UDPDirectModuleCxxImpl] ERROR: Bridge cast returned null manager");
            return nil;
        }
        return manager;
    } @catch (NSException *exception) {
        NSLog(@"[UDPDirectModuleCxxImpl] Exception accessing socket manager: %@", exception);
        return nil;
    }
}


// TURBO MODULE METHODS
jsi::Object UDPDirectModuleCxxImpl::getConstants(jsi::Runtime &rt) {
    NSLog(@"[UDPDirectModuleCxxImpl] getConstants called - TurboModule bridge is working");
    auto constants = jsi::Object(rt);
    constants.setProperty(rt, "VERSION", jsi::String::createFromUtf8(rt, "1.0.0"));
    constants.setProperty(rt, "TURBO_ENABLED", jsi::Value(true));
    return constants;
}

void UDPDirectModuleCxxImpl::addListener(jsi::Runtime &rt, jsi::String eventName) {
    std::string eventNameStr = eventName.utf8(rt);
    eventListenerCounts_[eventNameStr]++;
    NSLog(@"[UDPDirectModuleCxxImpl] Added listener for event: %s (count: %d)", 
          eventNameStr.c_str(), eventListenerCounts_[eventNameStr]);
}

void UDPDirectModuleCxxImpl::removeListeners(jsi::Runtime &rt, double count) {
    NSLog(@"[UDPDirectModuleCxxImpl] Removing %d listeners", (int)count);
    
    // Simple implementation: reduce all event listener counts
    for (auto& pair : eventListenerCounts_) {
        pair.second = std::max(0, pair.second - (int)count);
    }
}

// UDP SOCKET METHOD IMPLEMENTATIONS
jsi::Value UDPDirectModuleCxxImpl::createSocket(jsi::Runtime &rt, jsi::Object options) {
    NSLog(@"[UDPDirectModuleCxxImpl] createSocket called - creating REAL socket");
    
    // Install JSI bindings on first use
    if (!jsiInstalled_ && socketManager_) {
        installJSIBindings(rt);
    }
    
    try {
        UDPSocketManager *manager = getSocketManager();
        if (!manager) {
            NSLog(@"[UDPDirectModuleCxxImpl] ERROR: Socket manager not available");
            throw jsi::JSError(rt, "Socket manager not available");
        }
        
        NSLog(@"[UDPDirectModuleCxxImpl] Socket manager available: %p", manager);
        
        // Convert JSI options to NSDictionary for the socket manager
        NSMutableDictionary *nsOptions = [NSMutableDictionary dictionary];
        
        // Extract socket type (default to udp4)
        if (options.hasProperty(rt, "type")) {
            jsi::Value typeValue = options.getProperty(rt, "type");
            if (typeValue.isString()) {
                std::string type = typeValue.getString(rt).utf8(rt);
                nsOptions[@"type"] = [NSString stringWithUTF8String:type.c_str()];
                NSLog(@"[UDPDirectModuleCxxImpl] Socket type: %s", type.c_str());
            }
        } else {
            nsOptions[@"type"] = @"udp4"; // Default
        }
        
        // Extract reuseAddr option  
        if (options.hasProperty(rt, "reuseAddr")) {
            jsi::Value reuseAddrValue = options.getProperty(rt, "reuseAddr");
            if (reuseAddrValue.isBool()) {
                nsOptions[@"reuseAddr"] = @(reuseAddrValue.getBool());
                NSLog(@"[UDPDirectModuleCxxImpl] Socket reuseAddr: %d", reuseAddrValue.getBool());
            }
        }
        
        // Extract reusePort option
        if (options.hasProperty(rt, "reusePort")) {
            jsi::Value reusePortValue = options.getProperty(rt, "reusePort");
            if (reusePortValue.isBool()) {
                nsOptions[@"reusePort"] = @(reusePortValue.getBool());
                NSLog(@"[UDPDirectModuleCxxImpl] Socket reusePort: %d", reusePortValue.getBool());
            }
        }
        
        // Extract broadcast option
        if (options.hasProperty(rt, "broadcast")) {
            jsi::Value broadcastValue = options.getProperty(rt, "broadcast");
            if (broadcastValue.isBool()) {
                nsOptions[@"broadcast"] = @(broadcastValue.getBool());
                NSLog(@"[UDPDirectModuleCxxImpl] Socket broadcast: %d", broadcastValue.getBool());
            }
        }
        
        NSLog(@"[UDPDirectModuleCxxImpl] Creating socket with options: %@", nsOptions);
        
        // Create the actual socket using the manager
        NSError *error = nil;
        NSNumber *socketId = [manager createSocketWithOptions:nsOptions error:&error];
        
        if (!socketId) {
            std::string errorMsg = "Failed to create UDP socket";
            if (error) {
                errorMsg += ": " + std::string([[error localizedDescription] UTF8String]);
                NSLog(@"[UDPDirectModuleCxxImpl] Socket creation failed: %@", error);
            }
            throw jsi::JSError(rt, errorMsg);
        }
        
        NSLog(@"[UDPDirectModuleCxxImpl] Socket created successfully with ID: %@", socketId);
        
        // Return socket object with the REAL socketId as string
        auto socketObj = jsi::Object(rt);
        socketObj.setProperty(rt, "socketId", jsi::String::createFromUtf8(rt, [[socketId stringValue] UTF8String]));
        
        NSLog(@"[UDPDirectModuleCxxImpl] Returning real socket object with ID: %@", socketId);
        return socketObj;
        
    } catch (const jsi::JSError& e) {
        NSLog(@"[UDPDirectModuleCxxImpl] JSI Error in createSocket: %s", e.getMessage().c_str());
        throw;
    } catch (...) {
        NSLog(@"[UDPDirectModuleCxxImpl] Unknown error creating socket");
        throw jsi::JSError(rt, "Unknown error creating socket");
    }
}

jsi::Value UDPDirectModuleCxxImpl::bind(jsi::Runtime &rt, jsi::String socketId, double port, jsi::String address) {
    NSLog(@"[UDPDirectModuleCxxImpl] bind called");
    
    try {
        UDPSocketManager *manager = getSocketManager();
        if (!manager) {
            NSLog(@"[UDPDirectModuleCxxImpl] ERROR: Socket manager not available for bind");
            throw jsi::JSError(rt, "Socket manager not available");
        }
        
        // Convert string socketId to NSNumber
        std::string socketIdStr = socketId.utf8(rt);
        NSNumber *nsSocketId = @(std::stoi(socketIdStr));
        NSString *nsAddress = [NSString stringWithUTF8String:address.utf8(rt).c_str()];
        
        NSLog(@"[UDPDirectModuleCxxImpl] Binding socket %@ to %@:%d", nsSocketId, nsAddress, (int)port);
        
        NSError *error = nil;
        BOOL success = [manager bindSocket:nsSocketId toPort:(uint16_t)port address:nsAddress error:&error];
        
        if (success) {
            NSLog(@"[UDPDirectModuleCxxImpl] Successfully bound socket %@ to %@:%d", nsSocketId, nsAddress, (int)port);
            return jsi::Value::undefined();
        } else {
            std::string errorMsg = "Failed to bind socket";
            if (error) {
                errorMsg += ": " + std::string([[error localizedDescription] UTF8String]);
                NSLog(@"[UDPDirectModuleCxxImpl] Bind failed: %@", error);
            }
            throw jsi::JSError(rt, errorMsg);
        }
        
    } catch (const jsi::JSError& e) {
        NSLog(@"[UDPDirectModuleCxxImpl] JSI Error in bind: %s", e.getMessage().c_str());
        throw;
    } catch (...) {
        NSLog(@"[UDPDirectModuleCxxImpl] Unknown error binding socket");
        throw jsi::JSError(rt, "Unknown error binding socket");
    }
}

jsi::Value UDPDirectModuleCxxImpl::close(jsi::Runtime &rt, jsi::String socketId) {
    try {
        UDPSocketManager *manager = getSocketManager();
        if (!manager) {
            throw jsi::JSError(rt, "Socket manager not available");
        }
        
        // Convert string socketId to NSNumber
        std::string socketIdStr = socketId.utf8(rt);
        NSNumber *nsSocketId = @(std::stoi(socketIdStr));
        [manager closeSocket:nsSocketId];
        
        NSLog(@"[UDPDirectModuleCxxImpl] Successfully closed socket %@", nsSocketId);
        return jsi::Value::undefined();
        
    } catch (const jsi::JSError& e) {
        throw;
    } catch (...) {
        throw jsi::JSError(rt, "Unknown error closing socket");
    }
}

jsi::Value UDPDirectModuleCxxImpl::closeAllSockets(jsi::Runtime &rt) {
    try {
        UDPSocketManager *manager = getSocketManager();
        if (!manager) {
            throw jsi::JSError(rt, "Socket manager not available");
        }
        
        [manager closeAllSockets];
        NSLog(@"[UDPDirectModuleCxxImpl] Closed all sockets");
        return jsi::Value::undefined();
        
    } catch (...) {
        throw jsi::JSError(rt, "Unknown error closing all sockets");
    }
}

jsi::Value UDPDirectModuleCxxImpl::send(jsi::Runtime &rt, jsi::String socketId, jsi::String base64Data, double port, jsi::String address, std::optional<jsi::Object> options) {
    try {
        UDPSocketManager *manager = getSocketManager();
        if (!manager) {
            throw jsi::JSError(rt, "Socket manager not available");
        }
        
        // Convert string socketId to NSNumber
        std::string socketIdStr = socketId.utf8(rt);
        NSNumber *nsSocketId = @(std::stoi(socketIdStr));
        NSString *nsBase64Data = [NSString stringWithUTF8String:base64Data.utf8(rt).c_str()];
        NSString *nsAddress = [NSString stringWithUTF8String:address.utf8(rt).c_str()];
        
        // Decode base64 data
        NSData *nsData = [[NSData alloc] initWithBase64EncodedString:nsBase64Data options:0];
        if (!nsData) {
            throw jsi::JSError(rt, "Invalid base64 data");
        }
        
        // Send data (this is async, so we use tag 0 for now)
        [manager sendData:nsData onSocket:nsSocketId toHost:nsAddress port:(uint16_t)port tag:0];
        
        NSLog(@"[UDPDirectModuleCxxImpl] Initiated send from socket %@", nsSocketId);
        return jsi::Value::undefined();
        
    } catch (const jsi::JSError& e) {
        throw;
    } catch (...) {
        throw jsi::JSError(rt, "Unknown error sending data");
    }
}

#if 0 // Temporarily disabled advanced zero-copy implementations (see header)
jsi::Value UDPDirectModuleCxxImpl::sendBinary(jsi::Runtime &rt, jsi::String socketId, jsi::Object data, double port, jsi::String address, std::optional<jsi::Object> options) {
    try {
        UDPSocketManager *manager = getSocketManager();
        if (!manager) {
            throw jsi::JSError(rt, "Socket manager not available");
        }
        
        // Convert string socketId to NSNumber
        std::string socketIdStr = socketId.utf8(rt);
        NSNumber *nsSocketId = @(std::stoi(socketIdStr));
        NSString *nsAddress = [NSString stringWithUTF8String:address.utf8(rt).c_str()];
        
        // Handle ArrayBuffer or similar binary data object
        NSData *nsData = nil;
        
        // Check if it's an ArrayBuffer
        if (data.isArrayBuffer(rt)) {
            auto arrayBuffer = data.getArrayBuffer(rt);
            nsData = [NSData dataWithBytes:arrayBuffer.data(rt) length:arrayBuffer.size(rt)];
        } else {
            // Try to get it as a typed array or other buffer type
            throw jsi::JSError(rt, "sendBinary expects an ArrayBuffer");
        }
        
        if (!nsData) {
            throw jsi::JSError(rt, "Failed to extract binary data");
        }
        
        // Send data (this is async, so we use tag 0 for now)
        [manager sendData:nsData onSocket:nsSocketId toHost:nsAddress port:(uint16_t)port tag:0];
        
        NSLog(@"[UDPDirectModuleCxxImpl] Initiated binary send from socket %@", nsSocketId);
        return jsi::Value::undefined();
        
    } catch (const jsi::JSError& e) {
        throw;
    } catch (...) {
        throw jsi::JSError(rt, "Unknown error sending binary data");
    }
}
#endif


jsi::Array UDPDirectModuleCxxImpl::getLocalIPAddresses(jsi::Runtime &rt) {
    try {
        UDPSocketManager *manager = getSocketManager();
        if (!manager) {
            throw jsi::JSError(rt, "Socket manager not available");
        }
        
        NSArray<NSString *> *addresses = [manager getLocalIPAddresses];
        auto jsArray = jsi::Array(rt, addresses.count);
        
        for (NSUInteger i = 0; i < addresses.count; i++) {
            NSString *address = addresses[i];
            jsArray.setValueAtIndex(rt, i, jsi::String::createFromUtf8(rt, [address UTF8String]));
        }
        
        return jsArray;
        
    } catch (const jsi::JSError& e) {
        throw;
    } catch (...) {
        throw jsi::JSError(rt, "Unknown error getting local IP addresses");
    }
}

jsi::Value UDPDirectModuleCxxImpl::address(jsi::Runtime &rt, jsi::String socketId) {
    try {
        UDPSocketManager *manager = getSocketManager();
        if (!manager) {
            throw jsi::JSError(rt, "Socket manager not available");
        }
        
        // Convert string socketId to NSNumber
        std::string socketIdStr = socketId.utf8(rt);
        NSNumber *nsSocketId = @(std::stoi(socketIdStr));
        NSDictionary *addressInfo = [manager getSocketAddress:nsSocketId];
        
        if (addressInfo) {
            auto addressObj = jsi::Object(rt);
            
            NSString *address = addressInfo[@"address"];
            NSNumber *port = addressInfo[@"port"];
            NSString *family = addressInfo[@"family"];
            
            if (address) {
                addressObj.setProperty(rt, "address", jsi::String::createFromUtf8(rt, [address UTF8String]));
            }
            if (port) {
                addressObj.setProperty(rt, "port", jsi::Value((double)[port intValue]));
            }
            if (family) {
                addressObj.setProperty(rt, "family", jsi::String::createFromUtf8(rt, [family UTF8String]));
            }
            
            return addressObj;
        } else {
            return jsi::Value::null();
        }
        
    } catch (const jsi::JSError& e) {
        throw;
    } catch (...) {
        throw jsi::JSError(rt, "Unknown error getting socket address");
    }
}

jsi::Value UDPDirectModuleCxxImpl::setBroadcast(jsi::Runtime &rt, jsi::String socketId, bool flag) {
    try {
        UDPSocketManager *manager = getSocketManager();
        if (!manager) {
            throw jsi::JSError(rt, "Socket manager not available");
        }
        
        // Convert string socketId to NSNumber  
        std::string socketIdStr = socketId.utf8(rt);
        NSNumber *nsSocketId = @(std::stoi(socketIdStr));
        NSError *error = nil;
        BOOL success = [manager setBroadcast:nsSocketId enable:flag error:&error];
        
        if (success) {
            return jsi::Value::undefined();
        } else {
            std::string errorMsg = "Failed to set broadcast option";
            if (error) {
                errorMsg += ": " + std::string([[error localizedDescription] UTF8String]);
            }
            throw jsi::JSError(rt, errorMsg);
        }
        
    } catch (const jsi::JSError& e) {
        throw;
    } catch (...) {
        throw jsi::JSError(rt, "Unknown error setting broadcast");
    }
}

// REMAINING STUB METHODS (advanced API now handled purely via JSI – stub code excluded from Obj-C++ build)
#if 0 // Disabled – TurboModule no longer references these methods
jsi::Value UDPDirectModuleCxxImpl::sendFromArrayBuffer(jsi::Runtime &rt, jsi::String socketId, double bufferId, double offset, double length, double port, jsi::String address, std::optional<jsi::Object> options) {
    return jsi::Value::undefined(); // TODO: Implement if needed
}

jsi::Value UDPDirectModuleCxxImpl::createSharedArrayBuffer(jsi::Runtime &rt, double size) {
    try {
        UDPSocketManager *manager = getSocketManager();
        if (!manager) {
            throw jsi::JSError(rt, "Socket manager not available for buffer creation");
        }
        
        NSNumber *bufferId = [manager createManagedBufferOfSize:(NSUInteger)size];
        if (!bufferId) {
            throw jsi::JSError(rt, "Failed to create managed buffer in UDPSocketManager");
        }
        
        // Create a JSI object to return to JavaScript: { bufferId: ... }
        jsi::Object result = jsi::Object(rt);
        result.setProperty(rt, "bufferId", jsi::Value([bufferId doubleValue]));
        
        return result;
        
    } catch (const jsi::JSError& e) {
        throw;
    } catch (NSException *exception) {
        throw jsi::JSError(rt, [[NSString stringWithFormat:@"Exception creating shared buffer: %@", exception.reason] UTF8String]);
    } catch (...) {
        throw jsi::JSError(rt, "Unknown error creating shared buffer");
    }
}

jsi::Value UDPDirectModuleCxxImpl::releaseSharedArrayBuffer(jsi::Runtime &rt, double bufferId) {
    try {
        UDPSocketManager *manager = getSocketManager();
        if (!manager) {
            // It's possible the manager is gone during shutdown, so don't throw, just log.
            NSLog(@"[UDPDirectModuleCxxImpl] Socket manager not available for buffer release, skipping.");
            return jsi::Value::undefined();
        }
        
        [manager releaseManagedBuffer:[NSNumber numberWithDouble:bufferId]];
        
        return jsi::Value::undefined();
        
    } catch (const jsi::JSError& e) {
        throw;
    } catch (NSException *exception) {
        // Log the error but don't crash the app during a release operation
        NSLog(@"[UDPDirectModuleCxxImpl] Exception releasing shared buffer: %@", exception.reason);
        return jsi::Value::undefined();
    } catch (...) {
        NSLog(@"[UDPDirectModuleCxxImpl] Unknown error releasing shared buffer");
        return jsi::Value::undefined();
    }
}

jsi::Value UDPDirectModuleCxxImpl::getSharedBufferObject(jsi::Runtime &rt, double bufferId) {
    return jsi::Value::undefined(); // TODO: Implement if needed
}

jsi::Value UDPDirectModuleCxxImpl::setMulticastInterface(jsi::Runtime &rt, jsi::String socketId, jsi::String multicastInterfaceAddress) {
    return jsi::Value::undefined(); // TODO: Implement if needed
}

#endif

// EVENT HANDLER SETUP - CRITICAL FOR PREVENTING CRASHES
jsi::Value UDPDirectModuleCxxImpl::setDataEventHandler(jsi::Runtime &rt, jsi::String socketId) {
    try {
        UDPSocketManager *manager = getSocketManager();
        if (!manager) {
            throw jsi::JSError(rt, "Socket manager not available");
        }
        
        NSLog(@"[UDPDirectModuleCxxImpl] Setting up data event handler for socket: %@", [NSString stringWithUTF8String:socketId.utf8(rt).c_str()]);
        
        // Store a raw pointer for safe checking - callbacks will be cleared in destructor
        UDPDirectModuleCxxImpl* selfPtr = this;
        
        // Set up the data received callback with validity checking
        manager.onDataReceived = ^(NSNumber* socketId, NSData* data, NSString* host, uint16_t port, NSNumber* bufferId) {
            NSLog(@"[UDPDirectModuleCxxImpl] Data received callback - Socket: %@, Data size: %lu, From: %@:%u, BufferId: %@", 
                  socketId, (unsigned long)data.length, host, port, bufferId);
            
            // CRITICAL: Check if module is being destroyed before any operation
            if (!selfPtr || selfPtr->isBeingDestroyed_) {
                NSLog(@"[UDPDirectModuleCxxImpl] Data callback called on destroyed module, skipping completely");
                return;
            }
            
            @try {
                // Convert data to base64 for safe transport
                NSString *base64Data = [data base64EncodedStringWithOptions:0];
                
                // Additional safety check before emitDeviceEvent
                if (!selfPtr || selfPtr->isBeingDestroyed_) {
                    NSLog(@"[UDPDirectModuleCxxImpl] Module destroyed during callback, aborting emit completely");
                    return;
                }
                
                // Use NSNotificationCenter to emit events to the Objective-C provider
                // This avoids direct JSI calls from background threads
                @try {
                    // Create event data dictionary
                    NSDictionary *eventData = @{
                        @"eventName": @"message",
                        @"socketId": [socketId stringValue],
                        @"data": base64Data,
                        @"address": host,
                        @"port": @(port),
                        @"family": @"IPv4",
                        @"bufferId": bufferId ?: [NSNull null]
                    };
                    
                    // Use simplified logging for now to avoid JSI complications
                    std::string eventDataStr = "socketId=" + std::string([[socketId stringValue] UTF8String]) + 
                                             ", address=" + std::string([host UTF8String]) + 
                                             ", port=" + std::to_string(port) +
                                             ", dataLength=" + std::to_string([base64Data length]);
                    selfPtr->logEvent("message", eventDataStr);
                    
                    NSLog(@"[UDPDirectModuleCxxImpl] Logged 'message' event safely");
                } @catch (NSException *emitException) {
                    NSLog(@"[UDPDirectModuleCxxImpl] Exception during event notification: %@", emitException);
                }
                
            } @catch (NSException *exception) {
                NSLog(@"[UDPDirectModuleCxxImpl] Exception during message event emission: %@", exception);
            }
        };
        
        // Set up error/close callbacks with validity checking
        manager.onSocketClosed = ^(NSNumber* socketId, NSError* _Nullable error) {
            NSLog(@"[UDPDirectModuleCxxImpl] Socket closed callback - Socket: %@, Error: %@", socketId, error);
            
            // CRITICAL: Check if module is being destroyed before any operation
            if (!selfPtr || selfPtr->isBeingDestroyed_) {
                NSLog(@"[UDPDirectModuleCxxImpl] Close callback called on destroyed module, skipping completely");
                return;
            }
            
            @try {
                // Additional safety check before emitDeviceEvent
                if (!selfPtr || selfPtr->isBeingDestroyed_) {
                    NSLog(@"[UDPDirectModuleCxxImpl] Module destroyed during close callback, aborting emit completely");
                    return;
                }
                
                // Use NSNotificationCenter to emit events to the Objective-C provider
                // This avoids direct JSI calls from background threads
                @try {
                    // Create event data dictionary
                    NSDictionary *eventData = @{
                        @"eventName": @"close",
                        @"socketId": [socketId stringValue],
                        @"error": error ? [error localizedDescription] : [NSNull null]
                    };
                    
                    // Use simplified logging for now to avoid JSI complications  
                    std::string eventDataStr = "socketId=" + std::string([[socketId stringValue] UTF8String]);
                    if (error) {
                        eventDataStr += ", error=" + std::string([[error localizedDescription] UTF8String]);
                    }
                    selfPtr->logEvent("close", eventDataStr);
                    
                    NSLog(@"[UDPDirectModuleCxxImpl] Logged 'close' event safely");
                } @catch (NSException *emitException) {
                    NSLog(@"[UDPDirectModuleCxxImpl] Exception during event notification: %@", emitException);
                }
                
            } @catch (NSException *exception) {
                NSLog(@"[UDPDirectModuleCxxImpl] Exception during close event emission: %@", exception);
            }
        };
        
        manager.onSendFailure = ^(NSNumber* socketId, long tag, NSError* error) {
            NSLog(@"[UDPDirectModuleCxxImpl] Send failure callback - Socket: %@, Tag: %ld, Error: %@", socketId, tag, error);
            
            // CRITICAL: Check if module is being destroyed before any operation
            if (!selfPtr || selfPtr->isBeingDestroyed_) {
                NSLog(@"[UDPDirectModuleCxxImpl] Send failure callback called on destroyed module, skipping completely");
                return;
            }
            
            @try {
                // Additional safety check before emitDeviceEvent
                if (!selfPtr || selfPtr->isBeingDestroyed_) {
                    NSLog(@"[UDPDirectModuleCxxImpl] Module destroyed during send failure callback, aborting emit completely");
                    return;
                }
                
                // Use NSNotificationCenter to emit events to the Objective-C provider
                // This avoids direct JSI calls from background threads
                @try {
                    // Create event data dictionary
                    NSDictionary *eventData = @{
                        @"eventName": @"error",
                        @"socketId": [socketId stringValue],
                        @"tag": @(tag),
                        @"error": [error localizedDescription]
                    };
                    
                    // Use simplified logging for now to avoid JSI complications
                    std::string eventDataStr = "socketId=" + std::string([[socketId stringValue] UTF8String]) + 
                                             ", error=" + std::string([[error localizedDescription] UTF8String]) +
                                             ", errno=" + std::to_string([error code]);
                    selfPtr->logEvent("error", eventDataStr);
                    
                    NSLog(@"[UDPDirectModuleCxxImpl] Logged 'error' event safely");
                } @catch (NSException *emitException) {
                    NSLog(@"[UDPDirectModuleCxxImpl] Exception during event notification: %@", emitException);
                }
                
            } @catch (NSException *exception) {
                NSLog(@"[UDPDirectModuleCxxImpl] Exception during error event emission: %@", exception);
            }
        };
        
        // Start receiving on any bound sockets now that callbacks are set up
        [manager startReceivingOnBoundSockets];
        
        NSLog(@"[UDPDirectModuleCxxImpl] Data event handlers configured successfully - callbacks will be cleared in destructor");
        return jsi::Value::undefined();
        
    } catch (const jsi::JSError& e) {
        throw;
    } catch (...) {
        throw jsi::JSError(rt, "Unknown error setting up data event handler");
    }
}

void UDPDirectModuleCxxImpl::emitDeviceEvent(const std::string& eventName, const std::function<void(jsi::Runtime& rt, jsi::Object& eventData)>& eventDataBuilder) {
    NSLog(@"[UDPDirectModuleCxxImpl] emitDeviceEvent called for event: %s", eventName.c_str());
    
    // Safety check - don't emit events during destruction
    if (isBeingDestroyed_) {
        NSLog(@"[UDPDirectModuleCxxImpl] Module being destroyed, skipping event emission");
        return;
    }
    
    // Check if there are any listeners for this event
    auto it = eventListenerCounts_.find(eventName);
    if (it == eventListenerCounts_.end() || it->second <= 0) {
        NSLog(@"[UDPDirectModuleCxxImpl] No listeners for event '%s', skipping emission", eventName.c_str());
        return;
    }
    
    if (!jsInvoker_) {
        NSLog(@"[UDPDirectModuleCxxImpl] ERROR: No JSI invoker available for event emission");
        return;
    }
    
    NSLog(@"[UDPDirectModuleCxxImpl] Emitting event '%s' to %d listeners", eventName.c_str(), it->second);
    
    // For now, we'll use the NSNotificationCenter approach but with proper safety and listener checking
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!isBeingDestroyed_) {
            // Create a simple event data dictionary for NSNotificationCenter
            NSMutableDictionary *eventData = [NSMutableDictionary dictionaryWithObject:[NSString stringWithUTF8String:eventName.c_str()] forKey:@"eventName"];
            
            // We can't easily use the JSI eventDataBuilder here, so we'll pass a minimal event
            // The proper solution would be to use JSI directly, but that requires runtime access
            
            [[NSNotificationCenter defaultCenter] postNotificationName:@"RNUDPModuleEvent"
                                                                object:nil
                                                              userInfo:eventData];
            NSLog(@"[UDPDirectModuleCxxImpl] Posted safe notification for event: %s", eventName.c_str());
        }
    });
}

void UDPDirectModuleCxxImpl::logEvent(const std::string& eventName, const std::string& data) {
    NSLog(@"[UDPDirectModuleCxxImpl] 🎯 EVENT: %s - %s", eventName.c_str(), data.c_str());
}

// diagnoseSocket is not part of the generated spec
// The implementation has been removed as it's not in the codegen spec

jsi::Value UDPDirectModuleCxxImpl::forciblyReleasePort(jsi::Runtime &rt, double port) {
    NSLog(@"[UDPDirectModuleCxxImpl] forciblyReleasePort called for port: %.0f", port);
    
    try {
        UDPSocketManager *manager = getSocketManager();
        if (!manager) {
            NSLog(@"[UDPDirectModuleCxxImpl] ERROR: Socket manager not available for forciblyReleasePort");
            throw jsi::JSError(rt, "Socket manager not available");
        }
        
        __block int closedCount = 0;
        __block bool released = false;
        __block NSError *operationError = nil;
        
        // Force synchronous operation on the delegate queue to ensure thread safety
        dispatch_sync([manager delegateQueue], ^{
            @try {
                NSMutableArray<NSNumber *> *socketsToClose = [NSMutableArray array];
                
                // Get all socket IDs and check which ones are bound to the specified port
                NSDictionary *asyncSockets = manager.asyncSockets;
                
                if (asyncSockets) {
                    NSArray *socketIds = [asyncSockets allKeys];
                    for (NSNumber *socketId in socketIds) {
                        GCDAsyncUdpSocket *socket = asyncSockets[socketId];
                        if (socket && [socket localPort] == (uint16_t)port) {
                            NSLog(@"[UDPDirectModuleCxxImpl] Found socket %@ on port %.0f. Current state: isClosed=%@", 
                                  socketId, port, [socket isClosed] ? @"YES" : @"NO");
                            if (![socket isClosed]) {
                                [socketsToClose addObject:socketId];
                            }
                        }
                    }
                }
                
                // Close all sockets found on the specified port
                for (NSNumber *socketId in socketsToClose) {
                    NSLog(@"[UDPDirectModuleCxxImpl] Forcibly closing socket %@ on port %.0f", socketId, port);
                    [manager closeSocket:socketId];
                    closedCount++;
                    released = true;
                }
                
                if (closedCount > 0) {
                    NSLog(@"[UDPDirectModuleCxxImpl] Successfully closed %d socket(s) on port %.0f", closedCount, port);
                } else {
                    NSLog(@"[UDPDirectModuleCxxImpl] No active sockets found on port %.0f", port);
                }
                
            } @catch (NSException *exception) {
                NSLog(@"[UDPDirectModuleCxxImpl] Exception in forciblyReleasePort: %@", exception);
                NSDictionary *userInfo = @{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Exception in forciblyReleasePort: %@", exception.reason]};
                operationError = [NSError errorWithDomain:@"UDPDirectModule" code:1001 userInfo:userInfo];
            }
        });
        
        // Check if there was an error during the operation
        if (operationError) {
            std::string errorMsg = "Failed to release port " + std::to_string((int)port);
            if (operationError.localizedDescription) {
                errorMsg += ": " + std::string([operationError.localizedDescription UTF8String]);
            }
            throw jsi::JSError(rt, errorMsg);
        }
        
        // Return result object matching the expected TypeScript interface
        auto result = jsi::Object(rt);
        result.setProperty(rt, "success", jsi::Value(released));
        
        NSLog(@"[UDPDirectModuleCxxImpl] forciblyReleasePort completed: released=%@, closedCount=%d", released ? @"true" : @"false", closedCount);
        return result;
        
    } catch (const jsi::JSError& e) {
        NSLog(@"[UDPDirectModuleCxxImpl] JSI Error in forciblyReleasePort: %s", e.getMessage().c_str());
        throw;
    } catch (...) {
        NSLog(@"[UDPDirectModuleCxxImpl] Unknown error in forciblyReleasePort");
        throw jsi::JSError(rt, "Unknown error in forciblyReleasePort");
    }
}

// Test method for debugging
jsi::Value UDPDirectModuleCxxImpl::testMethod(jsi::Runtime &rt) {
    NSLog(@"*** [UDPDirectModuleCxxImpl] testMethod called - basic TurboModule call works! ***");
    return jsi::Value(42); // Return a simple number
}

void UDPDirectModuleCxxImpl::setSocketManager(void* socketManager) {
    NSLog(@"[UDPDirectModuleCxxImpl] setSocketManager called");
    
    if (socketManager_) {
        NSLog(@"[UDPDirectModuleCxxImpl] Warning: Socket manager already set, replacing");
    }
    
    socketManager_ = socketManager;
}

void UDPDirectModuleCxxImpl::installJSIBindings(jsi::Runtime& runtime) {
    if (jsiInstalled_) {
        NSLog(@"[UDPDirectModuleCxxImpl] JSI bindings already installed");
        return;
    }
    
    if (!socketManager_) {
        NSLog(@"[UDPDirectModuleCxxImpl] Cannot install JSI bindings without socket manager");
        return;
    }
    
    if (!jsInvoker_) {
        NSLog(@"[UDPDirectModuleCxxImpl] Cannot install JSI bindings without JS invoker");
        return;
    }
    
    try {
        UDPDirectJSI::install(runtime, socketManager_, jsInvoker_);
        jsiInstalled_ = true;
        NSLog(@"[UDPDirectModuleCxxImpl] JSI bindings installed successfully with CallInvoker");
    } catch (const std::exception& e) {
        NSLog(@"[UDPDirectModuleCxxImpl] Failed to install JSI bindings: %s", e.what());
    }
}

} // namespace react
} // namespace facebook 