//
//  AVCameraPainter.h
//  AVSimpleEditoriOS
//
//  Created by malczak on 04/11/14.
//
//

#import <Foundation/Foundation.h>
#import "AVFrameDrawer.h"
#import "GPUImage.h"

@interface AVCameraPainter : NSObject {
}

@property (nonatomic, assign) BOOL shouldUseCaptureTime;
@property (nonatomic, assign) BOOL shouldCaptureAudio;

@property (nonatomic, readonly) BOOL isCapturing;
@property (nonatomic, readonly) BOOL isRecording;
@property (nonatomic, readonly) BOOL isPaused;

@property (nonatomic, readonly) GPUImageTwoInputFilter *composer;
@property (nonatomic, readonly) AVFrameDrawer *overlay;

@property (nonatomic, readonly) GPUImageVideoCamera *camera;
@property (nonatomic, readonly) GPUImageMovieWriter *writer;

/// @name Initialization and teardown

/** Iniialize camera recorder with sessionPreset and device

 See AVCaptureSession for acceptable values
 
 @param sessionPreset Session preset to use
 @param cameraPosition Camera to capture from
 */
- (id)initWithSessionPreset:(NSString *)sessionPreset cameraPosition:(AVCaptureDevicePosition)cameraPosition;

/// @name Manage classes and options

-(void) setComposer:(GPUImageTwoInputFilter *) framesComposer;

-(void) setOverlay:(AVFrameDrawer *) framesOverlay;

/// @name Manage the camera video stream

/** Start camera capturing
 */
- (void)startCameraCapture;

/** Stop camera capturing
 */
- (void)stopCameraCapture;

/** Pause camera capturing
 */
- (void)pauseCameraCapture;

/** Resume camera capturing
 */
- (void)resumeCameraCapture;

/// @name Manage the camera recording

/** Start camera recording
 */
- (void)startCameraRecordingWithURL:(NSURL*) url size:(CGSize) size;

/** Stop camera recording
 */
- (void)stopCameraRecordingWithCompetionHandler:(void (^)(void))handler;


@end
