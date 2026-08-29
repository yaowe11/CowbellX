#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

@interface CCUICAPackageView : UIView
@end

@interface CCUILowPowerModeToggle : NSObject
- (CCUICAPackageView *)packageView;
@end

// 静态 C 函数递归遍历图层并进行缩放
static void cb_applyBatteryLevel(float level, CALayer *layer) {
    if (!layer || !layer.sublayers) return;

    for (CALayer *sub in layer.sublayers) {
        NSString *name = sub.name.lowercaseString;

        BOOL isBorderOrCap = name && ([name containsString:@"cap"] || [name containsString:@"tip"] || [name containsString:@"border"] || [name containsString:@"body"] || [name containsString:@"outline"]);
        
        // 核心：直接对内部填充图层进行 transform 横向缩放
        if (!isBorderOrCap && sub.bounds.size.width >= 8 && sub.bounds.size.width <= 30) {
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            sub.transform = CATransform3DMakeScale(level, 1.0, 1.0);
            [CATransaction commit];
        }

        cb_applyBatteryLevel(level, sub);
    }
}

%hook CCUILowPowerModeToggle

- (void)containerViewWillLayoutSubviews {
    %orig;

    // 1. 获取控制中心低电量按钮对应的 PackageView
    CCUICAPackageView *pkgView = nil;
    if ([self respondsToSelector:@selector(packageView)]) {
        pkgView = [self packageView];
    }
    
    if (!pkgView) return;

    // 2. 获取手机真实电量
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    float level = [UIDevice currentDevice].batteryLevel;
    if (level < 0) level = 1.0f;
    if (level < 0.05f) level = 0.05f;

    // 3. 执行缩放
    cb_applyBatteryLevel(level, pkgView.layer);
}

%end
