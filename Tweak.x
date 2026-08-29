#import <UIKit/UIKit.h>

@interface CCUICAPackageView : UIView
@property (nonatomic, copy) NSString *packageName;

// 解决编译报错：在此处声明自定义的递归更新方法
- (void)cb_updateBatteryFillLayerInLayer:(CALayer *)parentLayer batteryLevel:(float)level;
@end

%hook CCUICAPackageView

- (void)layoutSubviews {
    %orig;

    // 1. 精准识别低电量模式 Toggle，防止误伤其他控制中心图标
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

    // 2. 读取系统当前真实电量 (0.0 ~ 1.0)
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    float level = [UIDevice currentDevice].batteryLevel;
    if (level < 0.0f) level = 1.0f; // 模拟器或未获取到时默认按 100% 处理

    // 3. 动态更新系统原生 CAPackage 内部的 CAShapeLayer 填充宽度
    [self cb_updateBatteryFillLayerInLayer:self.layer batteryLevel:level];

    // 4. 整体将 Package 图层向上平移 4pt，给底部的百分比数字留出完美居中空间
    for (UIView *sub in self.subviews) {
        if (sub.tag != 8888) {
            sub.transform = CGAffineTransformMakeTranslation(0, -4.0f);
        }
    }

    // 5. 添加/更新底部 Cowbell 风格的百分比 Label
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
    label.frame = CGRectMake(0, self.bounds.size.height - labelH
