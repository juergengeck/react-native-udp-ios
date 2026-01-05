#import "UDPSocketManager.h"
#import "UDPErrorCodes.h"
#import <GCDAsyncUdpSocket.h>
#import <React/RCTLog.h> // For logging, can be replaced with a more generic logger if needed

// Required system headers for getLocalIPAddresses and setsockopt
#import <ifaddrs.h>
#import <sys/socket.h>
#import <arpa/inet.h>
#import <netdb.h>
#import <unistd.h> // For close() in setsockopt related scenarios if direct FD manipulation occurs.

// Log macros for consistent logging within this class
#ifndef UDP_SM_LOG
#define UDP_SM_LOG(fmt, ...) RCTLogInfo(@"UDPSocketManager: " fmt, ##__VA_ARGS__)
#endif
#ifndef UDP_SM_ERROR
#define UDP_SM_ERROR(fmt, ...) RCTLogError(@"UDPSocketManager: " fmt, ##__VA_ARGS__)
#endif

// Define Buffer Status Constants (internal to this manager)
static NSNumber * const kUDPBufferStatusReleased = @0;
static NSNumber * const kUDPBufferStatusInUseByJS = @1;      // JS has a HostObject pointing to it (for created buffers)
static NSNumber * const kUDPBufferStatusReadyForJSAccess = @2; // Received data, ready for JS to pick up via HostObject
static NSNumber * const kUDPBufferStatusNativeOnly = @3;     // (Potentially for future use if native needs its own buffers)

// Socket Status Constants (internal to this manager)
static NSNumber * const kUDPSocketStatusCreated = @10;
static NSNumber * const kUDPSocketStatusBound = @11;
// static NSNumber * const kUDPSocketStatusListening = @12; // Not explicitly used for clients, GCDAsync handles via beginReceiving
// static NSNumber * const kUDPSocketStatusConnected = @13; // For connected UDP (less common)
static NSNumber * const kUDPSocketStatusClosed = @14;
static NSNumber * const kUDPSocketStatusError = @15;

// Define the error domain
NSString * const UDPErrorDomain = @"com.lama.udpdirect.ErrorDomain";

@implementation UDPSocketManager {
    NSMutableDictionary<NSNumber*, GCDAsyncUdpSocket*> *_asyncSockets;
    NSMutableDictionary<NSNumber*, NSNumber*> *_socketStatus; // Stores kUDPSocketStatus...
    NSMutableDictionary<NSNumber*, NSDictionary*> *_socketInfo; // Stores original options, bound address/port
    NSInteger _nextSocketId;
    long _nextSendTag;

    dispatch_queue_t _delegateQueue; // The queue for GCDAsyncUdpSocket delegate methods & internal sync
}

@synthesize buffers = _buffers; // Synthesize to make readonly property work with internal mutation
@synthesize bufferStatus = _bufferStatus;
@synthesize nextBufferId = _nextBufferId;

- (dispatch_queue_t)delegateQueue {
    return _delegateQueue;
}

- (NSDictionary<NSNumber*, GCDAsyncUdpSocket*> *)asyncSockets {
    return [_asyncSockets copy];  // Return immutable copy for thread safety
}

- (NSDictionary<NSNumber*, NSNumber*> *)socketStatus {
    return [_socketStatus copy];  // Return immutable copy for thread safety
}

- (instancetype)initWithDelegateQueue:(dispatch_queue_t)queue {
    NSLog(@"[UDPSocketManager] INIT: Starting initialization...");
    UDP_SM_LOG(@"Initializing UDPSocketManager...");
    
    self = [super init];
    if (self) {
        NSLog(@"[UDPSocketManager] INIT: super init succeeded");
        _delegateQueue = queue;
        if (!_delegateQueue) {
            // Fallback to a default serial queue if none provided, though caller should provide one.
            _delegateQueue = dispatch_queue_create("com.lama.UDPSocketManagerQueue", DISPATCH_QUEUE_SERIAL);
            UDP_SM_LOG(@"Warning: No delegate queue provided, created a default one.");
        }

        _asyncSockets = [NSMutableDictionary dictionary];
        _socketStatus = [NSMutableDictionary dictionary];
        _socketInfo = [NSMutableDictionary dictionary];
        
        if (!_asyncSockets || !_socketStatus || !_socketInfo) {
            UDP_SM_ERROR(@"Failed to create internal dictionaries");
            return nil;
        }
        
        // Use timestamp-based socket IDs to avoid collisions after reload
        _nextSocketId = (NSInteger)([[NSDate date] timeIntervalSince1970] * 1000) % 1000000;
        _nextSendTag = 0;
        UDP_SM_LOG(@"Initial socket ID counter: %ld", (long)_nextSocketId);

        _buffers = [NSMutableDictionary dictionary];
        _bufferStatus = [NSMutableDictionary dictionary];
        
        if (!_buffers || !_bufferStatus) {
            UDP_SM_ERROR(@"Failed to create buffer dictionaries");
            return nil;
        }
        
        _nextBufferId = 1; // Buffer IDs also start from 1

        UDP_SM_LOG(@"Manager initialized successfully.");
        NSLog(@"[UDPSocketManager] INIT: Initialization completed successfully");
    } else {
        UDP_SM_ERROR(@"Failed to initialize UDPSocketManager - super init failed");
        NSLog(@"[UDPSocketManager] INIT: ERROR - super init failed");
    }
    NSLog(@"[UDPSocketManager] INIT: Returning from constructor");
    return self;
}

#pragma mark - Socket Operations

- (nullable NSNumber *)createSocketWithOptions:(NSDictionary *)options error:(NSError **)error {
    UDP_SM_LOG(@"createSocketWithOptions called with options: %@", options);
    
    // Safety check for manager state
    if (!_delegateQueue) {
        UDP_SM_ERROR(@"createSocketWithOptions: Delegate queue is nil");
        if (error) {
            *error = [NSError errorWithDomain:UDPErrorDomain code:UDPErrorCodeInternalException 
                                     userInfo:@{NSLocalizedDescriptionKey: @"Manager not properly initialized"}];
        }
        return nil;
    }
    
    __block NSNumber *newSocketId = nil;
    __block GCDAsyncUdpSocket *udpSocket = nil;
    __block NSError *creationError = nil;

    UDP_SM_LOG(@"About to enter dispatch_sync block for socket creation");
    
    dispatch_sync(_delegateQueue, ^{
        UDP_SM_LOG(@"Inside dispatch_sync block - creating socket with next ID: %ld", (long)self->_nextSocketId);
        
        newSocketId = @(self->_nextSocketId++);
        UDP_SM_LOG(@"Socket ID assigned: %@", newSocketId);
        
        // Retain self in the block if delegate methods need to access properties of self.
        // However, GCDAsyncUdpSocket init doesn't capture self unless delegate methods do.
        UDP_SM_LOG(@"About to create GCDAsyncUdpSocket with delegate: %p, queue: %p", self, self->_delegateQueue);
        
        udpSocket = [[GCDAsyncUdpSocket alloc] initWithDelegate:self delegateQueue:self->_delegateQueue];
        
        UDP_SM_LOG(@"GCDAsyncUdpSocket creation completed, result: %p", udpSocket);

        if (!udpSocket) {
            UDP_SM_ERROR(@"Failed to initialize GCDAsyncUdpSocket for socket %@", newSocketId);
            NSDictionary *userInfo = @{NSLocalizedDescriptionKey: @"Failed to initialize GCDAsyncUdpSocket."};
            creationError = [NSError errorWithDomain:UDPErrorDomain code:UDPErrorCodeInternalException userInfo:userInfo];
            self->_socketStatus[newSocketId] = kUDPSocketStatusError; // Mark as error even if socket is nil
            // nextSocketId was already incremented, so newSocketId is valid for status tracking
            return; // from dispatch_sync block
        }
        
        UDP_SM_LOG(@"GCDAsyncUdpSocket created successfully for socket %@", newSocketId);

        BOOL useIPv6 = [options[@"ipv6"] boolValue];
        [udpSocket setIPv6Enabled:useIPv6];
        UDP_SM_LOG(@"Socket %@: IPv6 enabled: %@", newSocketId, useIPv6 ? @"YES" : @"NO");

        NSNumber *recvBufferSize = options[@"recvBufferSize"];
        if (recvBufferSize != nil && [recvBufferSize intValue] > 0) {
            int rcvBufSize = [recvBufferSize intValue];
            // GCDAsyncUdpSocket documentation recommends setting these per socket type.
            // For simplicity, setting both. Or, could check `useIPv6`.
            [udpSocket setMaxReceiveIPv4BufferSize:rcvBufSize];
            [udpSocket setMaxReceiveIPv6BufferSize:rcvBufSize];
            UDP_SM_LOG(@"Socket %@: Set receive buffer size to %d", newSocketId, rcvBufSize);
        }
        
        // Handle reuseAddr and reusePort options BEFORE storing the socket
        BOOL reuseAddr = [options[@"reuseAddr"] boolValue];
        BOOL reusePort = [options[@"reusePort"] boolValue];
        
        if (reuseAddr || reusePort) {
            // Get socket file descriptors
            int fd4 = [udpSocket socket4FD];
            int fd6 = [udpSocket socket6FD];
            
            // For SO_REUSEADDR
            if (reuseAddr) {
                int optval = 1;
                if (fd4 != -1) {
                    if (setsockopt(fd4, SOL_SOCKET, SO_REUSEADDR, &optval, sizeof(optval)) < 0) {
                        UDP_SM_ERROR(@"Failed to set SO_REUSEADDR on IPv4 socket: %s", strerror(errno));
                    } else {
                        UDP_SM_LOG(@"Socket %@: SO_REUSEADDR enabled on IPv4", newSocketId);
                    }
                }
                if (fd6 != -1) {
                    if (setsockopt(fd6, SOL_SOCKET, SO_REUSEADDR, &optval, sizeof(optval)) < 0) {
                        UDP_SM_ERROR(@"Failed to set SO_REUSEADDR on IPv6 socket: %s", strerror(errno));
                    } else {
                        UDP_SM_LOG(@"Socket %@: SO_REUSEADDR enabled on IPv6", newSocketId);
                    }
                }
            }
            
            // For SO_REUSEPORT - when reusePort is true, set BOTH SO_REUSEADDR and SO_REUSEPORT
            if (reusePort) {
                // Attempt to use GCDAsyncUdpSocket helper so the option is applied to *all* future FDs
                // Some versions of CocoaAsyncSocket may not expose the `enableReusePort:` selector. To avoid
                // a compile-time error we call it dynamically if it exists. If it is not available we simply
                // rely on the `setsockopt` fallback below which already enables `SO_REUSEPORT`.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
                if ([udpSocket respondsToSelector:@selector(enableReusePort:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                    id result = [udpSocket performSelector:@selector(enableReusePort:) withObject:@(YES)];
#pragma clang diagnostic pop
                    // If the helper returned a BOOL wrapped in NSNumber we can log based on its value, otherwise assume success.
                    BOOL helperSuccess = YES;
                    if ([result isKindOfClass:[NSNumber class]]) {
                        helperSuccess = [(NSNumber *)result boolValue];
                    }
                    if (!helperSuccess) {
                        UDP_SM_ERROR(@"Failed to enable SO_REUSEPORT via GCDAsyncUdpSocket helper (dynamic call)");
                    } else {
                        UDP_SM_LOG(@"Socket %@: enableReusePort=YES (GCDAsyncUdpSocket via dynamic selector)", newSocketId);
                    }
                } else {
                    UDP_SM_LOG(@"GCDAsyncUdpSocket does not implement enableReusePort:. Falling back to manual setsockopt.");
                }
#pragma clang diagnostic pop

                int optval = 1;
                if (fd4 != -1) {
                    // First ensure SO_REUSEADDR is set (if not already set above)
                    if (!reuseAddr) {
                        if (setsockopt(fd4, SOL_SOCKET, SO_REUSEADDR, &optval, sizeof(optval)) < 0) {
                            UDP_SM_ERROR(@"Failed to set SO_REUSEADDR on IPv4 socket: %s", strerror(errno));
                        } else {
                            UDP_SM_LOG(@"Socket %@: SO_REUSEADDR enabled on IPv4 (for reusePort)", newSocketId);
                        }
                    }
                    // Then set SO_REUSEPORT
                    if (setsockopt(fd4, SOL_SOCKET, SO_REUSEPORT, &optval, sizeof(optval)) < 0) {
                        UDP_SM_ERROR(@"Failed to set SO_REUSEPORT on IPv4 socket: %s", strerror(errno));
                    } else {
                        UDP_SM_LOG(@"Socket %@: SO_REUSEPORT enabled on IPv4", newSocketId);
                    }
                }
                if (fd6 != -1) {
                    // First ensure SO_REUSEADDR is set (if not already set above)
                    if (!reuseAddr) {
                        if (setsockopt(fd6, SOL_SOCKET, SO_REUSEADDR, &optval, sizeof(optval)) < 0) {
                            UDP_SM_ERROR(@"Failed to set SO_REUSEADDR on IPv6 socket: %s", strerror(errno));
                        } else {
                            UDP_SM_LOG(@"Socket %@: SO_REUSEADDR enabled on IPv6 (for reusePort)", newSocketId);
                        }
                    }
                    // Then set SO_REUSEPORT
                    if (setsockopt(fd6, SOL_SOCKET, SO_REUSEPORT, &optval, sizeof(optval)) < 0) {
                        UDP_SM_ERROR(@"Failed to set SO_REUSEPORT on IPv6 socket: %s", strerror(errno));
                    } else {
                        UDP_SM_LOG(@"Socket %@: SO_REUSEPORT enabled on IPv6", newSocketId);
                    }
                }
            }
        }
        
        self->_asyncSockets[newSocketId] = udpSocket;
        self->_socketStatus[newSocketId] = kUDPSocketStatusCreated;
        NSMutableDictionary *info = [NSMutableDictionary dictionary];
        info[@"options"] = options ?: @{};
        self->_socketInfo[newSocketId] = info;
    });

    if (creationError) {
        if (error) {
            *error = creationError;
        }
        return nil;
    }
    UDP_SM_LOG(@"Created socket %@ successfully.", newSocketId);
    return newSocketId;
}

- (BOOL)bindSocket:(NSNumber *)socketId toPort:(uint16_t)port address:(nullable NSString *)address error:(NSError **)error {
    __block BOOL success = NO;
    __block NSError *bindError = nil;

    dispatch_sync(_delegateQueue, ^{
        GCDAsyncUdpSocket *udpSocket = self->_asyncSockets[socketId];
        if (!udpSocket) {
            NSDictionary *userInfo = @{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Socket %@ not found for bind.", socketId]};
            bindError = [NSError errorWithDomain:UDPErrorDomain code:UDPErrorCodeSocketNotFound userInfo:userInfo];
            return;
        }

        BOOL ipv6Enabled = [udpSocket isIPv6Enabled];
        NSString *interfaceToBind = address;

        if (interfaceToBind) {
            if (([interfaceToBind isEqualToString:@"0.0.0.0"] && !ipv6Enabled) || ([interfaceToBind isEqualToString:@"::"] && ipv6Enabled)) {
                UDP_SM_LOG(@"Binding socket %@ to any interface ('%@'), setting interface to nil for GCDAsyncUdpSocket", socketId, interfaceToBind);
                interfaceToBind = nil;
            }
        } else {
             UDP_SM_LOG(@"Binding socket %@ with nil address, defaulting to any interface.", socketId);
        }

        NSError *nativeError = nil;
        if (![udpSocket bindToPort:port interface:interfaceToBind error:&nativeError]) {
            NSString *errMsg = [NSString stringWithFormat:@"Failed to bind socket %@ to %@:%u. Error: %@", socketId, address ?: (ipv6Enabled ? @"::" : @"0.0.0.0"), port, nativeError.localizedDescription];
            NSDictionary *userInfo = @{
                NSLocalizedDescriptionKey: errMsg,
                @"nativeErrorCode": @(nativeError.code),
                @"nativeErrorDomain": nativeError.domain ?: @"UnknownDomain"
            };
            bindError = [NSError errorWithDomain:UDPErrorDomain code:UDPErrorCodeBindFailed userInfo:userInfo];
            self->_socketStatus[socketId] = kUDPSocketStatusError;
            return;
        }

        self->_socketStatus[socketId] = kUDPSocketStatusBound;
        NSMutableDictionary *info = [self->_socketInfo[socketId] mutableCopy] ?: [NSMutableDictionary dictionary];
        info[@"boundAddress"] = [udpSocket localHost] ?: (interfaceToBind ?: (ipv6Enabled ? @"::" : @"0.0.0.0"));
        info[@"boundPort"] = @([udpSocket localPort]);
        self->_socketInfo[socketId] = info;
        UDP_SM_LOG(@"Socket %@ bound to %@:%hu (Local: %@:%hu)", socketId, interfaceToBind ?: (ipv6Enabled ? @"::" : @"0.0.0.0"), port, [udpSocket localHost_IPv4] ?: ([udpSocket localHost_IPv6] ?: @"unknown"), [udpSocket localPort]);

        // Only start receiving if callbacks are properly set up to prevent crashes
        if (self.onDataReceived) {
            NSError *receiveErr = nil;
            if (![udpSocket beginReceiving:&receiveErr]) {
                UDP_SM_ERROR(@"Socket %@: Failed to beginReceiving after bind: %@", socketId, receiveErr.localizedDescription);
                self->_socketStatus[socketId] = kUDPSocketStatusError;
                // This is a non-fatal error for the bind operation itself, but owner should be notified.
                // The C++ layer can decide if this is critical. For now, bind itself is "success".
            } else {
                UDP_SM_LOG(@"Socket %@ now listening for datagrams.", socketId);
            }
        } else {
            UDP_SM_LOG(@"Socket %@ bound but not yet receiving - waiting for data event handler setup", socketId);
        }
        
        NSDictionary *origOptions = self->_socketInfo[socketId][@"options"];
        if (origOptions && [origOptions[@"broadcast"] boolValue]) {
            NSError *broadcastError = nil;
            if (![udpSocket enableBroadcast:YES error:&broadcastError]) {
                 UDP_SM_ERROR(@"Socket %@: Failed to enable broadcast after bind: %@", socketId, broadcastError.localizedDescription);
            } else {
                UDP_SM_LOG(@"Socket %@ broadcast flag enabled after bind.", socketId);
            }
        }
        success = YES;
    });

    if (!success && error) {
        *error = bindError;
    }
    return success;
}

- (void)sendData:(NSData *)data onSocket:(NSNumber *)socketId toHost:(NSString *)host port:(uint16_t)port tag:(long)tag {
    // Perform a quick lookup synchronously so we don't capture a nil socket
    GCDAsyncUdpSocket *udpSocket = _asyncSockets[socketId];
    if (!udpSocket) {
        UDP_SM_ERROR(@"Socket %@ not found for sending.", socketId);
        if (self.onSendFailure) {
            NSDictionary *userInfo = @{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Socket %@ not found for sending.", socketId]};
            NSError *notFoundError = [NSError errorWithDomain:UDPErrorDomain code:UDPErrorCodeSocketNotFound userInfo:userInfo];
            self.onSendFailure(socketId, tag, notFoundError);
        }
        return;
    }

    // Use async queue for the real send to preserve ordering with delegate callbacks
    dispatch_async(_delegateQueue, ^{
        // Ensure broadcast is enabled when sending to broadcast addresses
        if ([host isEqualToString:@"255.255.255.255"] || [host hasSuffix:@".255"]) {
            NSError *broadcastError = nil;
            if (![udpSocket enableBroadcast:YES error:&broadcastError]) {
                UDP_SM_ERROR(@"Socket %@: Failed to enable broadcast for send: %@", socketId, broadcastError.localizedDescription);
                if (self.onSendFailure) {
                    self.onSendFailure(socketId, tag, broadcastError);
                }
                return;
            }
            UDP_SM_LOG(@"Socket %@: Enabled broadcast for send to %@", socketId, host);
        }

        UDP_SM_LOG(@"Socket %@: Sending %lu bytes to %@:%u with tag %ld", socketId, (unsigned long)data.length, host, port, tag);
        [udpSocket sendData:data toHost:host port:port withTimeout:-1 tag:tag];
    });
}

- (void)sendDataFromBuffer:(NSNumber *)bufferId offset:(NSUInteger)offset length:(NSUInteger)length onSocket:(NSNumber *)socketId toHost:(NSString *)host port:(uint16_t)port tag:(long)tag {
     dispatch_async(_delegateQueue, ^{
        GCDAsyncUdpSocket *udpSocket = self->_asyncSockets[socketId];
        NSMutableData *buffer = self->_buffers[bufferId]; // Assumes buffers are managed on _delegateQueue

        if (!udpSocket) {
            UDP_SM_ERROR(@"Socket %@ not found for sending from buffer.", socketId);
            if (self.onSendFailure) {
                NSDictionary *userInfo = @{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Socket %@ not found for sending from buffer.", socketId]};
                self.onSendFailure(socketId, tag, [NSError errorWithDomain:UDPErrorDomain code:UDPErrorCodeSocketNotFound userInfo:userInfo]);
            }
            return;
        }
        if (!buffer) {
            UDP_SM_ERROR(@"Buffer %@ not found for sending from buffer.", bufferId);
             if (self.onSendFailure) {
                NSDictionary *userInfo = @{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Buffer %@ not found for sending.", bufferId]};
                self.onSendFailure(socketId, tag, [NSError errorWithDomain:UDPErrorDomain code:UDPErrorCodeInvalidArguments userInfo:userInfo]);
            }
            return;
        }
        if (offset + length > buffer.length) {
            UDP_SM_ERROR(@"Offset + length exceeds buffer %@ size.", bufferId);
             if (self.onSendFailure) {
                NSDictionary *userInfo = @{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Offset + length exceeds buffer %@ size.", bufferId]};
                self.onSendFailure(socketId, tag, [NSError errorWithDomain:UDPErrorDomain code:UDPErrorCodeInvalidArguments userInfo:userInfo]);
            }
            return;
        }

        const void *dataPtr = (const char *)buffer.bytes + offset;
        NSData *dataToSend = [NSData dataWithBytesNoCopy:(void*)dataPtr length:length freeWhenDone:NO];
        
        UDP_SM_LOG(@"Socket %@: Sending %lu bytes from buffer %@ (offset %lu) to %@:%u with tag %ld", socketId, (unsigned long)length, bufferId, (unsigned long)offset, host, port, tag);
        [udpSocket sendData:dataToSend toHost:host port:port withTimeout:-1 tag:tag];
    });
}

- (void)closeSocket:(NSNumber *)socketId {
    dispatch_async(_delegateQueue, ^{
        GCDAsyncUdpSocket *udpSocket = self->_asyncSockets[socketId];
        if (udpSocket) {
            UDP_SM_LOG(@"Closing socket %@", socketId);
            [udpSocket close]; // Delegate method udpSocketDidClose will handle cleanup
        } else {
            UDP_SM_LOG(@"Socket %@ not found for closing, or already closed.", socketId);
        }
    });
}

- (void)closeAllSockets {
    dispatch_async(_delegateQueue, ^{
        UDP_SM_LOG(@"Closing all sockets.");
        NSArray *allSocketIds = [self->_asyncSockets allKeys];
        for (NSNumber *sockId in allSocketIds) {
            GCDAsyncUdpSocket *udpSocket = self->_asyncSockets[sockId];
            if (udpSocket && ![udpSocket isClosed]) {
                [udpSocket close];
            }
        }
        // Actual removal from dictionaries will happen in udpSocketDidClose
    });
}

- (void)closeAllSocketsSynchronously {
    // IMPORTANT: This method must be called on the delegate queue for thread safety
    // It performs synchronous cleanup to prevent race conditions during app reload
    // Note: dispatch_get_current_queue() is deprecated, so we rely on caller to ensure proper queue
    
    UDP_SM_LOG(@"Closing all sockets synchronously for app reload.");
    NSArray *allSocketIds = [_asyncSockets allKeys];
    
    for (NSNumber *sockId in allSocketIds) {
        GCDAsyncUdpSocket *udpSocket = _asyncSockets[sockId];
        if (udpSocket && ![udpSocket isClosed]) {
            UDP_SM_LOG(@"Synchronously closing socket %@", sockId);
            
            // Close the socket and immediately clean up
            [udpSocket close];
            
            // Manually trigger cleanup that would normally happen in udpSocketDidClose:withError:
            // This ensures immediate cleanup without waiting for async delegate callbacks
            [_asyncSockets removeObjectForKey:sockId];
            [_socketInfo removeObjectForKey:sockId];
            _socketStatus[sockId] = kUDPSocketStatusClosed;
            
            UDP_SM_LOG(@"Socket %@ closed and cleaned up synchronously", sockId);
        }
    }

    // Reset socket counter to prevent ID collision after reload
    // Use a timestamp-based counter to avoid conflicts
    _nextSocketId = 1000 + (NSInteger)([[NSDate date] timeIntervalSince1970] * 1000) % 100000;
    UDP_SM_LOG(@"Reset socket ID counter to %ld after cleanup", (long)_nextSocketId);

    UDP_SM_LOG(@"All sockets closed synchronously. Remaining sockets: %lu", (unsigned long)[_asyncSockets count]);
}

- (void)startReceivingOnBoundSockets {
    dispatch_async(_delegateQueue, ^{
        UDP_SM_LOG(@"Starting to receive on bound sockets...");
        for (NSNumber *socketId in [self->_socketStatus allKeys]) {
            NSNumber *status = self->_socketStatus[socketId];
            if ([status isEqualToNumber:kUDPSocketStatusBound]) {
                GCDAsyncUdpSocket *udpSocket = self->_asyncSockets[socketId];
                if (udpSocket) {
                    NSError *receiveErr = nil;
                    if ([udpSocket beginReceiving:&receiveErr]) {
                        UDP_SM_LOG(@"Started receiving on bound socket %@", socketId);
                    } else {
                        UDP_SM_ERROR(@"Failed to start receiving on socket %@: %@", socketId, receiveErr.localizedDescription);
                        self->_socketStatus[socketId] = kUDPSocketStatusError;
                    }
                }
            }
        }
    });
}

#pragma mark - Socket Options Implementations

- (BOOL)setBroadcast:(NSNumber *)socketId enable:(BOOL)enable error:(NSError **)error {
    __block BOOL success = NO;
    __block NSError *opError = nil;
    dispatch_sync(_delegateQueue, ^{
        GCDAsyncUdpSocket *udpSocket = self->_asyncSockets[socketId];
        if (!udpSocket) {
            opError = [NSError errorWithDomain:UDPErrorDomain code:UDPErrorCodeSocketNotFound userInfo:@{NSLocalizedDescriptionKey:@"Socket not found"}]; return;
        }
        NSError *nativeError = nil;
        if (![udpSocket enableBroadcast:enable error:&nativeError]) {
            opError = [NSError errorWithDomain:UDPErrorDomain code:UDPErrorCodeInternalException userInfo:@{NSLocalizedDescriptionKey: nativeError.localizedDescription, @"nativeError": nativeError}];
        } else {
            UDP_SM_LOG(@"Socket %@ broadcast set to %@", socketId, enable ? @"YES" : @"NO");
            success = YES;
        }
    });
    if (error && opError) *error = opError;
    return success;
}

- (BOOL)setTTL:(NSNumber *)socketId ttl:(int)ttl error:(NSError **)error {
    __block BOOL success = NO;
    __block NSError *opError = nil;
    dispatch_sync(_delegateQueue, ^{
        GCDAsyncUdpSocket *udpSocket = self->_asyncSockets[socketId];
        if (!udpSocket) { opError = [NSError errorWithDomain:UDPErrorDomain code:UDPErrorCodeSocketNotFound userInfo:@{NSLocalizedDescriptionKey:@"Socket not found"}]; return; }

        int fd4 = [udpSocket socket4FD];
        int fd6 = [udpSocket socket6FD];
        BOOL opDone = NO;

        if (fd4 != -1) {
            if (setsockopt(fd4, IPPROTO_IP, IP_TTL, &ttl, sizeof(ttl)) == 0) { opDone = YES; }
            else { opError = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithUTF8String:strerror(errno)]}]; }
        }
        if (fd6 != -1) { // IPV6_UNICAST_HOPS for IPv6
            if (setsockopt(fd6, IPPROTO_IPV6, IPV6_UNICAST_HOPS, &ttl, sizeof(ttl)) == 0) { opDone = YES; }
            else if (!opError) { opError = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithUTF8String:strerror(errno)]}]; }
        }
        if (!opDone && (fd4 == -1 && fd6 == -1)) { // No valid FD
             opError = [NSError errorWithDomain:UDPErrorDomain code:UDPErrorCodeSocketNotFound userInfo:@{NSLocalizedDescriptionKey:@"Socket FDs not available for TTL."}];
        } else if (opDone) {
            UDP_SM_LOG(@"Socket %@ TTL set to %d", socketId, ttl);
            success = YES; // If at least one setsockopt succeeded without prior error
        }
    });
    if (error && opError) *error = opError;
    return success;
}

- (BOOL)setMulticastTTL:(NSNumber *)socketId ttl:(int)ttl error:(NSError **)error {
    __block BOOL success = NO;
    __block NSError *opError = nil;
    dispatch_sync(_delegateQueue, ^{
        GCDAsyncUdpSocket *udpSocket = self->_asyncSockets[socketId];
        if (!udpSocket) { opError = [NSError errorWithDomain:UDPErrorDomain code:UDPErrorCodeSocketNotFound userInfo:@{NSLocalizedDescriptionKey:@"Socket not found"}]; return; }

        int fd4 = [udpSocket socket4FD];
        int fd6 = [udpSocket socket6FD];
        BOOL opDone = NO;

        if (fd4 != -1) { // IP_MULTICAST_TTL for IPv4
            if (setsockopt(fd4, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, sizeof(ttl)) == 0) { opDone = YES; }
            else { opError = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithUTF8String:strerror(errno)]}];}
        }
        if (fd6 != -1) { // IPV6_MULTICAST_HOPS for IPv6 multicast TTL
            if (setsockopt(fd6, IPPROTO_IPV6, IPV6_MULTICAST_HOPS, &ttl, sizeof(ttl)) == 0) { opDone = YES; }
            else if (!opError) { opError = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithUTF8String:strerror(errno)]}]; }
        }
         if (!opDone && (fd4 == -1 && fd6 == -1)) {
             opError = [NSError errorWithDomain:UDPErrorDomain code:UDPErrorCodeSocketNotFound userInfo:@{NSLocalizedDescriptionKey:@"Socket FDs not available for Multicast TTL."}];
        } else if (opDone) {
            UDP_SM_LOG(@"Socket %@ Multicast TTL set to %d", socketId, ttl);
            success = YES;
        }
    });
    if (error && opError) *error = opError;
    return success;
}

- (BOOL)setMulticastLoopback:(NSNumber *)socketId flag:(BOOL)flag error:(NSError **)error {
    __block BOOL success = NO;
    __block NSError *opError = nil;
    dispatch_sync(_delegateQueue, ^{
        GCDAsyncUdpSocket *udpSocket = self->_asyncSockets[socketId];
        if (!udpSocket) { opError = [NSError errorWithDomain:UDPErrorDomain code:UDPErrorCodeSocketNotFound userInfo:@{NSLocalizedDescriptionKey:@"Socket not found"}]; return; }

        // For setsockopt, loopback is typically u_char (0 or 1) or int
        unsigned char loopbackFlag = flag ? 1 : 0;
        int fd4 = [udpSocket socket4FD];
        int fd6 = [udpSocket socket6FD];
        BOOL opDone = NO;

        if (fd4 != -1) { // IP_MULTICAST_LOOP for IPv4
            if (setsockopt(fd4, IPPROTO_IP, IP_MULTICAST_LOOP, &loopbackFlag, sizeof(loopbackFlag)) == 0) { opDone = YES; }
            else { opError = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithUTF8String:strerror(errno)]}]; }
        }
        if (fd6 != -1) { // IPV6_MULTICAST_LOOP for IPv6
            if (setsockopt(fd6, IPPROTO_IPV6, IPV6_MULTICAST_LOOP, &loopbackFlag, sizeof(loopbackFlag)) == 0) { opDone = YES; }
            else if (!opError) { opError = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithUTF8String:strerror(errno)]}];}
        }
        if (!opDone && (fd4 == -1 && fd6 == -1)) {
            opError = [NSError errorWithDomain:UDPErrorDomain code:UDPErrorCodeSocketNotFound userInfo:@{NSLocalizedDescriptionKey:@"Socket FDs not available for Multicast Loopback."}];
        } else if (opDone) {
            UDP_SM_LOG(@"Socket %@ Multicast Loopback set to %@", socketId, flag ? @"YES" : @"NO");
            success = YES;
        }
    });
    if (error && opError) *error = opError;
    return success;
}

- (BOOL)joinMulticastGroup:(NSNumber *)socketId address:(NSString *)address error:(NSError **)error {
    __block BOOL success = NO;
    __block NSError *opError = nil;
    dispatch_sync(_delegateQueue, ^{
        GCDAsyncUdpSocket *udpSocket = self->_asyncSockets[socketId];
        if (!udpSocket) { opError = [NSError errorWithDomain:UDPErrorDomain code:UDPErrorCodeSocketNotFound userInfo:@{NSLocalizedDescriptionKey:@"Socket not found"}]; return; }
        NSError *nativeError = nil;
        if (![udpSocket joinMulticastGroup:address error:&nativeError]) {
            opError = [NSError errorWithDomain:UDPErrorDomain code:UDPErrorCodeInternalException userInfo:@{NSLocalizedDescriptionKey: nativeError.localizedDescription, @"nativeError": nativeError}];
        } else {
             UDP_SM_LOG(@"Socket %@ joined multicast group %@", socketId, address);
            success = YES;
        }
    });
    if (error && opError) *error = opError;
    return success;
}

- (BOOL)leaveMulticastGroup:(NSNumber *)socketId address:(NSString *)address error:(NSError **)error {
    __block BOOL success = NO;
    __block NSError *opError = nil;
    dispatch_sync(_delegateQueue, ^{
        GCDAsyncUdpSocket *udpSocket = self->_asyncSockets[socketId];
        if (!udpSocket) { opError = [NSError errorWithDomain:UDPErrorDomain code:UDPErrorCodeSocketNotFound userInfo:@{NSLocalizedDescriptionKey:@"Socket not found"}]; return; }
        NSError *nativeError = nil;
        if (![udpSocket leaveMulticastGroup:address error:&nativeError]) {
            opError = [NSError errorWithDomain:UDPErrorDomain code:UDPErrorCodeInternalException userInfo:@{NSLocalizedDescriptionKey: nativeError.localizedDescription, @"nativeError": nativeError}];
        } else {
            UDP_SM_LOG(@"Socket %@ left multicast group %@", socketId, address);
            success = YES;
        }
    });
    if (error && opError) *error = opError;
    return success;
}

#pragma mark - Utility Implementations

- (nullable NSDictionary *)getSocketAddress:(NSNumber *)socketId {
    __block NSDictionary *addressInfo = nil;
    dispatch_sync(_delegateQueue, ^{
        GCDAsyncUdpSocket *udpSocket = self->_asyncSockets[socketId];
        if (udpSocket) {
            NSString *localHost = [udpSocket localHost_IPv4] ?: [udpSocket localHost_IPv6];
            uint16_t localPort = [udpSocket localPort];
            if (localHost) {
                addressInfo = @{
                    @"address": localHost,
                    @"port": @(localPort),
                    @"family": ([udpSocket isIPv6] ? @"IPv6" : @"IPv4")
                };
            } else { // Might be created but not bound
                 NSDictionary *sInfo = self->_socketInfo[socketId];
                 if (sInfo && sInfo[@"boundAddress"] && sInfo[@"boundPort"]) {
                     addressInfo = @{ @"address": sInfo[@"boundAddress"], @"port": sInfo[@"boundPort"], @"family": ([udpSocket isIPv6] ? @"IPv6" : @"IPv4")};
                 } else {
                     UDP_SM_LOG(@"Socket %@ found but not bound or local address unavailable.", socketId);
                 }
            }
        } else {
            UDP_SM_ERROR(@"Socket %@ not found for getSocketAddress.", socketId);
        }
    });
    return addressInfo;
}

- (NSArray<NSString *> *)getLocalIPAddresses {
    NSMutableArray *ipAddresses = [NSMutableArray array];
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    int success = getifaddrs(&interfaces);
    if (success == 0) {
        temp_addr = interfaces;
        while(temp_addr != NULL) {
            if(temp_addr->ifa_addr->sa_family == AF_INET) {
                NSString *address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
                if (address && ![address isEqualToString:@"0.0.0.0"] && ![address isEqualToString:@"127.0.0.1"]) {
                    [ipAddresses addObject:address];
                }
            } else if (temp_addr->ifa_addr->sa_family == AF_INET6) {
                char addrBuf[INET6_ADDRSTRLEN];
                const char* str = inet_ntop(AF_INET6, &(((struct sockaddr_in6 *)temp_addr->ifa_addr)->sin6_addr), addrBuf, INET6_ADDRSTRLEN);
                if (str) {
                    NSString *address = [NSString stringWithUTF8String:str];
                    if (address && ![address isEqualToString:@"::1"] && !([address rangeOfString:@"%"].location != NSNotFound) ) {
                        [ipAddresses addObject:address];
                    }
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
    }
    freeifaddrs(interfaces);
    UDP_SM_LOG(@"Found IP Addresses: %@", ipAddresses);
    return [ipAddresses copy]; // Return immutable copy
}

#pragma mark - Buffer Management

- (nullable NSNumber *)createManagedBufferOfSize:(NSUInteger)size {
    if (size == 0) return nil;
    __block NSNumber *newBufferId = nil;
    dispatch_sync(_delegateQueue, ^{
        newBufferId = @(self->_nextBufferId++);
        NSMutableData *buffer = [NSMutableData dataWithLength:size];
        if (buffer) {
            self->_buffers[newBufferId] = buffer;
            self->_bufferStatus[newBufferId] = kUDPBufferStatusInUseByJS; // Assume created for JS use initially
            UDP_SM_LOG(@"Allocated new managed buffer %@ with size %lu", newBufferId, (unsigned long)size);
        } else {
            UDP_SM_ERROR(@"Failed to allocate NSMutableData of size %lu", (unsigned long)size);
            // Roll back nextBufferId if allocation failed and newBufferId was already assigned
            // This is a bit tricky with dispatch_sync if newBufferId is only set on success.
            // Let's assume if buffer is nil, we don't store the ID.
            newBufferId = nil; // Mark as failed
        }
    });
    return newBufferId;
}

// This is called when JS explicitly releases its "view" or "handle" to a buffer *it created*.
// For *received* data buffers, jsDidReleaseBufferId is the JSI finalizer path.
- (void)releaseManagedBuffer:(NSNumber *)bufferIdFromJS {
    if (!bufferIdFromJS) return;
    dispatch_async(_delegateQueue, ^{
        if (self->_buffers[bufferIdFromJS]) {
            // This buffer was created by JS request (e.g., createSharedArrayBuffer)
            // JS is now saying it's done with it. We can remove it.
            [self->_buffers removeObjectForKey:bufferIdFromJS];
            [self->_bufferStatus removeObjectForKey:bufferIdFromJS];
            UDP_SM_LOG(@"Managed buffer %@ released and removed by JS request.", bufferIdFromJS);
        } else {
             UDP_SM_LOG(@"Managed buffer %@ not found or already released by JS request.", bufferIdFromJS);
        }
    });
}


- (nullable NSMutableData *)getModifiableBufferWithId:(NSNumber *)bufferId {
    if (!bufferId) return nil;
    __block NSMutableData *buffer = nil;
    dispatch_sync(_delegateQueue, ^{
        buffer = self->_buffers[bufferId];
        if (!buffer) {
            UDP_SM_ERROR(@"getModifiableBufferWithId: No buffer found for ID %@", bufferId);
        }
    });
    return buffer;
}

// Called by C++ when a HostObject for a *received* buffer is given to JS
- (void)jsDidAcquireReceivedBuffer:(NSNumber *)bufferId {
  if (!bufferId) return;
  dispatch_async(_delegateQueue, ^{
    NSNumber *currentStatus = self->_bufferStatus[bufferId];
    if (self->_buffers[bufferId] && currentStatus && [currentStatus isEqualToNumber:kUDPBufferStatusReadyForJSAccess]) {
      self->_bufferStatus[bufferId] = kUDPBufferStatusInUseByJS;
      UDP_SM_LOG(@"Buffer %@ transitioned to InUseByJS (from ReadyForJSAccess)", bufferId);
    } else {
      UDP_SM_ERROR(@"jsDidAcquireReceivedBuffer: Buffer %@ not found or not in ReadyForJSAccess state. Current: %@", bufferId, currentStatus);
    }
  });
}

// Called by C++ (SharedBufferHostObject finalizer) when JS no longer holds a reference to a *received* buffer.
- (void)jsDidReleaseBufferId:(NSNumber *)bufferId {
  if (!bufferId) return;
  dispatch_async(_delegateQueue, ^{
    UDP_SM_LOG(@"jsDidReleaseBufferId called for received buffer: %@", bufferId);
    if (self->_buffers[bufferId]) {
      NSNumber *currentStatus = self->_bufferStatus[bufferId];
      // Only remove if it was in use by JS (meaning it was a received buffer that JS acquired)
      if ([currentStatus isEqualToNumber:kUDPBufferStatusInUseByJS]) {
        [self->_buffers removeObjectForKey:bufferId];
        [self->_bufferStatus removeObjectForKey:bufferId]; // Or set to kUDPBufferStatusReleased
        UDP_SM_LOG(@"Received Buffer %@ (was InUseByJS) released by JSI finalizer and removed.", bufferId);
      } else {
         UDP_SM_LOG(@"Received Buffer %@ not InUseByJS (status: %@), not removed by JSI finalizer. Might be already released or an issue.", bufferId, currentStatus);
      }
    } else {
      UDP_SM_LOG(@"Received Buffer %@ for JSI finalizer already removed or never existed.", bufferId);
    }
  });
}


#pragma mark - GCDAsyncUdpSocketDelegate Methods

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didReceiveData:(NSData *)data
      fromAddress:(NSData *)address
withFilterContext:(nullable id)filterContext {

    // Safety checks to prevent crashes
    if (!sock || !data || !address) {
        UDP_SM_ERROR(@"didReceiveData called with null parameters");
        return;
    }

    NSString *senderHost = [GCDAsyncUdpSocket hostFromAddress:address];
    uint16_t senderPort = [GCDAsyncUdpSocket portFromAddress:address];

    __block NSNumber *socketId = nil;
    __block NSNumber *newBufferId = nil;

    // Find socketId and create buffer within the delegate queue
    // The delegate methods are already called on _delegateQueue.
    // No need for another dispatch_sync here unless explicitly managing cross-block state.

    // Safety check for _asyncSockets dictionary
    if (!self->_asyncSockets) {
        UDP_SM_ERROR(@"_asyncSockets dictionary is null during didReceiveData");
        return;
    }

    for (NSNumber *sId in self->_asyncSockets) {
        if (self->_asyncSockets[sId] == sock) {
            socketId = sId;
            break;
        }
    }

    if (!socketId) {
        UDP_SM_ERROR(@"Received data on a socket not tracked by UDPSocketManager.");
        return;
    }

    NSMutableData *mutableData = [data mutableCopy]; // Ensure data is mutable for storage
    newBufferId = @(self->_nextBufferId++);
    self->_buffers[newBufferId] = mutableData;
    self->_bufferStatus[newBufferId] = kUDPBufferStatusReadyForJSAccess; // Mark as ready for JS
    UDP_SM_LOG(@"Stored received data into buffer %@ (size: %lu) for socket %@. Status: ReadyForJSAccess", newBufferId, (unsigned long)mutableData.length, socketId);
    
    if (self.onDataReceived) {
        self.onDataReceived(socketId, mutableData, senderHost, senderPort, newBufferId);
    } else {
        UDP_SM_LOG(@"onDataReceived callback not set, data for socket %@ ignored.", socketId);
    }
}

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didNotSendDataWithTag:(long)tag dueToError:(NSError *)error {
    __block NSNumber *socketId = nil;
    // Find socketId for this sock
    for (NSNumber *sId in self->_asyncSockets) {
        if (self->_asyncSockets[sId] == sock) {
            socketId = sId;
            break;
        }
    }
    UDP_SM_ERROR(@"Socket %@ failed to send data with tag %ld. Error: %@", socketId ?: @"<unknown>", tag, error.localizedDescription);
    if (self.onSendFailure) {
        self.onSendFailure(socketId, tag, error);
    }
}

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didSendDataWithTag:(long)tag {
    __block NSNumber *socketId = nil;
    // Find socketId for this sock
     for (NSNumber *sId in self->_asyncSockets) {
        if (self->_asyncSockets[sId] == sock) {
            socketId = sId;
            break;
        }
    }
    UDP_SM_LOG(@"Socket %@ successfully sent data with tag %ld", socketId ?: @"<unknown>", tag);
    if (self.onSendSuccess) {
        self.onSendSuccess(socketId, tag);
    }
}

- (void)udpSocketDidClose:(GCDAsyncUdpSocket *)sock withError:(NSError *)error {
    __block NSNumber *sockId = nil;
    // Find the socket ID and remove it
    // This is already on _delegateQueue
    for (NSNumber *currentId in [self->_asyncSockets allKeys]) { // Iterate on keys copy
        if (self->_asyncSockets[currentId] == sock) {
            sockId = currentId;
            break;
        }
    }

    if (!sockId) {
        UDP_SM_ERROR(@"udpSocketDidClose called for an unknown socket instance.");
        return;
    }

    UDP_SM_LOG(@"Socket %@ did close. Error: %@", sockId, (error ? error.localizedDescription : @"No error"));
    [self->_asyncSockets removeObjectForKey:sockId];
    [self->_socketInfo removeObjectForKey:sockId];
    
    if (error) {
        self->_socketStatus[sockId] = kUDPSocketStatusError;
    } else {
        self->_socketStatus[sockId] = kUDPSocketStatusClosed;
    }
    
    if (self.onSocketClosed) {
        self.onSocketClosed(sockId, error);
    }
}

#pragma mark - Diagnostics

- (nullable NSDictionary *)getDiagnostics {
    __block NSMutableDictionary *diagnostics = [NSMutableDictionary dictionary];
    dispatch_sync(_delegateQueue, ^{
        // Buffer information
        NSMutableArray *bufferDetails = [NSMutableArray array];
        for (NSNumber *bufferId in self->_buffers) {
            NSMutableData *buffer = self->_buffers[bufferId];
            NSNumber *statusNum = self->_bufferStatus[bufferId];
            NSString *statusStr = @"unknown";
            if ([statusNum isEqualToNumber:kUDPBufferStatusInUseByJS]) statusStr = @"inUseByJS";
            else if ([statusNum isEqualToNumber:kUDPBufferStatusReadyForJSAccess]) statusStr = @"readyForJSAccess";
            else if ([statusNum isEqualToNumber:kUDPBufferStatusReleased]) statusStr = @"released";
            
            [bufferDetails addObject:@{
                @"id": bufferId,
                @"size": @(buffer.length),
                @"status": statusStr
            }];
        }
        diagnostics[@"buffers"] = bufferDetails;
        diagnostics[@"nextBufferId"] = @(self->_nextBufferId);
        
        // Socket information
        NSMutableArray *socketDetails = [NSMutableArray array];
        NSArray *allSocketIds = [self->_asyncSockets allKeys];
        for (NSNumber *socketId in allSocketIds) {
            GCDAsyncUdpSocket *udpSocket = self->_asyncSockets[socketId];
            NSDictionary *sInfo = self->_socketInfo[socketId] ?: @{};
            NSNumber *sStatusNumber = self->_socketStatus[socketId];
            NSString *sStatusString = @"unknown_status";
            if ([sStatusNumber isEqualToNumber:kUDPSocketStatusCreated]) sStatusString = @"created";
            else if ([sStatusNumber isEqualToNumber:kUDPSocketStatusBound]) sStatusString = @"bound";
            else if ([sStatusNumber isEqualToNumber:kUDPSocketStatusClosed]) sStatusString = @"closed";
            else if ([sStatusNumber isEqualToNumber:kUDPSocketStatusError]) sStatusString = @"error";

            NSMutableDictionary *details = [NSMutableDictionary dictionaryWithDictionary:@{
                @"id": socketId,
                @"status": sStatusString,
                @"info": sInfo
            }];
            if (udpSocket) {
                details[@"isIPv6"] = @(udpSocket.isIPv6);
                details[@"isClosed"] = @(udpSocket.isClosed);
                details[@"localHost"] = [udpSocket localHost_IPv4] ?: ([udpSocket localHost_IPv6] ?: @"unknown");
                details[@"localPort"] = @([udpSocket localPort]);
            }
            [socketDetails addObject:details];
        }
        diagnostics[@"sockets"] = socketDetails;
        diagnostics[@"nextSocketId"] = @(self->_nextSocketId);
        diagnostics[@"nextSendTag"] = @(self->_nextSendTag);
    });
    return diagnostics;
}


- (void)dealloc {
    UDP_SM_LOG(@"Dealloc starting cleanup...");
    // Ensure cleanup happens on the delegate queue to avoid race conditions with ongoing operations
    dispatch_sync(_delegateQueue, ^{
        for (NSNumber *socketId in [self->_asyncSockets allKeys]) {
            GCDAsyncUdpSocket *udpSocket = self->_asyncSockets[socketId];
            if (udpSocket) {
                UDP_SM_LOG(@"Dealloc: Closing socket %@", socketId);
                [udpSocket close];
            }
        }
        [self->_asyncSockets removeAllObjects];
        [self->_socketStatus removeAllObjects];
        [self->_socketInfo removeAllObjects];
        
        [self->_buffers removeAllObjects];
        [self->_bufferStatus removeAllObjects];
    });
    UDP_SM_LOG(@"Dealloc - cleaned up resources.");
}

@end 