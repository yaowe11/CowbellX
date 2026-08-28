#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// 声明系统私有的状态栏电池 View
@interface _UIBatteryView : UIView
@property (nonatomic, assign) NSInteger chargeState;
@property (nonatomic, assign) CGFloat chargePercent;
@property (nonatomic, assign) BOOL saverModeActive;
@property (nonatomic, assign) BOOL showsInlineChargingIndicator;
- (instancetype)initWithSizeCategory:(NSInteger)category;
- (void)setChargePercent:(CGFloat)chargePercent;
@end

@interface CCUIRoundButton : UIView
@property (nonatomic, strong) _UIBatteryView *cbBatteryView;
- (BOOL)cb_isLowPowerButton;
@end

@interface CCUIContentModuleContainerView : UIView
@property (nonatomic, strong) NSString *moduleIdentifier;
@property (nonatomic, strong) UILabel *cbPercentLabel;
- (void)cb_updatePercentText;
- (BOOL)cb_isLowPowerModule;
@end

#pragma mark - 1. 用系统原生 _UIBatteryView 精准替换按钮图标

%hook CCUIRoundButton

%property (nonatomic, strong) _UIBatteryView *cbBatteryView;

- (void)layoutSubviews {
    %orig;

    if (![self cb_isLowPowerButton]) return;

    // 1. 隐藏按钮内部原生的 Package 矢量控件，防止盖住
    for (UIView *sub in self.subviews) {
        if (sub != self.cbBatteryView) {
            sub.hidden = YES;
        }
    }

    // 2. 初始化并注入系统的 _UIBatteryView
    if (!self.cbBatteryView) {
        Class batClass = NSClassFromString(@"_UIBatteryView");
        if (batClass) {
            // category 0 为标准尺寸
            _UIBatteryView *bat = [[batClass alloc] initWithSizeCategory:0];
            bat.userInteractionEnabled = NO;

            // 放大 1.4 倍以匹配控制中心的大按钮
            bat.bounds = CGRectMake(0, 0, 24, 12);
            bat.transform = CGAffineTransformMakeScale(1.4, 1.4);

            self.cbBatteryView = bat;
            [self addSubview:bat];
        }
    }

    // 3. 居中定位与动态刷新电量
    if (self.cbBatteryView) {
        self.cbBatteryView.center = CGPointMake(self.bounds.size.width / 2.0, self.bounds.size.height / 2.0 - 5);
        [self bringSubviewToFront:self.cbBatteryView];

        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        float level = [UIDevice currentDevice].batteryLevel;
        if (level < 0) level = 1.0f;

        // 强行传值：精确拉动电池内部填充条缩放 (0.00 ~ 1.00)
        [self.cbBatteryView setChargePercent:level];

        BOOL isLowPower = [NSProcessInfo processInfo].isLowPowerModeEnabled;
        if ([self.cbBatteryView respondsToSelector:@selector(setSaverModeActive:)]) {
            [self.cbBatteryView setSaverModeActive:isLowPower];
        }
    }
}

%new
- (BOOL)cb_isLowPowerButton {
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
