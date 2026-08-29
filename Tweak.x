#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

@interface CCUICAPackageView : UIView
@property (nonatomic, copy) NSString *packageName;
- (void)setStateName:(NSString *)stateName;
@end

// 精准锁定并裁剪低电量图标的电量条
static void cb_applyStrictBatteryMask(CALayer *layer, float level) {
    if (!layer || !layer.sublayers) return;

    for (CALayer *sub in layer.sublayers) {
        NSString *name = sub.name.lowercaseString;

        // 1. 排除外边框和电池头
        BOOL isBorderOrCap = name && ([name containsString:@"cap"] || [name containsString:@"tip"] || [name containsString:@"border"] || [name containsString:@"body"] || [name containsString:@"outline"]);

        // 2. 寻找填充图层
        BOOL isFill = name && ([name containsString:@"fill"] || [name containsString:@"capacity"] || [name containsString:@"level"]);
        if (!isFill && !isBorderOrCap && sub.bounds.size.width >= 10 && sub.bounds.size.width <= 32 && sub.bounds.size.height >= 4) {
            isFill = YES;
        }

        if (isFill && !isBorderOrCap) {
            // 使用 CAShapeLayer 作为 Mask
            CAShapeLayer *mask = (CAShapeLayer *)sub.mask;
            if (!mask || ![mask isKindOfClass:[CAShapeLayer class]]) {
                mask = [CAShapeLayer layer];
                sub.mask = mask;
            }

            // 从左向右精准裁剪到真实电量比例
            CGFloat maskWidth = sub.bounds.size.width * level;
            CGRect maskRect = CGRectMake(0, 0, maskWidth, sub.bounds.size.height);

            [CATransaction begin];
            [CATransaction setDisableActions:YES]; // 禁用 CoreAnimation 自动过度
            mask.path = [UIBezierPath bezierPathWithRect:maskRect].CGPath;
            mask.fillColor = [UIColor blackColor].CGColor;
            [CATransaction commit];
        }

        cb_applyStrictBatteryMask(sub, level);
    }
}

%hook CCUICAPackageView

- (void)layoutSubviews {
    %orig;

    // 检查响应链，锁定低电量模块
    UIResponder *r = self;
    BOOL isLowPower = NO;
    while (r) {
        NSString *cls = NSStringFromClass([r class]);
        if ([cls containsString:@"LowPower"] || [cls containsString:@"Battery"]) {
            isLowPower = YES;
            break;
        }
        r = r.nextResponder;
    }

    if (!isLowPower) return;

    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    float level = [UIDevice currentDevice].batteryLevel;
    if (level < 0) level = 1.0f;
    if (level < 0.05f) level = 0.05f;

    cb_applyStrictBatteryMask(self.layer, level);
}

- (void)setStateName:(NSString *)stateName {
    %orig(stateName);

    UIResponder *r = self;
    BOOL isLowPower = NO;
    while (r) {
        NSString *cls = NSStringFromClass([r class]);
        if ([cls containsString:@"LowPower"] || [cls containsString:@"Battery"]) {
            isLowPower = YES;
            break;
        }
        r = r.nextResponder;
    }

    if (!isLowPower) return;

    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    float level = [UIDevice currentDevice].batteryLevel;
    if (level < 0) level = 1.0f;
    if (level < 0.05f) level = 0.05f;

    // 安全获取弱引用 Layer，防止 Block 内存问题
    __weak CALayer *weakLayer = self.layer;
    [CATransaction begin];
    [CATransaction setCompletionBlock:^{
        if (weakLayer) {
            cb_applyStrictBatteryMask(weakLayer, level);
        }
    }];
    [CATransaction commit];
}

%end
