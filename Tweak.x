#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

@interface CCUICAPackageView : UIView
- (void)setStateName:(NSString *)stateName;
@end

// 精准对内部 Fill 图层施加 Mask，杜绝外层大容器被误伤导致跑偏
static void cb_applyMaskFill(CALayer *layer, float level) {
    if (!layer || !layer.sublayers) return;

    for (CALayer *sub in layer.sublayers) {
        NSString *name = sub.name.lowercaseString;

        // 1. 过滤掉外框、极耳和容器大图层（避免整个模块变大/错位）
        BOOL isBorderOrCap = name && ([name containsString:@"cap"] || [name containsString:@"tip"] || [name containsString:@"border"] || [name containsString:@"body"] || [name containsString:@"outline"]);
        BOOL isTooLargeContainer = (sub.bounds.size.width > 35 || sub.bounds.size.height > 25);

        // 2. 判断是否为内部填充图层
        BOOL isFill = name && ([name containsString:@"fill"] || [name containsString:@"capacity"] || [name containsString:@"level"]);
        if (!isFill && !isBorderOrCap && !isTooLargeContainer && sub.bounds.size.width >= 10 && sub.bounds.size.width <= 32 && sub.bounds.size.height >= 4) {
            isFill = YES;
        }

        // 3. 只对真正的内部填充块套用 Mask
        if (isFill && !isBorderOrCap && !isTooLargeContainer) {
            [CATransaction begin];
            [CATransaction setDisableActions:YES]; // 禁用 CoreAnimation 自动过度

            CAShapeLayer *mask = (CAShapeLayer *)sub.mask;
            if (!mask || ![mask isKindOfClass:[CAShapeLayer class]]) {
                mask = [CAShapeLayer layer];
                sub.mask = mask;
            }

            // 从左到右严格按电量百分比计算遮罩宽度
            CGFloat maskWidth = sub.bounds.size.width * level;
            CGRect maskRect = CGRectMake(0, 0, maskWidth, sub.bounds.size.height);

            mask.path = [UIBezierPath bezierPathWithRect:maskRect].CGPath;
            mask.fillColor = [UIColor blackColor].CGColor;

            [CATransaction commit];
            return; // 命中填充块后直接结束，不再向下误伤
        }

        cb_applyMaskFill(sub, level);
    }
}

static void cb_updateLowPowerIcon(CCUICAPackageView *view) {
    // 判断响应链，保证作用范围只在低电量模块
    UIResponder *r = view;
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

    // 获取真实电量 (范围 0.05 ~ 1.0)
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    float level = [UIDevice currentDevice].batteryLevel;
    if (level < 0) level = 1.0f;
    if (level < 0.05f) level = 0.05f;

    cb_applyMaskFill(view.layer, level);
}

%hook CCUICAPackageView

- (void)layoutSubviews {
    %orig;
    cb_updateLowPowerIcon(self);
}

- (void)setStateName:(NSString *)stateName {
    %orig(stateName);

    // 拦截点按切换，避免 State 切换动画重置 Mask
    __weak CCUICAPackageView *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (weakSelf) {
            cb_updateLowPowerIcon(weakSelf);
        }
    });
}

%end
