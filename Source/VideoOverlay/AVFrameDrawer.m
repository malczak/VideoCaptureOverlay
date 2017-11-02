//
//  AVFrameDrawer
//  https://github.com/malczak/VideoCaptureOverlay
//

#import "AVFrameDrawer.h"

@interface AVFrameDrawer () {
    void *dataPtr;
    CGContextRef context;
}

@end

@implementation AVFrameDrawer

-(id) initWithSize:(CGSize) size {
    self = [self initWithSize:size contextInitailizeBlock:nil];
    return self;
}

-(id) initWithSize:(CGSize) size contextInitailizeBlock:(void(^)(CGContextRef context, CGSize size)) contextInitializeBlock
{
    self = [super init];
    if(self) {
        dataUpdateSemaphore = dispatch_semaphore_create(1);
        
        uploadedImageSize = size;
        pixelFormat = GPUPixelFormatBGRA;
        pixelType = GPUPixelTypeUByte;
        
        hasProcessedData = NO;
        
        dataPtr = NULL;
        
        __weak AVFrameDrawer *weakSelf = self;
        [self setFrameProcessingCompletionBlock:^(GPUImageOutput* output, CMTime time) {
            __strong AVFrameDrawer *strongSelf = weakSelf;
            if(strongSelf){
                BOOL contextModified = [strongSelf updateContextAtTime:time];
                
                if(strongSelf.contextUpdateBlock) {
                    BOOL contextModifiedInBlock = strongSelf.contextUpdateBlock([strongSelf outputContext], [strongSelf outputImageSize], time);
                    contextModified = contextModified || contextModifiedInBlock;
                }
                
                if(contextModified) {
                    [strongSelf updateContext];
                    // dont you will notify target and cause a update cycle ! this should be used if painter is on other target than camera
                    // [strongSelf processData];
                }
            }
        }];
        
        [self initBufferWithSize:size contextInitailizeBlock:contextInitializeBlock];
        [self initFramebuffer];
        [self updateContext];
    }
    return self;
}

-(void) initBufferWithSize:(CGSize) size contextInitailizeBlock:(void(^)(CGContextRef context, CGSize size)) contextInitializeBlock
{
    NSUInteger width = (NSUInteger)size.width;
    NSUInteger height = (NSUInteger)size.height;
    
    // If passed an empty image reference, CGContextDrawImage will fail in future versions of the SDK.
    NSAssert( width > 0 && height > 0, @"Passed size must not be empty - it should be at least 1px tall and wide");

    // Create context bitmap 
    NSUInteger bytesPerLine = width << 2;
    NSUInteger bytesCount = height * bytesPerLine;
    
    dataPtr = calloc(1, bytesCount);
    memset(dataPtr, 0x0, bytesCount);
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    
    context = CGBitmapContextCreate(dataPtr, width, height, 8, bytesPerLine, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    
    CGColorSpaceRelease(colorSpace);
    
    NSAssert(context != NULL, @"Failed to create bitmap context");
    
    [self initializeContext];
    
    if(contextInitializeBlock) {
        contextInitializeBlock([self outputContext], [self outputImageSize]);
    }
}

-(void) initFramebuffer
{
    [GPUImageContext useImageProcessingContext];
    
    outputFramebuffer = [[GPUImageContext sharedFramebufferCache] fetchFramebufferForSize:uploadedImageSize
                                                                           textureOptions:self.outputTextureOptions
                                                                              onlyTexture:YES];

    [outputFramebuffer disableReferenceCounting];
}

-(void) initializeContext
{
    
}

- (void)uploadBytes:(GLubyte *)bytesToUpload;
{
    hasProcessedData = NO;
    
    // should be async (?) or symed (?)
    glBindTexture(GL_TEXTURE_2D, [outputFramebuffer texture]);
    glTexImage2D(GL_TEXTURE_2D, 0, pixelFormat==GPUPixelFormatRGB ? GL_RGB : GL_RGBA, (int)uploadedImageSize.width, (int)uploadedImageSize.height, 0, (GLint)pixelFormat, (GLenum)pixelType, bytesToUpload);
    glBindTexture(GL_TEXTURE_2D, 0);
}

- (void)processData;
{
    if (dispatch_semaphore_wait(dataUpdateSemaphore, DISPATCH_TIME_NOW) != 0)
    {
        return;
    }
    
    hasProcessedData = YES;
    
    runAsynchronouslyOnVideoProcessingQueue(^{
    
        CGSize pixelSizeOfImage = [self outputImageSize];
        
        for (id<GPUImageInput> currentTarget in targets)
        {
            NSInteger indexOfObject = [targets indexOfObject:currentTarget];
            NSInteger textureIndexOfTarget = [[targetTextureIndices objectAtIndex:indexOfObject] integerValue];
            
            [currentTarget setInputSize:pixelSizeOfImage atIndex:textureIndexOfTarget];
            [currentTarget setInputFramebuffer:outputFramebuffer atIndex:textureIndexOfTarget];
            [currentTarget newFrameReadyAtTime:kCMTimeIndefinite atIndex:textureIndexOfTarget];
        }
        
        dispatch_semaphore_signal(dataUpdateSemaphore);
    });
}

/*
- (void)processDataForTimestamp:(CMTime)frameTime;
{
    if (dispatch_semaphore_wait(dataUpdateSemaphore, DISPATCH_TIME_NOW) != 0)
    {
        return;
    }
    
    runAsynchronouslyOnVideoProcessingQueue(^{
        
        CGSize pixelSizeOfImage = [self outputImageSize];
        
        for (id<GPUImageInput> currentTarget in targets)
        {
            NSInteger indexOfObject = [targets indexOfObject:currentTarget];
            NSInteger textureIndexOfTarget = [[targetTextureIndices objectAtIndex:indexOfObject] integerValue];
            
            [currentTarget setInputSize:pixelSizeOfImage atIndex:textureIndexOfTarget];
            [currentTarget newFrameReadyAtTime:frameTime atIndex:textureIndexOfTarget];
        }
        
        dispatch_semaphore_signal(dataUpdateSemaphore);
    });
}
*/

-(void) disposeFramebuffer
{
    [outputFramebuffer enableReferenceCounting];
    [outputFramebuffer unlock];
}

-(BOOL) updateContextAtTime:(CMTime) time
{    
    return NO;
}

-(void)addTarget:(id<GPUImageInput>)newTarget atTextureLocation:(NSInteger)textureLocation
{
    [super addTarget:newTarget atTextureLocation:textureLocation];
    
    if(hasProcessedData) {
        [newTarget setInputSize:[self outputImageSize] atIndex:textureLocation];
        // what about input framebuffer
        [newTarget newFrameReadyAtTime:kCMTimeIndefinite atIndex:textureLocation];
    }
}

-(void) updateContext
{
    [self uploadBytes:(GLubyte*)dataPtr];
}

- (CGSize)outputImageSize;
{
    return uploadedImageSize;
}

-(CGContextRef) outputContext
{
    return context;
}

-(void)dealloc
{
    [self disposeFramebuffer];
    CGContextRelease(context);
    if(dataPtr) {
        free(dataPtr);
    }
    self.contextUpdateBlock = nil;
}

@end
