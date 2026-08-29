#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

@interface CCUICAPackageView : UIView
@property (nonatomic, copy) NSString *packageName;
@end

static void cb_updateBatteryFill(CALayer *layer, float level) {
    if (!layer || !layer.sublayers) return;

    for (CALayer *sub in layer.sublayers) {
        NSString *name = sub.name.lowercaseString;

        // 过滤外框、边界和极耳
        BOOL isBorderOrCap = name && ([name containsString:@"cap"] || [name containsString:@"tip"] || [name containsString:@"border"] || [name containsString:@"body"] || [name containsString:@"outline"]);

        // 识别电池内部填充图层
        BOOL isFillLayer = name && ([name containsString:@"fill"] || [name containsString:@"capacity"] || [name containsString:@"level"]);
        if (!isFillLayer && !isBorderOrCap && sub.bounds.size.width >= 10 && sub.bounds.size.width <= 32 && sub.bounds.size.height >= 4) {
            isFillLayer = YES;
        }

        if (isFillLayer && !isBorderOrCap) {
            [CATransaction begin];
            [CATransaction setDisableActions:YES];

            // 1. 先进行 X 轴比例缩放
            CATransform3D scale = CATransform3DMakeScale(level, 1.0, 1.0);

            // 2. 核心数学修正：由于默认从中心缩放，左边会缩进去 (1 - level)/2 的宽度
            // 只需要向左平移这个差值，就能做到 100% 完美的左对齐，完全不破坏 anchorPoint 和坐标轴！
            CGFloat xOffset = -((sub.bounds.size.width * (1.0f - level)) / 2.0f);
            sub.transform = CATransform3DTranslate(scale, xOffset / level, 0, 0);

            [CATransaction commit];
            return;
        }

        cb_updateBatteryFill(sub, level);
    }
}

%hook CCUICAPackageView

- (void)layoutSubviews {
    %orig;

    // 1. 严格过滤响应链，杜绝误伤亮度、声音等其他控制中心图标！
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

    if (!isLowPower) return; // 不是低电量模块直接跳过

    // 2. 读取真实电量
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    float level = [UIDevice currentDevice].batteryLevel;
    if (level < 0) level = 1.0f;
    if (level < 0.05f) level = 0.05f;

    cb_updateBatteryFill(self.layer, level);
}

%end
