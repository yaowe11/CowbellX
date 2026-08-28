#import <UIKit/UIKit.h>

@interface CCUILabeledRoundButtonViewController : UIViewController
@property (nonatomic, retain) UIImageView *glyphImageView;
- (void)updateBatteryIcon;
@end

// 动态绘制 1% 精细度的电池图标
static UIImage *DrawCustomBatteryImage(float level, BOOL isCharging) {
    CGSize size = CGSizeMake(28, 14);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull rendererContext) {
        CGContextRef ctx = rendererContext.CGContext;
        
        // 1. 绘制电池外框
        CGRect outerRect = CGRectMake(1, 1, 22, 12);
        UIBezierPath *outerPath = [UIBezierPath bezierPathWithRoundedRect:outerRect cornerRadius:3];
        [[UIColor whiteColor] setStroke];
        outerPath.lineWidth = 1.5;
        [outerPath stroke];
        
        // 2. 绘制电池正极凸起头
        CGRect tipRect = CGRectMake(24, 4.5, 2, 5);
        UIBezierPath *tipPath = [UIBezierPath bezierPathWithRoundedRect:tipRect cornerRadius:1];
        [[UIColor whiteColor] setFill];
        [tipPath fill];
        
        // 3. 动态绘制内部电量填充（精确到 1%）
        float percentage = fmaxf(0.0f, fminf(1.0f, level));
        float maxFillWidth = 18.0f; // 内部最大可填充宽度
        float fillWidth = maxFillWidth * percentage;
        
        if (fillWidth > 0.5f) {
            CGRect fillRect = CGRectMake(3, 3, fillWidth, 8);
            UIBezierPath *fillPath = [UIBezierPath bezierPathWithRoundedRect:fillRect cornerRadius:1.5];
            
            // 低电量标红，平时标白
            if (percentage <= 0.20f) {
                [[UIColor systemRedColor] setFill];
            } else {
                [[UIColor whiteColor] setFill];
            }
            [fillPath fill];
        }
        
        // 4. 如果在充电，绘制闪电符号
        if (isCharging) {
            UIBezierPath *boltPath = [UIBezierPath bezierPath];
            [boltPath moveToPoint:CGPointMake(13, 2)];
            [boltPath addLineToPoint:CGPointMake(8, 7.5)];
            [boltPath addLineToPoint:CGPointMake(11.5, 7.5)];
            [boltPath addLineToPoint:CGPointMake(10, 12)];
            [boltPath addLineToPoint:CGPointMake(15, 6.5)];
            [boltPath addLineToPoint:CGPointMake(11.5, 6.5)];
            [boltPath closePath];
            
            [[UIColor systemYellowColor] setFill];
            [boltPath fill];
        }
    }];
}

static void UpdateGlyphForButton(id buttonController) {
    if (!buttonController) return;

    UIImageView *imageView = nil;
    if ([buttonController respondsToSelector:@selector(glyphImageView)]) {
        imageView = [buttonController glyphImageView];
    } else if ([buttonController isKindOfClass:[UIViewController class]]) {
        UIViewController *vc = (UIViewController *)buttonController;
        if ([vc.view respondsToSelector:@selector(glyphImageView)]) {
            imageView = [(id)vc.view glyphImageView];
        }
    }

    if (!imageView) return;

    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    float batteryLevel = [UIDevice currentDevice].batteryLevel;
    BOOL isCharging = ([UIDevice currentDevice].batteryState == UIDeviceBatteryStateCharging || 
                        [UIDevice currentDevice].batteryState == UIDeviceBatteryStateFull);

    // 绘制并替换原生图标
    UIImage *customBattery = DrawCustomBatteryImage(batteryLevel, isCharging);
    if (customBattery) {
        imageView.image = customBattery;
        imageView.contentMode = UIViewContentModeCenter;
    }
}

%hook CCUILabeledRoundButtonViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIDeviceBatteryLevelDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIDeviceBatteryStateDidChangeNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(updateBatteryIcon) 
                                                 name:UIDeviceBatteryLevelDidChangeNotification 
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(updateBatteryIcon) 
                                                 name:UIDeviceBatteryStateDidChangeNotification 
                                               object:nil];
    [self updateBatteryIcon];
}

%new
- (void)updateBatteryIcon {
    UpdateGlyphForButton(self);
}

%end
