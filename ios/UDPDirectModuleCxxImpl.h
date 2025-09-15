#pragma once

// Standard C++ Headers
#include <optional>
#include <memory>
#include <map>

// React Native / JSI / Codegen Headers
#include <UDPDirectModuleSpecJSI.h>
#include <ReactCommon/TurboModuleUtils.h>
#include <jsi/jsi.h>

// Forward declare the Objective-C socket manager
#ifdef __OBJC__
@class UDPSocketManager;
#endif

// Forward declarations
namespace facebook {
namespace react {
class Promise;

// UDPDirectModuleCxxImpl extends the generated template spec, not the JSI base class
class UDPDirectModuleCxxImpl : public NativeUDPDirectModuleCxxSpec<UDPDirectModuleCxxImpl> {
public:
    explicit UDPDirectModuleCxxImpl(std::shared_ptr<CallInvoker> jsInvoker);
    virtual ~UDPDirectModuleCxxImpl();


    // UDP socket method implementations - must match spec exactly
    jsi::Value createSocket(jsi::Runtime &rt, jsi::Object options);
    jsi::Value bind(jsi::Runtime &rt, jsi::String socketId, double port, jsi::String address);
    jsi::Value close(jsi::Runtime &rt, jsi::String socketId);
    jsi::Value closeAllSockets(jsi::Runtime &rt);
    jsi::Value send(jsi::Runtime &rt, jsi::String socketId, jsi::String base64Data, double port, jsi::String address, std::optional<jsi::Object> options);
    /*
     * The following advanced zero-copy APIs are temporarily disabled while we
     * migrate to a dedicated JSI binding.  They are left here for future
     * re-activation but are compiled out to keep the TurboModule spec and the
     * generated Delegate in sync (otherwise Xcode fails because of pure
     * virtuals).
     */
#if 0
    jsi::Value sendBinary(jsi::Runtime &rt, jsi::String socketId, jsi::Object data, double port, jsi::String address, std::optional<jsi::Object> options);
    // Buffer management methods for zero-copy operations
    jsi::Value sendFromArrayBuffer(jsi::Runtime &rt, jsi::String socketId, double bufferId, double offset, double length, double port, jsi::String address, std::optional<jsi::Object> options);
    jsi::Value createSharedArrayBuffer(jsi::Runtime &rt, double size);
    jsi::Value releaseSharedArrayBuffer(jsi::Runtime &rt, double bufferId);
    jsi::Value getSharedBufferObject(jsi::Runtime &rt, double bufferId);
    jsi::Value setMulticastInterface(jsi::Runtime &rt, jsi::String socketId, jsi::String multicastInterfaceAddress);
#endif
    jsi::Array getLocalIPAddresses(jsi::Runtime &rt);
    jsi::Value address(jsi::Runtime &rt, jsi::String socketId);
    jsi::Value setBroadcast(jsi::Runtime &rt, jsi::String socketId, bool flag);
    jsi::Value setDataEventHandler(jsi::Runtime &rt, jsi::String socketId);
    jsi::Value forciblyReleasePort(jsi::Runtime &rt, double port);
    void addListener(jsi::Runtime &rt, jsi::String eventName);
    void removeListeners(jsi::Runtime &rt, double count);
    jsi::Object getConstants(jsi::Runtime &rt);
    
    // Test method for debugging (not in spec)
    jsi::Value testMethod(jsi::Runtime &rt);
    
    // Event emission method for TurboModule events  
    void emitDeviceEvent(const std::string& eventName, const std::function<void(jsi::Runtime& rt, jsi::Object& eventData)>& eventDataBuilder);
    
    // Simplified event emission for testing - just logs events
    void logEvent(const std::string& eventName, const std::string& data);
    
    // Set socket manager and install JSI
    void setSocketManager(void* socketManager);
    
    // Get the JS invoker for JSI installation
    std::shared_ptr<CallInvoker> getJSInvoker() const { return jsInvoker_; }

private:
    void* socketManager_; // Opaque pointer to UDPSocketManager to avoid Objective-C++ mixing
    bool isBeingDestroyed_; // Flag to prevent callbacks during destruction
    std::shared_ptr<CallInvoker> jsInvoker_; // JSI invoker for thread-safe JavaScript calls
    bool jsiInstalled_; // Track if JSI bindings are installed
    
    // Event listener registry
    std::map<std::string, int> eventListenerCounts_;
    
    // Helper methods
#ifdef __OBJC__
    UDPSocketManager* getSocketManager();
#endif
    
    // Install JSI bindings
    void installJSIBindings(jsi::Runtime& runtime);
};

} // namespace react
} // namespace facebook 