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
 * SharedBufferHostObject.h - Header for the SharedBuffer JSI host object
 * This file defines a JavaScript Interface (JSI) host object that provides
 * direct access to native memory buffers for high-performance data transfer.
 * 
 * Note: This file contains mixed Objective-C++ and C++ code for React Native
 * JSI integration. If you see IDE/IntelliSense errors, they can be safely
 * ignored as the file compiles correctly with Xcode.
 */

#pragma once

// Handle VSCode IntelliSense which doesn't properly recognize Objective-C++ code
#ifdef __INTELLISENSE__
  // Provide minimal definitions to satisfy IntelliSense
  #define __OBJC__ 1
  #define JSI_NULLABLE
  namespace facebook { namespace jsi {
    class Runtime; class Value; class PropNameID; class HostObject;
  }}
  #define NS_ASSUME_NONNULL_BEGIN
  #define NS_ASSUME_NONNULL_END
#else
  // Define nullability macros for cross-compilation compatibility
  #ifdef __OBJC__
    // In Objective-C mode, use the standard nullability annotations
    #ifndef JSI_NULLABLE
      #define JSI_NULLABLE _Nullable
    #endif
  #else
    // In pure C++ mode, nullability annotations are not supported
    #ifndef JSI_NULLABLE
      #define JSI_NULLABLE
    #endif
  #endif
#endif

// Include JSI compatibility header
#import <jsi/jsi.h>
#import <memory>
#import <string>
#import <vector>

// No compatibility layer needed for current RN version

// Standard C++ headers
#include <memory>
#include <vector>

// Forward declarations
namespace facebook { namespace jsi { class Runtime; } }
namespace facebook { namespace react { class CallInvoker; } }
@class UDPSocketManager; // Forward declare UDPSocketManager

/**
 * SharedBufferHostObject
 *
 * This class implements a JSI HostObject that wraps a native buffer
 * for zero-copy access from JavaScript. It maintains a reference to
 * the UDPDirectModule and the buffer ID.
 */
class SharedBufferHostObject : public facebook::jsi::HostObject {
public:
  /**
   * Constructor
   *
   * @param runtime The JSI runtime
   * @param manager The UDPSocketManager instance
   * @param bufferId The ID of the buffer in the native module
   * @param jsCallInvoker The jsCallInvoker for the module
   */
  SharedBufferHostObject(
    facebook::jsi::Runtime& runtime,
    UDPSocketManager *manager,
    int bufferId,
    std::shared_ptr<facebook::react::CallInvoker> jsCallInvoker = nullptr
  );
  
  /**
   * Destructor - ensures proper cleanup of resources
   */
  ~SharedBufferHostObject() override;
  
  /**
   * Get JSI properties for this host object
   */
  facebook::jsi::Value get(
    facebook::jsi::Runtime& runtime,
    const facebook::jsi::PropNameID& name
  ) override;
  
  /**
   * Set JSI properties for this host object
   */
  void set(
    facebook::jsi::Runtime& runtime,
    const facebook::jsi::PropNameID& name,
    const facebook::jsi::Value& value
  ) override;
  
  /**
   * Get names of JSI properties for this host object
   */
  std::vector<facebook::jsi::PropNameID> getPropertyNames(
    facebook::jsi::Runtime& runtime
  ) override;
  
  /**
   * Get the buffer ID
   */
  int getBufferId() const {
    return bufferId_;
  }
  
  /**
   * Get the underlying NSMutableData pointer from the module.
   * This is a helper and not directly exposed to JSI.
   */
  NSMutableData* getNativeBuffer();
  
private:
  facebook::jsi::Runtime& runtime_; // Store runtime for creating JSI objects
  UDPSocketManager *socketManager_;
  int bufferId_;
  std::shared_ptr<facebook::react::CallInvoker> jsCallInvoker_;
};