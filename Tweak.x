#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

@interface CCUICAPackageView : UIView
@property (nonatomic, copy) NSString *packageName;
@end

// 静态 C 函数：精准只改低电量内部填充
static void cb_fixBatteryFill(CALayer *layer, float level) {
    if (!layer || !layer.sublayers) return;

    for (CALayer *sub in layer.sublayers) {
        NSString *name = sub.name.lowercaseString;

        // 1. 严格过滤掉外框(body/border)和极耳(cap/tip)
        BOOL isBorderOrCap = name && ([name containsString:@"cap"] || [name containsString:@"tip"] || [name containsString:@"border"] || [name containsString:@"body"] || [name containsString:@"outline"]);

        // 2. 只有明确是 fill / capacity / level，或者在低电量 View 内部特定宽度的块才处理
        BOOL isFill = name && ([name containsString:@"fill"] || [name containsString:@"capacity"] || [name containsString:@"level"]);
        if (!isFill && !isBorderOrCap && sub.bounds.size.width >= 12 && sub.bounds.size.width <= 28) {
            isFill = YES;
        }

        if (isFill && !isBorderOrCap) {
            [CATransaction begin];
            [CATransaction setDisableActions:YES]; // 禁用过度动画
            
            // 修正锚点为左中点 (0, 0.5)，使缩放时左边固定，只改变右侧长度
            if (sub.anchorPoint.x != 0.0f) {
                CGRect oldFrame = sub.frame;
                sub.anchorPoint = CGPointMake(0.0f, 0.5f);
                sub.frame = oldFrame; // 重新赋值 frame 保持原有相对位置不变
            }
            
            // 按照电量比例横向缩放
            sub.transform = CATransform3DMakeScale(level, 1.0f, 1.0f);
            [CATransaction commit];
        }

        cb_fixBatteryFill(sub, level);
    }
}

%hook CCUICAPackageView

- (void)layoutSubviews {
    %orig;

    // 严密防线：判断只有包含低电量包名时才执行修改，防止影响其他图标
    BOOL isBattery = NO;
    if ([self respondsToSelector:@selector(packageName)]) {
        NSString *pkg = self.packageName;
        if (pkg && ([pkg containsString:@"Battery"] || [pkg containsString:@"LowPower"])) {
            isBattery = YES;
        }
    }
    
    // 如果没有 packageName，通过检查 responder 链判断父类控制器
    if (!isBattery) {
        UIResponder *r = self;
        while (r) {
            NSString *cls = NSStringFromClass([r class]);
            if ([cls containsString:@"LowPower"] || [cls containsString:@"Battery"]) {
                isBattery = YES;
                break;
            }
            r = r.nextResponder;
        }
    }

    // 不是低电量图标则直接跳过，防止误伤其他控制中心模块
    if (!isBattery) return;

    // 获取真实电量
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    float level = [UIDevice currentDevice].batteryLevel;
    if (level < 0) level = 1.0f;
    if (level < 0.05f) level = 0.05f;

    cb_fixBatteryFill(self.layer, level);
}

%end
