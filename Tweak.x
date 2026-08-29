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

    // 2. 读取当前真实电量
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    float level = [UIDevice currentDevice].batteryLevel;
    if (level < 0.0f) level = 1.0f; // 模拟器或异常时默认 100%

    // 3. 递归遍历子图层，找到控制电池内部填充的 CAShapeLayer 并更新其 Path
    [self cb_updateBatteryFillLayerInLayer:self.layer batteryLevel:level];

    // 4. 整体微调 Package 偏移（向上平移 4pt 给底部百分比留空间）
    for (UIView *sub in self.subviews) {
        if (sub.tag != 8888) {
            sub.transform = CGAffineTransformMakeTranslation(0, -4.0f);
        }
    }

    // 5. 添加/更新底部百分比 Label
    UILabel *label = [self viewWithTag:8888];
    if (!label) {
        label = [[UILabel alloc] init];
        label.tag = 8888;
        label.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightRegular];
        label.textColor = [UIColor whiteColor];
        label.textAlignment = NSTextAlignmentCenter;
        [self addSubview:label];
    }

    label.text = [NSString stringWithFormat:@"%d%%", (int)(level * 100)];
    CGFloat labelH = 13.0f;
    label.frame = CGRectMake(0, self.bounds.size.height - labelH - 6.0f, self.bounds.size.width, labelH);
}

// 递归遍历 Layer 寻找电池填充 Layer
%new
- (void)cb_updateBatteryFillLayerInLayer:(CALayer *)parentLayer batteryLevel:(float)level {
    for (CALayer *sublayer in parentLayer.sublayers) {
        // 系统 CAPackage 的电池填充图层通常带有 "fill" 或 "Fill" 命名标识
        NSString *layerName = sublayer.name ? sublayer.name : @"";
        
        if ([sublayer isKindOfClass:[CAShapeLayer class]] && 
           ([layerName containsString:@"fill"] || [layerName containsString:@"Fill"] || [layerName containsString:@"level"])) {
            
            CAShapeLayer *shapeLayer = (CAShapeLayer *)sublayer;
            CGRect bounds = shapeLayer.bounds;
            
            if (bounds.size.width > 0) {
                // 根据实际电量百分比计算新的填充宽度
                CGFloat maxW = bounds.size.width;
                CGFloat currentW = maxW * level;
                if (currentW < 1.0f) currentW = 1.0f;
                
                // 重新绘制并替换 Path
                CGRect newFillRect = CGRectMake(0, 0, currentW, bounds.size.height);
                UIBezierPath *newPath = [UIBezierPath bezierPathWithRoundedRect:newFillRect cornerRadius:1.0f];
                shapeLayer.path = newPath.CGPath;
            }
        }
        
        // 继续向下递归找深层 Layer
        if (sublayer.sublayers.count > 0) {
            [self cb_updateBatteryFillLayerInLayer:sublayer batteryLevel:level];
        }
    }
}

%end
