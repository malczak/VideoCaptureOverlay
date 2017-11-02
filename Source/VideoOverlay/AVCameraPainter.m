//
//  AVCameraPainter
//  https://github.com/malczak/VideoCaptureOverlay
//

#import "AVCameraPainter.h"

@interface AVCameraPainter () {
    CMTime startTime;
}

@property (nonatomic, assign) int fileDescriptor;
@property (nonatomic, strong) dispatch_source_t fileObserver;

@property (nonatomic, strong) dispatch_semaphore_t dataUpdateSemaphore;
@property (nonatomic, copy) void(^originalFrameProcessingCompletionBlock)(GPUImageOutput*, CMTime);

-(GPUImageOutput*) mainWriterOutput;

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
    _camera = [[GPUImageVideoCamera alloc] initWithSessionPreset:sessionPreset
                                                  cameraPosition:cameraPosition];

    NSAssert(_camera!=nil,@"Failed to create GPUImageVideoCamera instance");
    
    _camera.horizontallyMirrorFrontFacingCamera = YES;
    _camera.horizontallyMirrorRearFacingCamera = NO;
//    _camera.inputCamera.exposurePointOfInterest
}

#pragma mark -
#pragma mark Manage classes and options

-(void)setShouldRecordOverlay:(BOOL)value
{
    if(_isRecording || _isCapturing) {
        @throw [NSException exceptionWithName:@"Cannot set 'shouldRecordOverlay' while capturing video" reason:nil userInfo:nil];
    }

    _shouldRecordOverlay = value;
}

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

- (void)startCameraRecordingWithURL:(NSURL*) url size:(CGSize) size metaData:(NSArray<AVMetadataItem*>*) metadata
{
    if(!_isCapturing) {
        @throw [NSException exceptionWithName:@"Forgot to start camera capture?" reason:nil userInfo:nil];
    }

    if(!_isRecording) {
        [self initCameraRecordingWithURL:url
                                    size:size
                                metaData:metadata];
        _isRecording = YES;
    }
}

- (void)stopCameraRecordingWithCompetionHandler:(void (^)(AVCameraPainter*))handler
{
    if(_isRecording) {
        [self freeCameraRecordingWithCompetionHandler:handler];
        _isRecording = NO;
    }
}

- (void)cancelCameraRecording
{
    if(_isRecording) {
        if (dispatch_semaphore_wait(self.dataUpdateSemaphore, DISPATCH_TIME_NOW) != 0)
        {
            return;
        }
        
        [self removeFileObserver];
        [_writer cancelRecording];
        [self destroyCameraWriter];
    }
}

- (void)caputreStillImage
{
    if(_isRecording) {

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

            // set startTime frame time on first call :S
            if(CMTIME_IS_INDEFINITE(startTime))
            {
                startTime = processingTime; // @todo startTime is catupring 'self'
            }
            
            __strong AVCameraPainter *strongSelf = weakSelf;
            if(strongSelf)
            {
                // perform original composition using real composition time
                if(strongSelf.originalFrameProcessingCompletionBlock)
                {
                    strongSelf.originalFrameProcessingCompletionBlock(output, processingTime);
                }
                
                // use recording time for frame drawer
                currentTime = [strongSelf recordTime];
                if(CMTIME_IS_INDEFINITE(currentTime))
                {
                    currentTime = strongSelf.shouldUseCaptureTime ? [strongSelf captureTime:processingTime] : kCMTimeZero;
                }
            }
            
            __strong AVFrameDrawer *strongOverlay = weakOverlay;
            if(strongOverlay)
            {
                [strongOverlay frameProcessingCompletionBlock](output, currentTime); // @todo pass time etc :P
            }

        };
        
//        [fakeFilter setFrameProcessingCompletionBlock:frameProcessingCompletionBlock];
        [_composer setFrameProcessingCompletionBlock:frameProcessingCompletionBlock];
    }
    
    if(self.shouldCaptureAudio)
    {
        [_camera addAudioInputsAndOutputs];
    }
}

-(void) initCameraRecordingWithURL:(NSURL*) url size:(CGSize) size metaData:(NSArray<AVMetadataItem*>*) metadata
{
    if(_isRecording) {
        return;
    }
    
    _isRecording = YES;
    
    _writer = [[GPUImageMovieWriter alloc] initWithMovieURL:url
                                                       size:size];
    _writer.delegate = self;
    _writer.metaData = metadata;
    
    [[self mainWriterOutput] addTarget:_writer];

    if(self.shouldCaptureAudio) {
        _camera.audioEncodingTarget = _writer;
    }
    _writer.encodingLiveVideo = YES;
    [_writer startRecording];

    [self createFileObserver];
}

-(void) createFileObserver
{
    if(!_isRecording) {
        return ;
    }
    
    AVAssetWriter *assetWriter = _writer.assetWriter;
    if(!assetWriter || !assetWriter.outputURL) {
        return ;
    }
    
    NSURL *movieUrl = assetWriter.outputURL;
    dispatch_queue_t defaultQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    self.fileDescriptor = open([[movieUrl path] fileSystemRepresentation], O_EVTONLY);
    // Get a reference to the default queue so our file notifications can go out on it
    
    // Create a dispatch source
    self.fileObserver = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE,
                                               self.fileDescriptor,
                                               DISPATCH_VNODE_ATTRIB | DISPATCH_VNODE_DELETE | DISPATCH_VNODE_EXTEND | DISPATCH_VNODE_LINK | DISPATCH_VNODE_RENAME | DISPATCH_VNODE_REVOKE | DISPATCH_VNODE_WRITE,
                                               defaultQueue);
    
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(self.fileObserver, ^
                                      {
                                          unsigned long eventTypes = dispatch_source_get_data(weakSelf.fileObserver);
                                          [weakSelf handleFileEvent:eventTypes];
                                      });
    
    dispatch_source_set_cancel_handler(self.fileObserver, ^
                                       {
                                           __strong typeof(weakSelf) strongSelf = weakSelf;
                                           if(strongSelf) {
                                               close(strongSelf.fileDescriptor);
                                               strongSelf.fileDescriptor = 0;
                                               strongSelf.fileObserver = nil;
                                           }
                                       });
    dispatch_resume(self.fileObserver);
}

-(void) removeFileObserver
{
    if(self.fileObserver) {
        dispatch_source_cancel(self.fileObserver);
    }
}

- (void)handleFileEvent:(unsigned long)eventTypes
{
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^
                   {
                       if (eventTypes & (DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME))
                       {
                           // file removed (!) cancel recording
                           if(weakSelf.isRecording) {
                               [weakSelf cancelCameraRecording];
                           }
                       }
                   });
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

-(void) freeCameraRecordingWithCompetionHandler:(void (^)(AVCameraPainter*))handler
{
    _camera.audioEncodingTarget = nil;
    [[self mainWriterOutput] removeTarget:_writer];
    
    if (dispatch_semaphore_wait(self.dataUpdateSemaphore, DISPATCH_TIME_NOW) != 0)
    {
        return;
    }
    
    [self removeFileObserver];
    __weak AVCameraPainter *weakSelf = self;
    [_writer finishRecordingWithCompletionHandler:^(){
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if(strongSelf)
        {
            if(handler) {
                handler(strongSelf);
            }
            
            [strongSelf destroyCameraWriter];
        }
    }];
}

-(void) destroyCameraWriter
{
    _isRecording = NO;
    _isPaused = NO;
    _writer = nil;
    dispatch_semaphore_signal(self.dataUpdateSemaphore);
}

-(GPUImageOutput*) mainWriterOutput
{
    return self.shouldRecordOverlay ? _composer : _camera;
}

#pragma mark - Handle capture / recording

-(CMTime) captureTime:(CMTime) processingTime
{
    return CMTimeSubtract(processingTime, startTime);
}

-(CMTime) recordTime
{
    return (_isRecording) ? _writer.duration : kCMTimeIndefinite;
}

#pragma mark - GPUImageMovieWriterDelegate protocol implementation

- (void)movieRecordingFailedWithError:(NSError*)error
{
    NSLog(@"%@", [error description]);
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
