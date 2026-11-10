#import "TyprAudioInput.h"

@interface TyprAudioInput ()
@property(nonatomic, copy) AVAudioEngine * (^engineFactory)(void);
@property(nonatomic, strong, nullable) AVAudioEngine *engine;
@property(nonatomic) BOOL tapInstalled;
@end

@implementation TyprAudioInput

- (instancetype)init {
    return [self initWithEngineFactory:^{ return [[AVAudioEngine alloc] init]; }];
}

- (instancetype)initWithEngineFactory:(AVAudioEngine * (^)(void))engineFactory {
    self = [super init];
    if (self) {
        _engineFactory = [engineFactory copy];
    }
    return self;
}

- (BOOL)isRunning {
    return self.engine.isRunning;
}

- (BOOL)startWithBufferHandler:(AVAudioNodeTapBlock)handler error:(NSError **)error {
    [self stop];
    BOOL started = NO;
    NSError *startError = nil;
    @try {
        // A stopped/reset engine can retain the previous route's input format.
        // Create the graph only after the caller activated the audio session.
        self.engine = self.engineFactory();
        AVAudioInputNode *input = self.engine.inputNode;
        AVAudioFormat *format = [input outputFormatForBus:0];
        if (format.sampleRate > 0 && format.channelCount > 0) {
            // Let AVFAudio choose the current native format rather than pinning
            // a snapshot that can go stale during a CarPlay/Bluetooth transition.
            [input installTapOnBus:0 bufferSize:4096 format:nil block:handler];
            self.tapInstalled = YES;
            [self.engine prepare];
            started = [self.engine startAndReturnError:&startError];
        }
    } @catch (NSException *exception) {
        // AVFAudio assertions are not Swift Errors. Catch them entirely in ObjC,
        // discard this graph, and use the existing recoverable UI error path.
        // Do not expose device/route information from exception.reason.
        (void)exception;
    }
    if (!started) {
        [self stop];
        if (error) {
            *error = startError ?: [NSError errorWithDomain:@"dev.rudek.typr.audio" code:1 userInfo:@{
                NSLocalizedDescriptionKey: @"The microphone is temporarily unavailable. Try dictating again."
            }];
        }
    }
    return started;
}

- (void)dealloc {
    [self stop];
}

- (void)stop {
    AVAudioEngine *engine = self.engine;
    self.engine = nil;
    BOOL hadTap = self.tapInstalled;
    self.tapInstalled = NO;
    // Cleanup must not raise a second exception from an already-invalid graph.
    @try {
        [engine stop];
    } @catch (NSException *exception) {
        (void)exception;
    }
    if (hadTap) {
        @try {
            [engine.inputNode removeTapOnBus:0];
        } @catch (NSException *exception) {
            (void)exception;
        }
    }
}

@end
