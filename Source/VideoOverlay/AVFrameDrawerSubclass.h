//
//  AVFrameDrawer.m
//  AVSimpleEditoriOS
//
//  Created by malczak on 03/11/14.
//
//

#import "AVFrameDrawer.h"

@interface AVFrameDrawer (AVFrameDrawerProtected)

-(void) initializeContext;

-(BOOL) updateContextAtTime:(CMTime) time;

-(CGSize)outputImageSize;

-(CGContextRef) outputContext;

@end