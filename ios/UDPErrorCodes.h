#pragma once

#import <Foundation/Foundation.h>

// UDPErrorCodes.h – central place for structured error identifiers.
// The string constants are surfaced to JS via TurboModule constants.
// The NSInteger enum values are used for NSError codes natively.

// Domain for NSErrors originating from this module
extern NSString * const UDPErrorDomain;

// Enum for native error codes
typedef NS_ENUM(NSInteger, UDPErrorCode) {
    // Socket lifecycle errors (100-199)
    UDPErrorCodeSocketNotFound = 100,
    UDPErrorCodeAlreadyBound = 101,
    UDPErrorCodeSocketClosed = 102,

    // Parameter validation errors (200-299)
    UDPErrorCodeInvalidArguments = 200,
    UDPErrorCodeInvalidBase64 = 201,
    UDPErrorCodeInvalidAddress = 202,

    // System failures (300-399)
    UDPErrorCodeBindFailed = 300,
    UDPErrorCodeSendFailed = 301,
    UDPErrorCodeReceiveFailed = 302,
    UDPErrorCodeBeginReceiveFailed = 303,
    
    // Buffer / Zero-Copy errors (400-499)
    UDPErrorCodeBufferNotFound = 400,
    UDPErrorCodeBufferCreationFailed = 401,
    UDPErrorCodeBufferAccessFailed = 402,

    // Internal errors (500-599)
    UDPErrorCodeInternalException = 500,
    UDPErrorCodeOperationFailed = 501 // Generic operation failure
};

// String constants for JS export (matching enum values for clarity where possible)
// These strings are exported via TurboModule constants so TypeScript can use a string-union.
// Keep them stable – changing a code is a breaking change for JS.

// Socket lifecycle
static NSString * const UDP_STR_ERR_SOCKET_NOT_FOUND     = @"ERR_SOCKET_NOT_FOUND";
static NSString * const UDP_STR_ERR_ALREADY_BOUND        = @"ERR_ALREADY_BOUND";
static NSString * const UDP_STR_ERR_SOCKET_CLOSED        = @"ERR_SOCKET_CLOSED";

// Parameter validation
static NSString * const UDP_STR_ERR_INVALID_ARGUMENTS    = @"ERR_INVALID_ARGUMENTS";
static NSString * const UDP_STR_ERR_INVALID_BASE64       = @"ERR_INVALID_BASE64";
static NSString * const UDP_STR_ERR_INVALID_ADDRESS      = @"ERR_INVALID_ADDRESS";

// System failures
static NSString * const UDP_STR_ERR_BIND_FAILED          = @"ERR_BIND_FAILED";
static NSString * const UDP_STR_ERR_SEND_FAILED          = @"ERR_SEND_FAILED";
static NSString * const UDP_STR_ERR_RECEIVE_FAILED       = @"ERR_RECEIVE_FAILED";
static NSString * const UDP_STR_ERR_BEGIN_RECEIVE_FAILED = @"ERR_BEGIN_RECEIVE_FAILED";

// Buffer / Zero-Copy errors
static NSString * const UDP_STR_ERR_BUFFER_NOT_FOUND          = @"ERR_BUFFER_NOT_FOUND";
static NSString * const UDP_STR_ERR_BUFFER_CREATION_FAILED    = @"ERR_BUFFER_CREATION_FAILED";
static NSString * const UDP_STR_ERR_BUFFER_ACCESS_FAILED      = @"ERR_BUFFER_ACCESS_FAILED";

// Internal
static NSString * const UDP_STR_ERR_INTERNAL_EXCEPTION   = @"ERR_INTERNAL_EXCEPTION";
static NSString * const UDP_STR_ERR_OPERATION_FAILED     = @"ERR_OPERATION_FAILED"; 