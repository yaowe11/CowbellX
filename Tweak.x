#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

%hook CCUICAPackageView

- (void)layoutSubviews {
    %orig;

    // 判断是不是低电量模块里的 PackageView
    UIResponder *responder = self;
    BOOL isLowPower = NO;
    while (responder) {
        if ([NSStringFromClass([responder class]) containsString:@"LowPower"]) {
            isLowPower = YES;
            break;
        }
        responder = responder.nextResponder;
    }

    if (isLowPower) {
        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        float level = [UIDevice currentDevice].batteryLevel;
        if (level < 0) level = 1.0f;

        // 直接向 CA Package 内部的电池 Layer 注入电量进度 (0.0 - 1.0)
        // 原生 Package 内部用于控制填充度的 KeyPath 通常为 fill / level
        [self.layer setValue:@(level) forKeyPath:@"publishedObjects.fill.strokeEnd"];
    }
}

%end
