#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

// 辅助方法：判断响应者链是否属于低电量模块
static BOOL CBIsLowPowerModule(UIView *view) {
    UIResponder *responder = view;
    while (responder) {
        NSString *clsName = NSStringFromClass([responder class]);
        if ([clsName containsString:@"LowPower"] || [clsName containsString:@"Battery"]) {
            return YES;
        }
        responder = responder.nextResponder;
    }
    return NO;
}

// 核心裁切逻辑：给 View 加上按真实电量裁剪的 Mask
static void CBApplyBatteryLevelMask(UIView *view) {
    if (!view) return;

    // 获取系统真实电量 (0.0 ~ 1.0)
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    float level = [UIDevice currentDevice].batteryLevel;
    if (level < 0) level = 1.0f; // 异常默认 100%
    if (level < 0.08f) level = 0.08f; // 留出最少电量可见度

    // 找到尺寸在 20~40 之间的核心图标 View（即电池图标本身）
    if (view.bounds.size.width >= 20 && view.bounds.size.width <= 45) {
        CALayer *maskLayer = view.layer.mask;
        if (!maskLayer) {
            maskLayer = [CALayer layer];
            maskLayer.backgroundColor = [UIColor blackColor].CGColor;
            view.layer.mask = maskLayer;
        }

        // 仅在宽度方向按电量比例裁剪
        CGRect bounds = view.bounds;
        CGRect maskFrame = CGRectMake(0, 0, bounds.size.width * level, bounds.size.height);

        [CATransaction begin];
        [CATransaction setDisableActions:NO];
        [CATransaction setAnimationDuration:0.25];
        maskLayer.frame = maskFrame;
        [CATransaction commit];
    }
}

// ------------------- Hook 1: CAPackageView -------------------
@interface CCUICAPackageView : UIView
@end

%hook CCUICAPackageView

- (void)layoutSubviews {
    %orig;
    if (CBIsLowPowerModule(self)) {
        CBApplyBatteryLevelMask(self);
    }
}

%end

// ------------------- Hook 2: UIImageView -------------------
%hook UIImageView

- (void)layoutSubviews {
    %orig;
    if (CBIsLowPowerModule(self)) {
        CBApplyBatteryLevelMask(self);
    }
}

%end
