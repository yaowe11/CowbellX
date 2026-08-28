#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

@interface CCUICAPackageView : UIView
- (id)publishedObjectWithName:(NSString *)name;
- (NSArray *)publishedObjectNames;
- (BOOL)cb_isLowPowerPackage;
- (void)cb_applyBatteryLevel;
@end

@interface CCUIContentModuleContainerView : UIView
@property (nonatomic, strong) NSString *moduleIdentifier;
@property (nonatomic, strong) UILabel *cbPercentLabel;
- (void)cb_updatePercentText;
- (BOOL)cb_isLowPowerModule;
@end

#pragma mark - 1. 动态挂载原生 CALayer 缩放

%hook CCUICAPackageView

- (void)layoutSubviews {
    %orig;

    if ([self cb_isLowPowerPackage]) {
        [self cb_applyBatteryLevel];
    }
}

- (void)setStateName:(NSString *)stateName {
    %orig;

    if ([self cb_isLowPowerPackage]) {
        [self cb_applyBatteryLevel];
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
- (void)cb_applyBatteryLevel {
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        float level = [UIDevice currentDevice].batteryLevel;
        if (level < 0) level = 1.0f;

        // 方法 A：通过 CAPackage 暴露的官方 Key 精准调取填充图层
        CALayer *fillLayer = nil;
        if ([self respondsToSelector:@selector(publishedObjectWithName:)]) {
            fillLayer = [self publishedObjectWithName:@"fill"];
            if (!fillLayer) fillLayer = [self publishedObjectWithName:@"Level"];
            if (!fillLayer) fillLayer = [self publishedObjectWithName:@"battery-fill"];
            if (!fillLayer) fillLayer = [self publishedObjectWithName:@"battery"];
        }

        // 方法 B：如果方法 A 未命中，直接遍历根 Layer 下的所有叶子 CALayer
        if (!fillLayer && self.layer.sublayers.count > 0) {
            NSMutableArray *queue = [NSMutableArray arrayWithArray:self.layer.sublayers];
            while (queue.count > 0) {
                CALayer *ly = [queue firstObject];
                [queue removeObjectAtIndex:0];
                
                // 筛选出非根节点且拥有几何形状的矢量 Shape/Model Layer
                if (ly.sublayers.count == 0 && ([ly isKindOfClass:[CAShapeLayer class]] || [NSStringFromClass([ly class]) containsString:@"Vector"])) {
                    fillLayer = ly;
                    break;
                }
                if (ly.sublayers.count > 0) {
                    [queue addObjectsFromArray:ly.sublayers];
                }
            }
        }

        // 强行施加横向 1% 精度的 X 轴 Transform 矩阵缩放
        if (fillLayer) {
            fillLayer.transform = CATransform3DIdentity;
            fillLayer.transform = CATransform3DMakeScale(level, 1.0, 1.0);
        } else {
            // 方法 C (终极兜底)：直接对整个 PackageView 的内部主 Layer 进行横向缩放裁剪
            for (CALayer *sub in self.layer.sublayers) {
                sub.transform = CATransform3DIdentity;
                sub.transform = CATransform3DMakeScale(0.2f + (0.8f * level), 1.0, 1.0);
            }
        }
    });
}

%end

#pragma mark - 2. 底部百分比显示

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
        UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(0, height - 18, width, 12)];
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
        self.cbPercentLabel.frame = CGRectMake(0, height - 18, width, 12);
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
