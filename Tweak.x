#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

@interface CCUICAPackageView : UIView
@property (nonatomic, copy) NSString *packageName;
@end

static void cb_applyMaskToFillLayer(CALayer *layer, float level) {
    if (!layer || !layer.sublayers) return;

    for (CALayer *sub in layer.sublayers) {
        NSString *name = sub.name.lowercaseString;

        // 过滤外框、边界和极耳
        BOOL isBorderOrCap = name && ([name containsString:@"cap"] || [name containsString:@"tip"] || [name containsString:@"border"] || [name containsString:@"body"] || [name containsString:@"outline"]);

        // 识别电池内部真正的填充图层
        BOOL isFillLayer = name && ([name containsString:@"fill"] || [name containsString:@"capacity"] || [name containsString:@"level"]);
        if (!isFillLayer && !isBorderOrCap && sub.bounds.size.width >= 10 && sub.bounds.size.width <= 32 && sub.bounds.size.height >= 4) {
            isFillLayer = YES;
        }

        if (isFillLayer && !isBorderOrCap) {
            [CATransaction begin];
            [CATransaction setDisableActions:YES];

            CAShapeLayer *mask = (CAShapeLayer *)sub.mask;
            if (!mask || ![mask isKindOfClass:[CAShapeLayer class]]) {
                mask = [CAShapeLayer layer];
                sub.mask = mask;
            }

            // 修正：内部填充条在 100% 满电时需要撑满整个 Layer bounds
            // 避免 bounds 宽于内部 path 导致的比例偏小问题
            CGFloat fullWidth = sub.bounds.size.width;
            
            // 真实电量比例裁剪宽度
            CGFloat maskWidth = fullWidth * level;
            
            // 保证低电量时最低保留可读宽度，满电时 100% 贴合右边框
            if (level >= 0.98f) {
                maskWidth = fullWidth; // 满电/接近满电直接填满，不留右侧缝隙
            } else if (maskWidth < 2.0f) {
                maskWidth = 2.0f;
            }

            CGRect maskRect = CGRectMake(0, 0, maskWidth, sub.bounds.size.height);
            mask.path = [UIBezierPath bezierPathWithRect:maskRect].CGPath;
            mask.fillColor = [UIColor blackColor].CGColor;

            sub.transform = CATransform3DIdentity;

            [CATransaction commit];
            return;
        }

        cb_applyMaskToFillLayer(sub, level);
    }
}

%hook CCUICAPackageView

- (void)layoutSubviews {
    %orig;

    NSString *pkgName = @"";
    if ([self respondsToSelector:@selector(packageName)]) {
        pkgName = self.packageName ? self.packageName : @"";
    }

    BOOL isLowPower = [pkgName containsString:@"LowPower"] || [pkgName containsString:@"Battery"];

    if (!isLowPower) {
        UIResponder *r = self;
        while (r) {
            NSString *cls = NSStringFromClass([r class]);
            if ([cls containsString:@"Brightness"] || [cls containsString:@"Display"]) {
                return;
            }
            if ([cls containsString:@"LowPower"]) {
                isLowPower = YES;
                break;
            }
            r = r.nextResponder;
        }
    }

    if (!isLowPower) return;

    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    float level = [UIDevice currentDevice].batteryLevel;
    if (level < 0) level = 1.0f;

    cb_applyMaskToFillLayer(self.layer, level);
}

%end
