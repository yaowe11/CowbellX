#import <UIKit/UIKit.h>

@interface CCUILabeledRoundButtonViewController : UIViewController
@property (nonatomic, retain) UIImageView *glyphImageView;
- (void)updateBatteryIcon;
@end

static UIImage *DrawNativeStyleBattery(float level) {
    CGSize size = CGSizeMake(26, 13);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull rendererContext) {
        CGContextRef ctx = rendererContext.CGContext;
        
        // 1. 绘制原生标准外框
        CGRect outerRect = CGRectMake(1, 1, 21, 11);
        UIBezierPath *outerPath = [UIBezierPath bezierPathWithRoundedRect:outerRect cornerRadius:3.5];
        [[UIColor whiteColor] setStroke];
        outerPath.lineWidth = 1.25;
        [outerPath stroke];
        
        // 2. 绘制电池正极头
        CGRect tipRect = CGRectMake(23, 4, 1.5, 5);
        UIBezierPath *tipPath = [UIBezierPath bezierPathWithRoundedRect:tipRect cornerRadius:0.75];
        [[UIColor whiteColor] setFill];
        [tipPath fill];
        
        // 3. 按 1% 精确比例平滑填充内部（纯白）
        float percentage = fmaxf(0.0f, fminf(1.0f, level));
        float maxFillWidth = 17.0f; 
        float fillWidth = maxFillWidth * percentage;
        
        if (fillWidth > 0.5f) {
            CGRect fillRect = CGRectMake(3, 3, fillWidth, 7);
            UIBezierPath *fillPath = [UIBezierPath bezierPathWithRoundedRect:fillRect cornerRadius:1.5];
            [[UIColor whiteColor] setFill];
            [fillPath fill];
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

    // 替换为纯粹的原生动态填充图像
    UIImage *batteryImage = DrawNativeStyleBattery(batteryLevel);
    if (batteryImage) {
        imageView.image = batteryImage;
        imageView.contentMode = UIViewContentModeCenter;
    }
}

%hook CCUILabeledRoundButtonViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIDeviceBatteryLevelDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(updateBatteryIcon) 
                                                 name:UIDeviceBatteryLevelDidChangeNotification 
                                               object:nil];
    [self updateBatteryIcon];
}

%new
- (void)updateBatteryIcon {
    UpdateGlyphForButton(self);
}

%end
