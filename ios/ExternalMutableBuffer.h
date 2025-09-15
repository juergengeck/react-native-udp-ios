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
 * ExternalMutableBuffer.h - Header for an external mutable JSI buffer implementation
 */
#pragma once

// React Native JSI includes
#include <jsi/jsi.h>
#include <functional>

/**
 * ExternalMutableBuffer implementation that provides a JSI buffer backed by
 * external memory (like NSData). It implements both Buffer and MutableBuffer 
 * interfaces to allow for read/write access.
 */
class ExternalMutableBuffer : public facebook::jsi::MutableBuffer {
public:
  /**
   * Constructor
   * 
   * @param data Pointer to the backing data buffer
   * @param size Size of the buffer in bytes
   * @param finalizeCallback Optional callback that will be invoked when this object is destroyed
   */
  ExternalMutableBuffer(
    void* data, 
    size_t size, 
    std::function<void()> finalizeCallback = nullptr
  ) : data_(data), size_(size), finalizeCallback_(std::move(finalizeCallback)) {}
  
  /**
   * Destructor - calls the finalize callback if provided
   */
  ~ExternalMutableBuffer() {
    if (finalizeCallback_) {
      finalizeCallback_();
    }
  }
  
  /**
   * Get pointer to the buffer data
   * @return Const pointer to the data
   */
  const uint8_t* data() const {
    return static_cast<const uint8_t*>(data_);
  }
  
  /**
   * Get mutable pointer to the buffer data
   * @return Mutable pointer to the data
   */
  uint8_t* data() override {
    return static_cast<uint8_t*>(data_);
  }
  
  /**
   * Get the buffer size
   * @return Size of the buffer in bytes
   */
  size_t size() const override {
    return size_;
  }
  
  // Explicitly non-copyable
  ExternalMutableBuffer(const ExternalMutableBuffer&) = delete;
  ExternalMutableBuffer& operator=(const ExternalMutableBuffer&) = delete;

  // Explicitly movable (members are movable: void*, size_t, std::function)
  ExternalMutableBuffer(ExternalMutableBuffer&&) = default;
  ExternalMutableBuffer& operator=(ExternalMutableBuffer&&) = default;
  
private:
  void* data_;
  size_t size_;
  std::function<void()> finalizeCallback_;
}; 