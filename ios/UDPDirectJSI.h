#pragma once

#include <jsi/jsi.h>
#include <memory>
#include <ReactCommon/CallInvoker.h>

#ifdef __OBJC__
@class UDPSocketManager;
#endif

namespace facebook {
namespace react {

class UDPDirectJSI {
public:
    static void install(jsi::Runtime& runtime, void* socketManager, std::shared_ptr<CallInvoker> jsInvoker);
    
private:
    // Core JSI functions
    static jsi::Value udpSendDirect(
        jsi::Runtime& runtime,
        const jsi::Value& thisValue,
        const jsi::Value* arguments,
        size_t count
    );
    
    static jsi::Value createUdpSocket(
        jsi::Runtime& runtime,
        const jsi::Value& thisValue,
        const jsi::Value* arguments,
        size_t count
    );
    
    static jsi::Value bindSocket(
        jsi::Runtime& runtime,
        const jsi::Value& thisValue,
        const jsi::Value* arguments,
        size_t count
    );
    
    static jsi::Value closeSocket(
        jsi::Runtime& runtime,
        const jsi::Value& thisValue,
        const jsi::Value* arguments,
        size_t count
    );
    
    static jsi::Value setEventHandler(
        jsi::Runtime& runtime,
        const jsi::Value& thisValue,
        const jsi::Value* arguments,
        size_t count
    );
    
    // Helper to get socket manager
    static void* getSocketManager(jsi::Runtime& runtime);
};

} // namespace react
} // namespace facebook