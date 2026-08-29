#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

@interface CCUIContentModuleContainerView : UIView
@property (nonatomic, strong) NSString *moduleIdentifier;
@property (nonatomic, strong) UILabel *cbPercentLabel;
- (void)cb_updatePercentText;
- (BOOL)cb_isLowPowerModule;
- (void)cb_applyBatteryFillToPackageView:(UIView *)packageView level:(float)level;
@end

%hook CCUIContentModuleContainerView

%property (nonatomic, strong) UILabel *cbPercentLabel;

- (void)layoutSubviews {
    %orig;

    // 1. 非低电量模块隐藏并返回
    if (![self cb_isLowPowerModule]) {
        if (self.cbPercentLabel) {
            self.cbPercentLabel.hidden = YES;
        }
        return;
    }

    CGFloat width = self.bounds.size.width;
    CGFloat height = self.bounds.size.height;

    if (width <= 0 || height <= 0 || width > 100 || height > 100) return;

    // 2. 原生图标完全保持原位
    for (UIView *subview in self.subviews) {
        if (subview != self.cbPercentLabel) {
            subview.transform = CGAffineTransformIdentity;
        }
    }

    // 3. 保持你调好的百分比 Label 布局
    if (!self.cbPercentLabel) {
        UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(0, height - 22, width, 12)];
        lab.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
        lab.textAlignment = NSTextAlignmentCenter;
        lab.userInteractionEnabled = NO;

        self.cbPercentLabel = lab;
        [self addSubview:lab];

        [UIDevice currentDevice].batteryMonitoringEnabled = YES;

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(cb_updatePercentText)
                                                     name:UIDeviceBatteryLevelDidChangeNotification
                                                   object:nil];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(cb_updatePercentText)
                                                     name:NSProcessInfoPowerStateDidChangeNotification
                                                   object:nil];
    } else {
        self.cbPercentLabel.hidden = NO;
        self.cbPercentLabel.frame = CGRectMake(0, height - 22, width, 12);
    }

    [self bringSubviewToFront:self.cbPercentLabel];
    [self cb_updatePercentText];
}

%new
- (BOOL)cb_isLowPowerModule {
    if ([self respondsToSelector:@selector(moduleIdentifier)]) {
        NSString *modID = [self performSelector:@selector(moduleIdentifier)];
        if ([modID isEqualToString:@"com.apple.control-center.LowPowerModule"] || 
            [modID containsString:@"LowPowerModule"]) {
            return YES;
        }
    }

    UIResponder *responder = self;
    while (responder) {
        NSString *clsName = NSStringFromClass([responder class]);
        if ([clsName containsString:@"CCUILowPowerModeModule"]) {
            return YES;
        }
        responder = responder.nextResponder;
    }

    return NO;
}

%new
- (void)cb_updatePercentText {
    dispatch_async(dispatch_get_main_queue(), ^{
        float level = [UIDevice currentDevice].batteryLevel;
        if (level < 0) level = 1.0f;

        // 1. 刷新百分比 Label 文本与颜色
        if (self.cbPercentLabel) {
            int percent = (int)round(level * 100.0f);
            self.cbPercentLabel.text = [NSString stringWithFormat:@"%d%%", percent];

            BOOL isLowPowerMode = [NSProcessInfo processInfo].isLowPowerModeEnabled;
            if (isLowPowerMode) {
                self.cbPercentLabel.textColor = [UIColor blackColor];
            } else {
                self.cbPercentLabel.textColor = [UIColor whiteColor];
            }
        }

        // 2. 遍历查找原生 Package 图标组件并做几何几何裁切/缩放
        for (UIView *subview in self.subviews) {
            if (subview == self.cbPercentLabel) continue;
            [self cb_applyBatteryFillToPackageView:subview level:level];
        }
    });
}

%new
- (void)cb_applyBatteryFillToPackageView:(UIView *)targetView level:(float)level {
    if (!targetView) return;

    // 递归查找所有的 Layer 节点
    NSMutableArray *queue = [NSMutableArray arrayWithObject:targetView.layer];

    while (queue.count > 0) {
        CALayer *layer = [queue firstObject];
        [queue removeObjectAtIndex:0];

        // 匹配逻辑：
        // 电池图标的填充 Layer 满足特征：
        // 1. 它属于 CAShapeLayer 或者普通的 CALayer
        // 2. 它的 bounds 宽度大于 5 且小于整个外框（非最外层根 Layer，也非最底层的全屏背景）
        // 3. 背景色不为空 或 拥有 path 填充
        CGRect bounds = layer.bounds;
        BOOL isFillCandidate = NO;

        if ([layer isKindOfClass:[CAShapeLayer class]]) {
            CAShapeLayer *shape = (CAShapeLayer *)layer;
            if (shape.path || shape.fillColor) {
                isFillCandidate = YES;
            }
        } else if (layer.backgroundColor != NULL) {
            isFillCandidate = YES;
        }

        // 排除根节点，锁定真正的内部电池 Fill 块
        if (isFillCandidate && bounds.size.width > 5.0 && bounds.size.width < targetView.bounds.size.width && bounds.size.height > 3.0) {
            
            // 采用精准的 Transform 矩阵改变水平缩放
            // 改变锚点至左侧中心 (0, 0.5)
            if (layer.anchorPoint.x != 0.0f) {
                CGPoint newAnchor = CGPointMake(0.0f, 0.5f);
                CGPoint currentAnchor = layer.anchorPoint;
                
                CGRect frame = layer.frame;
                frame.origin.x += (newAnchor.x - currentAnchor.x) * frame.size.width;
                frame.origin.y += (newAnchor.y - currentAnchor.y) * frame.size.height;
                
                layer.anchorPoint = newAnchor;
                layer.frame = frame;
            }

            // 施加 X 轴缩放，保持 Y 轴不变
            layer.transform = CATransform3DMakeScale(level, 1.0f, 1.0f);
        }

        if (layer.sublayers.count > 0) {
            [queue addObjectsFromArray:layer.sublayers];
        }
    }

    // 递归深入查找子 View
    for (UIView *child in targetView.subviews) {
        if (child != self.cbPercentLabel) {
            [self cb_applyBatteryFillToPackageView:child level:level];
        }
    }
}

%end
