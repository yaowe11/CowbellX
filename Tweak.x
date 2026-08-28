#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

@interface CCUICAPackageView : UIView
- (BOOL)cb_isLowPowerPackage;
- (void)cb_updateBatteryProgress;
@end

@interface CCUIContentModuleContainerView : UIView
@property (nonatomic, strong) NSString *moduleIdentifier;
@property (nonatomic, strong) UILabel *cbPercentLabel;
- (void)cb_updatePercentText;
- (BOOL)cb_isLowPowerModule;
@end

#pragma mark - 1. 劫持原生 CAPackage 图层实现 1% 平滑缩放

%hook CCUICAPackageView

- (void)layoutSubviews {
    %orig;

    if ([self cb_isLowPowerPackage]) {
        [self cb_updateBatteryProgress];
    }
}

- (void)setStateName:(NSString *)stateName {
    %orig;

    if ([self cb_isLowPowerPackage]) {
        [self cb_updateBatteryProgress];
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
- (void)cb_updateBatteryProgress {
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        float level = [UIDevice currentDevice].batteryLevel;
        if (level < 0) level = 1.0f;

        // 冻结原生 CALayer 动画播放，将电量百分比(0.0~1.0)直接映射为动画帧进度
        self.layer.speed = 0.0;
        
        CFTimeInterval duration = self.layer.duration;
        if (duration <= 0) duration = 1.0; // 防止未获取到 duration 时除零
        
        self.layer.timeOffset = level * duration;
    });
}

%end

#pragma mark - 2. 渲染底部 81% 百分比 Label

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
