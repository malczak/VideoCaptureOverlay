//
//  ViewController.m
//  VideoCaptureOverlay
//
//  Created by malczak on 04/11/14.
//  Copyright (c) 2014 segfaultsoft. All rights reserved.
//

#import <AssetsLibrary/AssetsLibrary.h>
#import <SVProgressHUD.h>
#import "ViewController.h"
#import "AVFrameDrawer.h"
#import "AVCameraPainter.h"

@interface ViewController () {
    GPUImageView *cameraPreview;
    AVCameraPainter *painter;
    AVFrameDrawer *frameDrawer;
    
    NSURL *outUrl;
}

@property (nonatomic, weak) IBOutlet UIButton *recordButton;

@end

@implementation ViewController

// hd - like a boss
static CGFloat targetWidth = 1280.0;
static CGFloat targetHeight = 720.0;

static NSUInteger videoDurationInSec = 240; // 4min+


- (void)viewDidLoad {
    [super viewDidLoad];
    
    // create camera preview
    [self createCameraPreview];
    
    // init capture session and pass it to preview
    [self initCameraCapture];
    
    [self.recordButton addTarget:self action:@selector(recordButtonHandler:) forControlEvents:UIControlEventTouchUpInside];
}

#pragma mark -
#pragma mark - Record button

-(void) recordButtonHandler:(id) sender
{
    if(painter.isRecording) {
        [self stopCameraCapture];
    } else {
        [self startCameraCapture];        
    }
}

#pragma mark -
#pragma mark - Initialize camera preview view

-(void) createCameraPreview
{
    CGRect screen = [[UIScreen mainScreen] bounds];
    
    CGRect rect = CGRectMake(0, 0, screen.size.height, screen.size.width);
    CGAffineTransform T = CGAffineTransformIdentity;
    
    T = CGAffineTransformTranslate(T, -rect.size.width * 0.5, -rect.size.height * 0.5);
    T = CGAffineTransformRotate(T, M_PI_2);
    T = CGAffineTransformTranslate(T, rect.size.width * 0.5, -rect.size.height * 0.5);
    
    cameraPreview = [[GPUImageView alloc] initWithFrame:rect];
    cameraPreview.transform = T;
    cameraPreview.fillMode = kGPUImageFillModePreserveAspectRatio;
    
    [self.view insertSubview:cameraPreview atIndex:0];
}

#pragma mark -
#pragma mark - Initialize camera capture

-(void) initCameraCapture
{
    // create video painter
    painter = [[AVCameraPainter alloc] initWithSessionPreset:AVCaptureSessionPreset1280x720 cameraPosition:AVCaptureDevicePositionBack];
    painter.shouldCaptureAudio = NO;
    painter.camera.outputImageOrientation = UIInterfaceOrientationMaskLandscapeRight;
    
    
    // context initialization - block (we dont want to overload class in this example)
    void (^contextInitialization)(CGContextRef context, CGSize size) = ^(CGContextRef context, CGSize size) {
        CGContextClearRect(context, CGRectMake(0, 0, size.width, size.height));
        
        CGContextSetRGBFillColor(context, 0.0, 1.0, 0.0, 0.5);
        CGContextFillRect(context, CGRectMake(0, 0, size.width*0.3, size.height*0.8));
        
        CGContextSetRGBFillColor(context, 1.0, 1.0, 1.0, 0.7);
        CGContextFillEllipseInRect(context, CGRectMake(0, 0, size.width*0.5, size.height*0.4));
        
        NSString *fontName = @"Courier-Bold";
        CGContextSelectFont(context, [fontName UTF8String], 18, kCGEncodingMacRoman);
        
        CGContextSetRGBFillColor(context, 1, 0, 0, 1);
        NSString *s = @"Just running this ...";
        CGContextShowTextAtPoint(context, 10, 10, [s UTF8String], s.length);
    };
    
    // create overlay + some code
    frameDrawer = [[AVFrameDrawer alloc] initWithSize:CGSizeMake(targetWidth, targetHeight)
                               contextInitailizeBlock:contextInitialization];
    
    frameDrawer.contextUpdateBlock = ^BOOL(CGContextRef context, CGSize size, CMTime time) {
        CGContextSetRGBFillColor(context, 1, 1, 1, 1);
        //    s = [s stringByAppendingString:@"-"];
        NSString *chars = @"-\\|/";
        CGFloat secondsf = (CGFloat)time.value / (CGFloat)time.timescale;
        NSUInteger seconds = (int)roundf(secondsf);
        NSUInteger loc = (int)roundf(secondsf * 10) % (int)chars.length;
        NSString *s = [chars substringWithRange:NSMakeRange(loc,1)];
        
        CGContextClearRect(context, CGRectMake(90, 90, 120, 40));
        CGContextClearRect(context, CGRectMake(90, 90, 120, 40));
        CGContextSetRGBFillColor(context, 0, 0, 0, 0.8);
        CGContextFillRect(context, CGRectMake(90, 90, 120, 40));
        
        s = [NSString stringWithFormat:@"%@ - %02d:%02d",s,(int)(seconds / 60),(int)(seconds % 60)];
        
        CGContextSetRGBFillColor(context, 1, 1, 1, 1);
        CGContextShowTextAtPoint(context, 100, 100, [s UTF8String], s.length);
        
        return YES;
    };
    
    // setup composer, preview and painter all together
    [painter.composer addTarget:cameraPreview];
    
    [painter setOverlay:frameDrawer];
    
    [painter startCameraCapture];
}

#pragma mark -
#pragma mark - Handler camera capture

-(void) startCameraCapture
{
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"file.mov"];
    outUrl = [NSURL fileURLWithPath:path];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:path error:nil];
    
    NSLog(@"Recording ...");
    
    [painter startCameraRecordingWithURL:outUrl size:CGSizeMake(targetWidth, targetHeight)];
    
    __weak ViewController *weakSelf = self;

    int64_t stopDelay = (int64_t)(videoDurationInSec * NSEC_PER_SEC);
    dispatch_time_t autoStopTime = dispatch_time(DISPATCH_TIME_NOW, stopDelay);
    
    dispatch_after(autoStopTime, dispatch_get_main_queue(), ^{
        [weakSelf stopCameraCapture];
    });
 
    [self.recordButton setTitle:@"STOP" forState:UIControlStateNormal];
}

-(void) stopCameraCapture
{
    if(!painter.isRecording) {
        return;
    }
    
    NSURL *movieUrl = outUrl;
    
    __weak ViewController *weakSelf = self;
    
    [painter stopCameraRecordingWithCompetionHandler:^(){
        
        dispatch_async(dispatch_get_main_queue(), ^(){
            NSLog(@"Recorded :/");
            [SVProgressHUD showWithStatus:@"Exporting..."];
            
            [weakSelf.recordButton setTitle:@"Record" forState:UIControlStateNormal];
            
            ALAssetsLibrary *assetsLibrary = [[ALAssetsLibrary alloc] init];
            if ([assetsLibrary videoAtPathIsCompatibleWithSavedPhotosAlbum:movieUrl]) {
                [assetsLibrary writeVideoAtPathToSavedPhotosAlbum:movieUrl completionBlock:^(NSURL *assetURL, NSError *error){
                    
                    dispatch_async(dispatch_get_main_queue(), ^(){
                        [SVProgressHUD showSuccessWithStatus:@"File saved in photo..."];
                    });
                    
                }];
            }
        });
    }];
}

#pragma mark -
#pragma mark - Handle dark side

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    NSLog(@"Darkness it getting closer... run... run... you fools!");
}

-(void)dealloc
{
    // Nooooooooo
}

@end
