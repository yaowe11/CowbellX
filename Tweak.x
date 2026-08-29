#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

@interface CCUICAPackageView : UIView
- (void)setStateName:(NSString *)stateName;
@end

static void cb_scaleFillLayerOnly(CALayer *layer, float level) {
    if (!layer || !layer.sublayers) return;

    for (CALayer *sub in layer.sublayers) {
        NSString *name = sub.name.lowercaseString;

        // 寻找电量填充块图层
        BOOL isFillLayer = name && ([name containsString:@"fill"] || [name containsString:@"capacity"]);
        
        if (isFillLayer) {
            [CATransaction begin];
            [CATransaction setDisableActions:YES]; // 禁用 CoreAnimation 默认拉伸过渡

            // 1. 修正锚点到左侧 (0, 0.5)，确保向右延伸、从右向左收缩
            if (sub.anchorPoint.x != 0.0f) {
                CGPoint oldAnchor = sub.anchorPoint;
                sub.anchorPoint = CGPointMake(0.0f, 0.5f);
                sub.position = CGPointMake(sub.position.x - (oldAnchor.x - 0.0f) * sub.bounds.size.width, sub.position.y);
            }

            // 2. 强行按实际电量比例缩放 X 轴
            sub.transform = CATransform3DMakeScale(level, 1.0, 1.0);

            [CATransaction commit];
            return;
        }

        cb_scaleFillLayerOnly(sub, level);
    }
}

// 通用逻辑：判断是否为低电量模块并施加电量缩放
static void cb_updateLowPowerIconIfNeeded(CCUICAPackageView *view) {
    UIResponder *r = view;
    BOOL isLowPower = NO;
    while (r) {
        NSString *cls = NSStringFromClass([r class]);
        if ([cls containsString:@"LowPower"] || [cls containsString:@"Battery"]) {
            isLowPower = YES;
            break;
        }
        r = r.nextResponder;
    }

    if (!isLowPower) return;

    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    float level = [UIDevice currentDevice].batteryLevel;
    if (level < 0) level = 1.0f;
    if (level < 0.05f) level = 0.05f;

    cb_scaleFillLayerOnly(view.layer, level);
}

%hook CCUICAPackageView

// 1. 布局时刷新电量
- (void)layoutSubviews {
    %orig;
    cb_updateLowPowerIconIfNeeded(self);
}

// 2. 拦截系统切换动画（解决点击开启/关闭低电量模式后失效恢复默认的问题）
- (void)setStateName:(NSString *)stateName {
    %orig(stateName);
    
    // 动画切换完后，在下一个 RunLoop 极速补上电量缩放，防止被系统覆盖
    __weak CCUICAPackageView *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (weakSelf) {
            cb_updateLowPowerIconIfNeeded(weakSelf);
        }
    });
}

%end
