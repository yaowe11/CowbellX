#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

@interface CCUICAPackageView : UIView
@property (nonatomic, copy) NSString *packageName;
- (id)publishedObjectWithName:(NSString *)name;
@end

%hook CCUICAPackageView

- (void)layoutSubviews {
    %orig;

    // 1. 判断是否是低电量模块（通过 Responder 链或 Package 名称）
    UIResponder *responder = self;
    BOOL isLowPower = NO;
    while (responder) {
        NSString *clsName = NSStringFromClass([responder class]);
        if ([clsName containsString:@"LowPower"] || [clsName containsString:@"Battery"]) {
            isLowPower = YES;
            break;
        }
        responder = responder.nextResponder;
    }

    if (isLowPower) {
        // 2. 获取手机当前真实电量 (0.0 ~ 1.0)
        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        float level = [UIDevice currentDevice].batteryLevel;
        if (level < 0) level = 1.0f; // 异常时回退为 1.0

        // 保障最少显示 5% 的微小电量色块，避免完全缩到 0
        if (level < 0.05f) level = 0.05f;

        // 3. 递归寻找并精准对内部所有的子 ShapeLayer / FillLayer 进行 X 轴按电量比例缩放
        [self cb_scaleBatteryFillInLayer:self.layer level:level];
    }
}

%new
- (void)cb_scaleBatteryFillInLayer:(CALayer *)layer level:(float)level {
    if (!layer) return;

    // 内部的矢量色块通常是 CAShapeLayer 或带有 fill 属性的 Layer
    // 电池外框的 Bounds 较宽，而电量填充色块的 Bounds 通常更窄
    // 通过判断 Layer 属性和层级结构，精准对填充块实施 Transform
    
    for (CALayer *sub in layer.sublayers) {
        // 如果子图层的 Bounds 满足内部填充块的比例，且不是最外层容器
        if ([sub isKindOfClass:NSClassFromString(@"CAShapeLayer")] || sub.sublayers.count == 0) {
            
            // 设置锚点为左侧中心 (0, 0.5)，使电量从左向右延伸
            if (sub.anchorPoint.x != 0.0f) {
                CGRect oldFrame = sub.frame;
                sub.anchorPoint = CGPointMake(0.0f, 0.5f);
                sub.frame = oldFrame;
            }

            // 施加平滑的电量缩放动画
            [CATransaction begin];
            [CATransaction setAnimationDuration:0.25];
            sub.transform = CATransform3DMakeScale(level, 1.0f, 1.0f);
            [CATransaction commit];
        } else {
            // 继续深度遍历子图层
            [self cb_scaleBatteryFillInLayer:sub level:level];
        }
    }
}

%end
