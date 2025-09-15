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
 */

#pragma once

// Platform compatibility definitions

#ifdef __OBJC__
#import <Foundation/Foundation.h>
#import <React/RCTEventEmitter.h>
#import <React/RCTBridgeModule.h>
#import <React-NativeModulesApple/ReactCommon/RCTTurboModule.h>

NS_ASSUME_NONNULL_BEGIN

// Forward declare UDPDirectModule class - the actual interface is defined in UDPDirectModule.h
@class UDPDirectModule;

NS_ASSUME_NONNULL_END

#else // __OBJC__
// C/C++ only section

#ifdef __cplusplus
// In C++ mode, use properly typed forward declarations with extern "C++"
// This preserves type safety while avoiding redefinition issues
extern "C++" {
  // Forward declare the Objective-C class as an opaque type
  class UDPDirectModule;
  // Define a properly-typed nullable pointer using modern C++ convention
  using UDPDirectModulePtr = UDPDirectModule* _Nullable;
}
#endif // __cplusplus

#endif // __OBJC__ 