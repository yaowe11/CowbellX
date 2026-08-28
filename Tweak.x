#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

@interface CCUICAPackageView : UIView
- (id)publishedObjectWithName:(NSString *)name;
- (BOOL)cb_isLowPowerPackage;
- (void)cb_updateBatteryLevel;
@end

@interface CCUIContentModuleContainerView : UIView
@property (nonatomic, strong) NSString *moduleIdentifier;
@property (nonatomic, strong) UILabel *cbPercentLabel;
- (void)cb_updatePercentText;
- (BOOL)cb_isLowPowerModule;
@end

#pragma mark - 1. 拦截 CCUICAPackageView 状态设置并修改 Layer

%hook CCUICAPackageView

- (void)setStateName:(NSString *)stateName {
    if ([self cb_isLowPowerPackage]) {
        // 先调用原生的 setStateName 确保外框和底层元素渲染出来
        %orig;
        // 紧接着强行注入我们的电量比例
        [self cb_updateBatteryLevel];
    } else {
        %orig;
    }
}

- (void)layoutSubviews {
    %orig;
    if ([self cb_isLowPowerPackage]) {
        [self cb_updateBatteryLevel];
    }
}

%new
- (BOOL)cb_isLowPowerPackage {
    UIResponder *responder = self;
    while (responder) {
        NSString *clsName = NSStringFromClass([responder class]);
        if ([clsName containsString:@"LowPower"]) {
            return YES;
        }
        responder = [responder nextResponder];
    }
    return NO;
}

%new
- (void)cb_updateBatteryLevel {
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        float level = [UIDevice currentDevice].batteryLevel;
        if (level < 0) level = 1.0f;

        // 1. 尝试直接获取 CAPackage 暴露的电池填充 layer ("fill" 是 iOS 16 低电量 module 的矢量 Key)
        CALayer *fillLayer = nil;
        if ([self respondsToSelector:@selector(publishedObjectWithName:)]) {
            fillLayer = [self publishedObjectWithName:@"fill"];
            if (!fillLayer) fillLayer = [self publishedObjectWithName:@"Fill"];
            if (!fillLayer) fillLayer = [self publishedObjectWithName:@"level"];
        }

        // 2. 如果成功拿到 fillLayer，判断它是 CAShapeLayer 还是普通 CALayer
        if (fillLayer) {
            [CATransaction begin];
            [CATransaction setDisableActions:YES]; // 禁用系统默认补间动画，确保 1% 实时平滑

            if ([fillLayer isKindOfClass:[CAShapeLayer class]]) {
                // 如果是路径型 ShapeLayer，直接修改 strokeEnd 即可实现百分比拉伸
                ((CAShapeLayer *)fillLayer).strokeEnd = level;
            } else {
                // 如果是 Bitmap/Model 矢量图层，通过 AnchorPoint 定位在左侧并平滑 X 轴缩放
                fillLayer.anchorPoint = CGPointMake(0.0, 0.5);
                fillLayer.transform = CATransform3DMakeScale(level, 1.0, 1.0);
            }

            [CATransaction commit];
        } else {
            // 3. 兜底方案：如果没拿到 publishedObject，深度遍历 packageView 找到负责填充的子 Layer
            [self cb_findAndScaleFillLayerInLayer:self.layer level:level];
        }
    });
}

%new
- (void)cb_findAndScaleFillLayerInLayer:(CALayer *)parentLayer level:(float)level {
    for (CALayer *sub in parentLayer.sublayers) {
        // 找到内部名字包含 fill 或 key Path 的子 Layer
        NSString *name = [sub.name lowercaseString];
        if (name && ([name containsString:@"fill"] || [name containsString:@"level"])) {
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            sub.anchorPoint = CGPointMake(0.0, 0.5);
            sub.transform = CATransform3DMakeScale(level, 1.0, 1.0);
            [CATransaction commit];
            return;
        }
        if (sub.sublayers.count > 0) {
            [self cb_findAndScaleFillLayerInLayer:sub level:level];
        }
    }
}

%end

#pragma mark - 2. 底部 81% 文本显示

%hook CCUIContentModuleContainerView

%property (nonatomic, strong) UILabel *cbPercentLabel;

- (void)layoutSubviews {
    %orig;

    if (![self cb_isLowPowerModule]) {
        if (self.cbPercentLabel) self.cbPercentLabel.hidden = YES;
        return;
    }

    CGFloat width = self.bounds.size.width;
    CGFloat height = self.bounds.size.height;
    if (width <= 0 || height <= 0 || width > 100 || height > 100) return;

    if (!self.cbPercentLabel) {
        UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(0, height - 16, width, 12)];
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
        self.cbPercentLabel.frame = CGRectMake(0, height - 16, width, 12);
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
        responder = [responder nextResponder];
    }

    return NO;
}

%new
- (void)cb_updatePercentText {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.cbPercentLabel) return;

        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        float level = [UIDevice currentDevice].batteryLevel;
        int percent = (level >= 0) ? (int)round(level * 100.0f) : 100;

        self.cbPercentLabel.text = [NSString stringWithFormat:@"%d%%", percent];
        BOOL isLowPowerMode = [NSProcessInfo processInfo].isLowPowerModeEnabled;
        self.cbPercentLabel.textColor = isLowPowerMode ? [UIColor blackColor] : [UIColor whiteColor];
    });
}

%end
