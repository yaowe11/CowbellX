#import <UIKit/UIKit.h>

@interface CCUICAPackageView : UIView
@property (nonatomic, copy) NSString *packageName;
@end

%hook CCUICAPackageView

- (void)layoutSubviews {
    %orig;

    // 1. 精准识别低电量模式 Toggle
    NSString *pkgName = @"";
    if ([self respondsToSelector:@selector(packageName)]) {
        pkgName = self.packageName ? self.packageName : @"";
    }

    BOOL isLowPower = [pkgName containsString:@"LowPower"] || [pkgName containsString:@"Battery"];

    if (!isLowPower) {
        UIResponder *r = self;
        while (r) {
            NSString *cls = NSStringFromClass([r class]);
            if ([cls containsString:@"Brightness"] || [cls containsString:@"Display"]) return;
            if ([cls containsString:@"LowPower"]) {
                isLowPower = YES;
                break;
            }
            r = r.nextResponder;
        }
    }

    if (!isLowPower) return;

    // 2. 获取真实电量 (0.0 ~ 1.0)
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    float level = [UIDevice currentDevice].batteryLevel;
    if (level < 0.0f) level = 1.0f;

    // 3. 寻找原生 CAPackage 里的电池填充 Layer，并进行左对齐 X 轴比例缩放
    [self cb_scaleNativeBatteryFillInLayer:self.layer batteryLevel:level];

    // 4. 底部挂载百分比 Label
    UILabel *label = [self viewWithTag:8888];
    if (!label) {
        label = [[UILabel alloc] init];
        label.tag = 8888;
        label.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightRegular];
        label.textColor = [UIColor whiteColor];
        label.textAlignment = NSTextAlignmentCenter;
        [self addSubview:label];
    }

    label.text = [NSString stringWithFormat:@"%d%%", (int)(level * 100.0f)];
    CGFloat labelH = 13.0f;
    label.frame = CGRectMake(0, self.bounds.size.height - labelH - 6.0f, self.bounds.size.width, labelH);
}

%new
- (void)cb_scaleNativeBatteryFillInLayer:(CALayer *)parentLayer batteryLevel:(float)level {
    for (CALayer *sublayer in parentLayer.sublayers) {
        NSString *layerName = sublayer.name ? sublayer.name : @"";

        // 精准匹配系统 CAPackage 内部的 Fill/Level 图层
        if ([layerName containsString:@"fill"] || [layerName containsString:@"Fill"] || [layerName containsString:@"level"]) {
            
            // 设置锚点为左侧中心 (0, 0.5)，确保从左往右等比例缩放，不改变高度和圆角
            if (sublayer.anchorPoint.x != 0.0f) {
                sublayer.anchorPoint = CGPointMake(0.0f, 0.5f);
                // 修正因修改 anchorPoint 导致的坐标偏移
                CGRect frame = sublayer.frame;
                frame.origin.x -= frame.size.width * 0.5f;
                sublayer.frame = frame;
            }

            // 仅在 X 轴（宽度方向）进行电量比例缩放，Y 轴保持原生 1.0 不变
            sublayer.transform = CATransform3DMakeScale(level, 1.0f, 1.0f);
        }

        if (sublayer.sublayers.count > 0) {
            [self cb_scaleNativeBatteryFillInLayer:sublayer batteryLevel:level];
        }
    }
}

%end
