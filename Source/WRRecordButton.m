//
//  WRRecordButton.m
//  WodRandomizer
//
//  Created by Mateusz Malczak on 30/05/16.
//  Copyright © 2016 segfaultsoft. All rights reserved.
//

#import "WRRecordButton.h"

@interface WRRecordButton ()

//@property (nonatomic, assign) BOOL selected;

@property (nonatomic, strong) CAShapeLayer *borderLayer;

@property (nonatomic, strong) CAShapeLayer *indicatorLayer;

@end



@implementation WRRecordButton

static NSUInteger kvoSelectedGuard;
static NSUInteger kvoHighlightedGuard;

- (instancetype)init
{
    self = [super init];
    if (self) {
        [self initialize];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        [self initialize];
    }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self initialize];
    }
    return self;
}

-(void) initialize
{
    self.selected = NO;
    self.changeSelectionOnTouch = YES;
    self.borderWidth = 8;
    self.borderSpacing = 3;
    self.animationTime = 0.22;
    
    [self addTarget:self action:@selector(onTouchUpInside:) forControlEvents:UIControlEventTouchUpInside];
    
    [self addObserver:self forKeyPath:@"selected"
              options:NSKeyValueObservingOptionNew|NSKeyValueObservingOptionOld
              context:&kvoSelectedGuard];
    [self addObserver:self forKeyPath:@"highlighted"
              options:NSKeyValueObservingOptionNew|NSKeyValueObservingOptionOld
              context:&kvoHighlightedGuard];
    
    self.borderLayer = [[CAShapeLayer alloc] init];
    [self.layer addSublayer: self.borderLayer];
    
    self.indicatorLayer = [[CAShapeLayer alloc] init];
    [self.layer addSublayer: self.indicatorLayer];
    
    self.backgroundColor = [UIColor clearColor];
}

-(void) onTouchUpInside: (id) sender
{
    if(self.changeSelectionOnTouch)
    {
        [self setSelected:!self.selected];
    }
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSString *,id> *)change context:(void *)context
{
    if(context == &kvoSelectedGuard) {
        [self updateIndicatorState];
    } else
    if(context == &kvoHighlightedGuard)
    {
        [self updateIndicatorColor];
        NSNumber *oldNmbr = [change objectForKey:@"old"];
        NSNumber *newNbmr = [change objectForKey:@"new"];
        if(![oldNmbr isEqualToNumber:newNbmr]) {
            [self updateIndicatorColor];
        }
    } else {
        [super observeValueForKeyPath:keyPath
                             ofObject:object
                               change:change
                              context:context];
    }
}

-(void) updateIndicatorColor
{
    UIColor *highlightColor = self.highlighted ? [UIColor redColor] : [UIColor redColor];
    self.indicatorLayer.fillColor = [highlightColor CGColor];
}

-(void) updateIndicatorState
{
    CGPathRef newPath = [self statePath];
    
    CABasicAnimation *anim = [CABasicAnimation animationWithKeyPath:@"path"];
    anim.removedOnCompletion = NO;
    
    anim.duration = self.animationTime;
    anim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    anim.fromValue = (__bridge id _Nullable)(self.indicatorLayer.path);
    anim.toValue = (__bridge id _Nullable)(newPath);
    
    self.indicatorLayer.path = newPath;
    [self.indicatorLayer addAnimation:anim forKey:@"path.anim"];
    
    if(self.selected)
    {
        CAKeyframeAnimation *canim = [CAKeyframeAnimation animationWithKeyPath:@"fillColor"];
        canim.removedOnCompletion = NO;
        canim.repeatCount = HUGE_VALF;
        canim.duration = 6.0 * self.animationTime;
        canim.timingFunctions = @[
                                  [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut],
                                  [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn]
                                  ];
        canim.values = @[
                         (__bridge id)[[UIColor redColor] CGColor],
                         (__bridge id)[[UIColor redColor] CGColor],
                         (__bridge id)[[UIColor redColor] CGColor]
                         ];
        canim.keyTimes = @[ @0.0, @0.5, @1.0];
        canim.autoreverses = YES;
        [self.indicatorLayer addAnimation:canim forKey:@"path.fill"];
    } else {
        [self.indicatorLayer removeAnimationForKey:@"path.fill"];
    }
}

-(void)layoutSubviews
{
    [super layoutSubviews];
    
    CGRect bounds = self.bounds;
    CGFloat width = CGRectGetWidth(bounds), height = CGRectGetHeight(bounds);
    CGFloat diameter = MIN(width, height);
    CGRect buttonRect = CGRectMake((width - diameter) * 0.5, (height - diameter) * 0.5, diameter, diameter);
    
    CGMutablePathRef cgPath = CGPathCreateMutable();
    CGPathAddEllipseInRect(cgPath, NULL, buttonRect);
    CGPathAddEllipseInRect(cgPath, NULL, CGRectInset(buttonRect, self.borderWidth, self.borderWidth));
    CGPathCloseSubpath(cgPath);
    self.borderLayer.path = CGPathCreateMutableCopy(cgPath);
    self.borderLayer.fillRule = kCAFillRuleEvenOdd;
    self.borderLayer.fillColor = [[UIColor whiteColor] CGColor];
    CGPathRelease(cgPath);

    self.indicatorLayer.path = [self statePath];
    self.indicatorLayer.fillRule = kCAFillRuleEvenOdd;
    self.indicatorLayer.fillColor = [[UIColor redColor] CGColor];
}

-(CGRect) buttonRect
{
    CGRect bounds = self.bounds;
    CGFloat width = CGRectGetWidth(bounds), height = CGRectGetHeight(bounds);
    CGFloat diameter = MIN(width, height);
    return CGRectMake((width - diameter) * 0.5, (height - diameter) * 0.5, diameter, diameter);
}

-(CGRect) indicatorRect
{
    CGRect buttonRect = [self buttonRect];
    CGFloat borderSpace = self.borderWidth + self.borderSpacing;
    return CGRectInset(buttonRect, borderSpace, borderSpace);
}

-(CGPathRef) statePath
{
    return self.selected ? [self selectedStatePath] : [self deselectedStatePath];
}

-(CGPathRef) selectedStatePath
{
    CGRect indicatorRect = [self indicatorRect];
    return [self createPathInBounds:indicatorRect withRadiusPerc:0.32 roundingPerc:0.2];
}

-(CGPathRef) deselectedStatePath
{
    CGRect indicatorRect = [self indicatorRect];
    return [self createPathInBounds:indicatorRect withRadiusPerc:0.5 roundingPerc:0.5];
}

-(CGPathRef) createPathInBounds: (CGRect) bounds withRadiusPerc: (CGFloat) radius roundingPerc: (CGFloat) roundingPerc
{
    CGFloat width = CGRectGetWidth(bounds), height = CGRectGetHeight(bounds);
    CGFloat diameter = MIN(width, height);
    CGFloat R = diameter * radius, ER = R * roundingPerc;
    return [self createPathInBounds:bounds radius:R rounding:ER];
}

-(CGPathRef) createPathInBounds: (CGRect) bounds withRadiusPerc: (CGFloat) radius rounding: (CGFloat) roundingLevel
{
    CGFloat width = CGRectGetWidth(bounds), height = CGRectGetHeight(bounds);
    CGFloat diameter = MIN(width, height);
    CGFloat R = diameter * radius, ER = roundingLevel;
    return [self createPathInBounds:bounds radius:R rounding:ER];
}

-(CGPathRef) createPathInBounds: (CGRect) bounds radius: (CGFloat) R rounding: (CGFloat) ER
{
    CGFloat R1 = R - 2 * ER, CX = CGRectGetMidX(bounds), CY = CGRectGetMidY(bounds);
    CGMutablePathRef cgPath = CGPathCreateMutable();
    CGPathMoveToPoint(cgPath, NULL, CX - R1, CY - R);
    CGPathAddLineToPoint(cgPath, NULL, CX + R1, CY - R);
    CGPathAddCurveToPoint(cgPath, NULL, CX + R1 + ER, CY - R, CX + R, CY - R1 - ER, CX + R, CY - R1);
    CGPathAddLineToPoint(cgPath, NULL, CX + R, CY + R1);
    CGPathAddCurveToPoint(cgPath, NULL, CX + R, CY + R1 + ER, CX + R1 + ER, CY + R, CX + R1, CY + R);
    CGPathAddLineToPoint(cgPath, NULL, CX - R1, CY + R);
    CGPathAddCurveToPoint(cgPath, NULL, CX - R1 - ER, CY + R, CX - R, CY + R1 + ER, CX - R, CY + R1);
    CGPathAddLineToPoint(cgPath, NULL, CX - R, CY - R1);
    CGPathAddCurveToPoint(cgPath, NULL, CX - R, CY - R1 - ER, CX - R1 - ER, CY - R, CX - R1, CY - R);
    CGPathCloseSubpath(cgPath);
    CGPathRef outPath = CGPathCreateCopy(cgPath);
    CGPathRelease(cgPath);
    return outPath;
}

-(void)prepareForInterfaceBuilder
{
    self.borderWidth = 4;
    self.animationTime = 0.1;
    self.borderSpacing = 2;
}

-(void)dealloc
{
    @try {
        [self removeTarget:self action:@selector(onTouchUpInside:) forControlEvents:UIControlEventTouchUpInside];
        [self removeObserver:self forKeyPath:@"selected"];
    } @catch (NSException *exception) {
    }
}

@end
