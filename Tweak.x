#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

@interface CCUICAPackageView : UIView
@property (nonatomic, copy) NSString *packageName;
@end

// 动态计算并强行修改电池内部填充 Layer
static void cb_updateBatteryFill(CALayer *layer, float level) {
    if (!layer || !layer.sublayers) return;

    for (CALayer *sub in layer.sublayers) {
        NSString *name = sub.name.lowercaseString;

        // 识别电池内部的填充图层 (通常包含 fill/capacity 或尺寸位于内部)
        BOOL isFillLayer = name && ([name containsString:@"fill"] || [name containsString:@"capacity"] || [name containsString:@"level"]);
        
        if (!isFillLayer && sub.bounds.size.width >= 10 && sub.bounds.size.width <= 32) {
            // 如果名字没标记，按尺寸精准锁定内部填充块
            isFillLayer = YES;
        }

        if (isFillLayer) {
            [CATransaction begin];
            [CATransaction setDisableActions:YES]; // 禁用系统默认动画覆盖
            
            // 改变锚点为左侧，确保从左向右填充
            sub.anchorPoint = CGPointMake(0.0, 0.5);
            // 重新计算 position 偏移以防锚点改变导致图层错位
            sub.position = CGPointMake(sub.frame.origin.x, sub.position.y);
            // 按照真实电量比例 (0.05 ~ 1.0) 进行横向 CATransform3D 缩放
            sub.transform = CATransform3DMakeScale(level, 1.0, 1.0);
            
            [CATransaction commit];
        }

        cb_updateBatteryFill(sub, level);
    }
}

%hook CCUICAPackageView

- (void)layoutSubviews {
    %orig;

    // 获取真实电量
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    float level = [UIDevice currentDevice].batteryLevel;
    if (level < 0) level = 1.0f;
    if (level < 0.05f) level = 0.05f;

    cb_updateBatteryFill(self.layer, level);
}

%end
