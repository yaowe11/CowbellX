#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

@interface CCUICAPackageView : UIView
@property (nonatomic, copy) NSString *packageName;
- (void)cb_applyLevel:(float)level toLayer:(CALayer *)layer;
@end

%hook CCUICAPackageView

- (void)layoutSubviews {
    %orig;

    // 1. 安全过滤包名，避免崩溃
    NSString *pkg = nil;
    @try {
        if ([self respondsToSelector:@selector(packageName)]) {
            pkg = self.packageName;
        }
    } @catch (NSException *e) {}

    if (!pkg || (![pkg containsString:@"Battery"] && ![pkg containsString:@"LowPower"])) {
        return;
    }

    // 2. 获取手机当前真实电量
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    float level = [UIDevice currentDevice].batteryLevel;
    if (level < 0) level = 1.0f;
    if (level < 0.05f) level = 0.05f;

    // 3. 执行修改
    [self cb_applyLevel:level toLayer:self.layer];
}

%new
- (void)cb_applyLevel:(float)level toLayer:(CALayer *)layer {
    if (!layer || !layer.sublayers) return;

    for (CALayer *sub in layer.sublayers) {
        NSString *name = sub.name.lowercaseString;

        BOOL isBorderOrCap = name && ([name containsString:@"cap"] || [name containsString:@"tip"] || [name containsString:@"border"] || [name containsString:@"body"] || [name containsString:@"outline"]);
        BOOL isFill = name && ([name containsString:@"fill"] || [name containsString:@"level"] || [name containsString:@"capacity"] || [name containsString:@"content"]);

        if (isFill && !isBorderOrCap) {
            // 直接动态调整 frame 宽度，不再使用 mask 遮罩
            CGRect rect = sub.bounds;
            if (rect.size.width > 0) {
                [CATransaction begin];
                [CATransaction setDisableActions:YES];
                sub.bounds = CGRectMake(rect.origin.x, rect.origin.y, rect.size.width * level, rect.size.height);
                [CATransaction commit];
            }
        }

        [self cb_applyLevel:level toLayer:sub];
    }
}

%end
