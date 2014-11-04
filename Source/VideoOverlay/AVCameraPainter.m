//
//  AVCameraPainter.m
//  AVSimpleEditoriOS
//
//  Created by malczak on 04/11/14.
//
//

#import "AVCameraPainter.h"

@interface AVCameraPainter () {
    CMTime startTime;
}

@property (nonatomic, strong) dispatch_semaphore_t dataUpdateSemaphore;
@property (nonatomic, copy) void(^originalFrameProcessingCompletionBlock)(GPUImageOutput*, CMTime);

@end

@implementation AVCameraPainter  {
}

#pragma mark -
#pragma mark Initialization and teardown

- (id)initWithSessionPreset:(NSString *)sessionPreset cameraPosition:(AVCaptureDevicePosition)cameraPosition
{
    self = [super init];
    if(self) {
        self.originalFrameProcessingCompletionBlock = nil;
        self.dataUpdateSemaphore = dispatch_semaphore_create(1);
        startTime = kCMTimeIndefinite;
        
        _composer = nil;
        _overlay = nil;

        _isCapturing = NO;
        _isRecording = NO;
        _isPaused = NO;
        
        self.shouldUseCaptureTime = NO;
        self.shouldCaptureAudio = NO;
        
        [self setComposer:[[GPUImageSourceOverBlendFilter alloc] init]];
        [self initCameraWithSessionPreset:sessionPreset position:cameraPosition];
    }
    return self;
}

-(void)initCameraWithSessionPreset:(NSString *)sessionPreset position:(AVCaptureDevicePosition)cameraPosition
{
    _camera = [[GPUImageVideoCamera alloc] initWithSessionPreset:sessionPreset cameraPosition:cameraPosition];

    NSAssert(_camera!=nil,@"Failed to create GPUImageVideoCamera instance");
    
    _camera.horizontallyMirrorFrontFacingCamera = NO;
    _camera.horizontallyMirrorRearFacingCamera = NO;
}

#pragma mark -
#pragma mark Manage classes and options

-(void) setComposer:(GPUImageTwoInputFilter *) framesComposer
{
    if(_isRecording || _isCapturing) {
        @throw [NSException exceptionWithName:@"Cannot set composer while capturing video" reason:nil userInfo:nil];
    }
    
    if(![framesComposer isKindOfClass:[GPUImageTwoInputFilter class]]) {
        @throw [NSException exceptionWithName:@"Expected GPUImageTwoInputFilter subclass"  reason:nil userInfo:nil];
    }
    
    _composer = framesComposer;
}

-(void) setOverlay:(AVFrameDrawer *) framesOverlay
{
    if(_isRecording || _isCapturing) {
        @throw [NSException exceptionWithName:@"Cannot set overlay while capturing video" reason:nil userInfo:nil];
    }

    if(![framesOverlay isKindOfClass:[AVFrameDrawer class]]) {
        @throw [NSException exceptionWithName:@"Expected AVFrameDrawer subclass"  reason:nil userInfo:nil];
    }
    
    _overlay = framesOverlay;
}

#pragma mark -
#pragma mark Manage the camera video stream

- (void)startCameraCapture;
{
    if(!_isCapturing) {
        [self initCameraCapture];
        [_camera startCameraCapture];
        _isCapturing = YES;
    }
}

- (void)stopCameraCapture;
{
    if(_isCapturing) {
        if(_isRecording) {
            [self stopCameraRecordingWithCompetionHandler:nil];
        }
        [_camera stopCameraCapture];
        [self freeCameraCapture];
        _isCapturing = NO;
    }
}

- (void)pauseCameraCapture;
{
    if(!_isPaused) {
        [_camera pauseCameraCapture];
        _isPaused = YES;
    }
}

- (void)resumeCameraCapture;
{
    if(_isPaused) {
        [_camera resumeCameraCapture];
        _isPaused = NO;
    }
}

#pragma mark -
#pragma mark Manage the camera recording

/** Start camera recording
 */
- (void)startCameraRecordingWithURL:(NSURL*) url size:(CGSize) size;
{
    if(!_isCapturing) {
        @throw [NSException exceptionWithName:@"Forgot to start camera capture?" reason:nil userInfo:nil];
    }

    if(!_isRecording) {
        [self initCameraRecordingWithURL:url size:size];
        _isRecording = YES;
    }
}

/** Stop camera recording
 */
- (void)stopCameraRecordingWithCompetionHandler:(void (^)(void))handler
{
    if(_isRecording) {
        [self freeCameraRecordingWithCompetionHandler:handler];
        _isRecording = NO;
    }
}

#pragma mark -
#pragma mark Private camera capture methods

-(void) initCameraCapture
{
    [_camera addTarget:_composer];
    
    if(_overlay != nil) {
        
        startTime = kCMTimeIndefinite;
        
        [_overlay addTarget:_composer];
        [_overlay processData];

        __weak AVFrameDrawer *weakOverlay = _overlay;
        __weak AVCameraPainter *weakSelf = self;
        
        self.originalFrameProcessingCompletionBlock = [_composer frameProcessingCompletionBlock];

        void(^frameProcessingCompletionBlock)(GPUImageOutput*, CMTime) = ^(GPUImageOutput* output, CMTime processingTime) {
            
            CMTime currentTime = processingTime;

            if(CMTIME_IS_INDEFINITE(startTime)) {
                startTime = processingTime;
            }
            
            __strong AVCameraPainter *strongSelf = weakSelf;
            if(strongSelf){
                if(strongSelf.originalFrameProcessingCompletionBlock) {
                    strongSelf.originalFrameProcessingCompletionBlock(output, processingTime);
                }
                
                currentTime = [strongSelf recordTime];
                if(CMTIME_IS_INDEFINITE(currentTime)) {
                    currentTime = strongSelf.shouldUseCaptureTime ? [strongSelf captureTime:processingTime] : kCMTimeZero;
                }
            }
            
            __strong AVFrameDrawer *strongOverlay = weakOverlay;
            if(strongOverlay) {
                [strongOverlay frameProcessingCompletionBlock](output, currentTime);
            }

        };
        
//        [fakeFilter setFrameProcessingCompletionBlock:frameProcessingCompletionBlock];
        [_composer setFrameProcessingCompletionBlock:frameProcessingCompletionBlock];
    }
    
    if(self.shouldCaptureAudio) {
        [_camera addAudioInputsAndOutputs];
    }
}

-(void) initCameraRecordingWithURL:(NSURL*) url size:(CGSize) size
{
    _writer = [[GPUImageMovieWriter alloc] initWithMovieURL:url size:size];
    [_composer addTarget:_writer];

    if(self.shouldCaptureAudio) {
        _camera.audioEncodingTarget = _writer;
    }
    
    _writer.encodingLiveVideo = YES;
    [_writer startRecording];
}

-(void) freeCameraCapture
{
    self.originalFrameProcessingCompletionBlock = nil;
    
    if(_overlay != nil) {
        [_overlay removeTarget:_composer];
        [_composer setFrameProcessingCompletionBlock:nil];
    }
    
    [_camera removeTarget:_composer];
}

-(void) freeCameraRecordingWithCompetionHandler:(void (^)(void))handler
{
    _camera.audioEncodingTarget = nil;
    [_composer removeTarget:_writer];
    
    if (dispatch_semaphore_wait(self.dataUpdateSemaphore, DISPATCH_TIME_NOW) != 0)
    {
        return;
    }
    
    __weak AVCameraPainter *weakSelf = self;
    // set_sema
    [_writer finishRecordingWithCompletionHandler:^(){
        if(handler) {
            handler();
        }

        __strong AVCameraPainter *strongSelf = weakSelf;
        if(strongSelf) {
            [strongSelf destroyCameraWriter];
        }
        
    }];
}

-(void) destroyCameraWriter
{
    _writer = nil;
    dispatch_semaphore_signal(self.dataUpdateSemaphore);
}

#pragma mark - Handle capture / recording

-(CMTime) captureTime:(CMTime) processingTime {
    return CMTimeSubtract(processingTime, startTime);
}

-(CMTime) recordTime {
    return (_isRecording) ? _writer.duration : kCMTimeIndefinite;
}

#pragma mark - Deallocation

-(void)dealloc
{
    [self stopCameraCapture];

    _camera = nil;
    _overlay = nil;
    _composer = nil;
}

@end
