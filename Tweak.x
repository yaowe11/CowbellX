#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

@interface CCUICAPackageView : UIView
@property (nonatomic, copy) NSString *packageName;
@end

// 使用 Mask 遮罩控制宽度，避免修改 anchorPoint 导致的坐标错位和长条动画
static void cb_applyMaskFill(CALayer *layer, float level) {
    if (!layer || !layer.sublayers) return;

    for (CALayer *sub in layer.sublayers) {
        NSString *name = sub.name.lowercaseString;

        // 过滤外框和极耳
        BOOL isBorderOrCap = name && ([name containsString:@"cap"] || [name containsString:@"tip"] || [name containsString:@"border"] || [name containsString:@"body"] || [name containsString:@"outline"]);

        // 判定填充图层
        BOOL isFill = name && ([name containsString:@"fill"] || [name containsString:@"capacity"] || [name containsString:@"level"]);
        if (!isFill && !isBorderOrCap && sub.bounds.size.width >= 10 && sub.bounds.size.width <= 30 && sub.bounds.size.height >= 5) {
            isFill = YES;
        }

        if (isFill && !isBorderOrCap) {
            [CATransaction begin];
            [CATransaction setDisableActions:YES]; // 关掉 CoreAnimation 自动过度

            // 如果没有创建过自定义 mask，则添加一个
            if (!sub.mask) {
                CALayer *maskLayer = [CALayer layer];
                maskLayer.backgroundColor = [UIColor blackColor].CGColor;
                sub.mask = maskLayer;
            }

            // 获取原始尺寸，严格按电量百分比计算遮罩宽度
            CGRect fullBounds = sub.bounds;
            sub.mask.frame = CGRectMake(0, 0, fullBounds.size.width * level, fullBounds.size.height);

            [CATransaction commit];
        }

        cb_applyMaskFill(sub, level);
    }
}

%hook CCUICAPackageView

- (void)layoutSubviews {
    %orig;

    // 获取真实电量 (范围 0.05 ~ 1.0)
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    float level = [UIDevice currentDevice].batteryLevel;
    if (level < 0) level = 1.0f;
    if (level < 0.05f) level = 0.05f;

    // 判断响应链，保证作用范围只在低电量模块
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

    if (isLowPower) {
        cb_applyMaskFill(self.layer, level);
    }
}

- (void)setState:(NSString *)state animated:(BOOL)animated {
    %orig;

    // 当用户点按开关触发切换动画后，再次刷新 Mask 宽度
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    float level = [UIDevice currentDevice].batteryLevel;
    if (level < 0) level = 1.0f;
    if (level < 0.05f) level = 0.05f;

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

    if (isLowPower) {
        dispatch_async(dispatch_get_main_queue(), ^{
            cb_applyMaskFill(self.layer, level);
        });
    }
}

%end
