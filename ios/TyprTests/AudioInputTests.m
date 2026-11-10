#import <XCTest/XCTest.h>
#import "../Typr/TyprAudioInput.h"

// Raise exceptions only in Objective-C: unwinding a Swift test closure would
// reproduce the unsafe boundary this fix is meant to eliminate.
@interface TestInputNode : NSObject
@property(nonatomic) BOOL failInstall;
@property(nonatomic) BOOL failRemove;
@property(nonatomic) BOOL usedNativeFormat;
@property(nonatomic) NSUInteger installs;
@property(nonatomic) NSUInteger removals;
@property(nonatomic) BOOL invalidFormat;
@end

@implementation TestInputNode
- (AVAudioFormat *)outputFormatForBus:(AVAudioNodeBus)bus {
    if (self.invalidFormat) { return nil; }
    return [[AVAudioFormat alloc] initStandardFormatWithSampleRate:48000 channels:1];
}
- (void)installTapOnBus:(AVAudioNodeBus)bus bufferSize:(AVAudioFrameCount)size
                format:(AVAudioFormat *)format block:(AVAudioNodeTapBlock)block {
    self.installs += 1;
    self.usedNativeFormat = format == nil;
    if (self.failInstall) {
        [NSException raise:NSInvalidArgumentException format:@"simulated route/format assertion"];
    }
}
- (void)removeTapOnBus:(AVAudioNodeBus)bus {
    self.removals += 1;
    if (self.failRemove) {
        [NSException raise:NSInternalInconsistencyException format:@"simulated invalid graph cleanup"];
    }
}
@end

@interface TestInputEngine : AVAudioEngine
@property(nonatomic, strong) TestInputNode *testInput;
@property(nonatomic) BOOL testRunning;
@property(nonatomic) BOOL failPrepare;
@property(nonatomic) BOOL failStart;
@property(nonatomic) BOOL failStop;
@property(nonatomic) NSUInteger stops;
@end

@implementation TestInputEngine
- (instancetype)init {
    self = [super init];
    if (self) { _testInput = [[TestInputNode alloc] init]; }
    return self;
}
- (AVAudioInputNode *)inputNode { return (AVAudioInputNode *)self.testInput; }
- (BOOL)isRunning { return self.testRunning; }
- (void)prepare {
    if (self.failPrepare) {
        [NSException raise:NSInternalInconsistencyException format:@"simulated prepare assertion"];
    }
}
- (BOOL)startAndReturnError:(NSError **)error {
    if (self.failStart) {
        if (error) { *error = [NSError errorWithDomain:@"test.audio" code:42 userInfo:nil]; }
        return NO;
    }
    self.testRunning = YES;
    return YES;
}
- (void)stop {
    self.stops += 1;
    self.testRunning = NO;
    if (self.failStop) {
        [NSException raise:NSInternalInconsistencyException format:@"simulated stop assertion"];
    }
}
@end

@interface AudioInputTests : XCTestCase
@end

@implementation AudioInputTests

- (AVAudioNodeTapBlock)handler {
    return ^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {};
}

- (void)testTapExceptionBecomesErrorAndNextStartUsesFreshNativeGraph {
    TestInputEngine *bad = [[TestInputEngine alloc] init];
    bad.testInput.failInstall = YES;
    TestInputEngine *good = [[TestInputEngine alloc] init];
    __block NSUInteger creations = 0;
    TyprAudioInput *input = [[TyprAudioInput alloc] initWithEngineFactory:^{
        return creations++ == 0 ? bad : good;
    }];
    NSError *error = nil;
    XCTAssertFalse([input startWithBufferHandler:self.handler error:&error]);
    XCTAssertEqualObjects(error.domain, @"dev.rudek.typr.audio");
    XCTAssertFalse(input.isRunning);
    XCTAssertEqual(bad.stops, 1u);
    XCTAssertTrue(bad.testInput.usedNativeFormat);
    XCTAssertFalse([error.localizedDescription containsString:@"assertion"]);

    error = nil;
    XCTAssertTrue([input startWithBufferHandler:self.handler error:&error]);
    XCTAssertNil(error);
    XCTAssertTrue(input.isRunning);
    XCTAssertEqual(creations, 2u);
    XCTAssertTrue(good.testInput.usedNativeFormat);
    [input stop];
    [input stop];
    XCTAssertFalse(input.isRunning);
    XCTAssertEqual(good.testInput.removals, 1u);
    XCTAssertEqual(good.stops, 1u);
}

- (void)testPrepareExceptionCleansInstalledTapEvenWhenCleanupRaises {
    TestInputEngine *engine = [[TestInputEngine alloc] init];
    engine.failPrepare = YES;
    engine.failStop = YES;
    engine.testInput.failRemove = YES;
    TyprAudioInput *input = [[TyprAudioInput alloc] initWithEngineFactory:^{ return engine; }];
    NSError *error = nil;
    XCTAssertFalse([input startWithBufferHandler:self.handler error:&error]);
    XCTAssertNotNil(error);
    XCTAssertFalse(input.isRunning);
    XCTAssertEqual(engine.stops, 1u);
    XCTAssertEqual(engine.testInput.removals, 1u);
    XCTAssertNoThrow([input stop]);
}

- (void)testStartErrorIsPreservedAndGraphIsDiscarded {
    TestInputEngine *engine = [[TestInputEngine alloc] init];
    engine.failStart = YES;
    TyprAudioInput *input = [[TyprAudioInput alloc] initWithEngineFactory:^{ return engine; }];
    NSError *error = nil;
    XCTAssertFalse([input startWithBufferHandler:self.handler error:&error]);
    XCTAssertEqualObjects(error.domain, @"test.audio");
    XCTAssertEqual(error.code, 42);
    XCTAssertFalse(input.isRunning);
    XCTAssertEqual(engine.testInput.removals, 1u);
}

- (void)testUnavailableInputDoesNotInstallTap {
    TestInputEngine *engine = [[TestInputEngine alloc] init];
    engine.testInput.invalidFormat = YES;
    TyprAudioInput *input = [[TyprAudioInput alloc] initWithEngineFactory:^{ return engine; }];
    NSError *error = nil;
    XCTAssertFalse([input startWithBufferHandler:self.handler error:&error]);
    XCTAssertNotNil(error);
    XCTAssertEqual(engine.testInput.installs, 0u);
    XCTAssertFalse(input.isRunning);
}

@end
