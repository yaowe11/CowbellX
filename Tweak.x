#import <UIKit/UIKit.h>

@interface CCUICAPackageView : UIView
@property (nonatomic, copy) NSString *packageName;

- (void)cb_updateBatteryFillLayerInLayer:(CALayer *)parentLayer batteryLevel:(float)level;
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

    // 2. 读取系统当前真实电量
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    float level = [UIDevice currentDevice].batteryLevel;
    if (level < 0.0f) level = 1.0f;

    // 3. 动态更新系统原生 CAPackage 内部填充宽度
    [self cb_updateBatteryFillLayerInLayer:self.layer batteryLevel:level];

    // 4. 添加/更新底部百分比 Label（完全不移动系统图标）
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

%new
- (void)cb_updateBatteryFillLayerInLayer:(CALayer *)parentLayer batteryLevel:(float)level {
    for (CALayer *sublayer in parentLayer.sublayers) {
        NSString *layerName = sublayer.name ? sublayer.name : @"";
        
        if ([sublayer isKindOfClass:[CAShapeLayer class]] && 
           ([layerName containsString:@"fill"] || [layerName containsString:@"Fill"] || [layerName containsString:@"level"])) {
            
            CAShapeLayer *shapeLayer = (CAShapeLayer *)sublayer;
            CGRect bounds = shapeLayer.bounds;
            
            if (bounds.size.width > 0) {
                CGFloat maxW = bounds.size.width;
                CGFloat currentW = maxW * level;
                if (currentW < 1.0f) currentW = 1.0f;
                
                CGRect newFillRect = CGRectMake(0, 0, currentW, bounds.size.height);
                UIBezierPath *newPath = [UIBezierPath bezierPathWithRoundedRect:newFillRect cornerRadius:1.0f];
                shapeLayer.path = newPath.CGPath;
            }
        }
        
        if (sublayer.sublayers.count > 0) {
            [self cb_updateBatteryFillLayerInLayer:sublayer batteryLevel:level];
        }
    }
}

%end
