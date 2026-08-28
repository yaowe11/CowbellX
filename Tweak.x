#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// 声明系统私有类 _UIBatteryView
@interface _UIBatteryView : UIView
@property (nonatomic, assign) NSInteger chargeState;
@property (nonatomic, assign) CGFloat chargePercent;
@property (nonatomic, assign) BOOL saverModeActive;
@property (nonatomic, assign) BOOL showsInlineChargingIndicator;
- (instancetype)initWithSizeCategory:(NSInteger)category;
- (void)setChargePercent:(CGFloat)chargePercent;
@end

@interface CCUIContentModuleContainerView : UIView
@property (nonatomic, strong) NSString *moduleIdentifier;
@property (nonatomic, strong) UILabel *cbPercentLabel;
@property (nonatomic, strong) _UIBatteryView *cbBatteryView;
- (void)cb_updatePercentTextAndIcon;
- (BOOL)cb_isLowPowerModule;
@end

%hook CCUIContentModuleContainerView

%property (nonatomic, strong) UILabel *cbPercentLabel;
%property (nonatomic, strong) _UIBatteryView *cbBatteryView;

- (void)layoutSubviews {
    %orig;

    if (![self cb_isLowPowerModule]) {
        if (self.cbPercentLabel) self.cbPercentLabel.hidden = YES;
        if (self.cbBatteryView) self.cbBatteryView.hidden = YES;
        return;
    }

    CGFloat width = self.bounds.size.width;
    CGFloat height = self.bounds.size.height;

    if (width <= 0 || height <= 0 || width > 100 || height > 100) return;

    // 1. 递归隐藏原生图标ImageView，防止重影
    for (UIView *subview in self.subviews) {
        if (subview != self.cbPercentLabel && subview != (UIView *)self.cbBatteryView) {
            for (UIView *child in subview.subviews) {
                if ([child isKindOfClass:[UIImageView class]]) {
                    child.hidden = YES;
                }
            }
        }
    }

    // 2. 嵌入系统原生的 _UIBatteryView 控件
    if (!self.cbBatteryView) {
        Class batteryClass = NSClassFromString(@"_UIBatteryView");
        if (batteryClass) {
            // sizeCategory 0 为标准尺寸，可自由设定 bounds
            _UIBatteryView *bat = [[batteryClass alloc] initWithSizeCategory:0];
            bat.frame = CGRectMake((width - 24) / 2.0, (height - 24) / 2.0 - 4, 24, 12);
            bat.userInteractionEnabled = NO;
            
            self.cbBatteryView = bat;
            [self addSubview:bat];
        }
    } else {
        self.cbBatteryView.hidden = NO;
        self.cbBatteryView.frame = CGRectMake((width - 24) / 2.0, (height - 24) / 2.0 - 4, 24, 12);
    }

    // 3. 嵌入百分比 Label
    if (!self.cbPercentLabel) {
        UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(0, height - 22, width, 12)];
        lab.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
        lab.textAlignment = NSTextAlignmentCenter;
        lab.userInteractionEnabled = NO;

        self.cbPercentLabel = lab;
        [self addSubview:lab];

        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(cb_updatePercentTextAndIcon)
                                                     name:UIDeviceBatteryLevelDidChangeNotification
                                                   object:nil];
                                                   
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(cb_updatePercentTextAndIcon)
                                                     name:NSProcessInfoPowerStateDidChangeNotification
                                                   object:nil];
    } else {
        self.cbPercentLabel.hidden = NO;
        self.cbPercentLabel.frame = CGRectMake(0, height - 22, width, 12);
    }

    if (self.cbBatteryView) [self bringSubviewToFront:(UIView *)self.cbBatteryView];
    [self bringSubviewToFront:self.cbPercentLabel];
    
    [self cb_updatePercentTextAndIcon];
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
- (void)cb_updatePercentTextAndIcon {
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        float level = [UIDevice currentDevice].batteryLevel;
        if (level < 0) level = 1.0f;
        int percent = (int)round(level * 100.0f);

        // 1. 刷新百分比
        if (self.cbPercentLabel) {
            self.cbPercentLabel.text = [NSString stringWithFormat:@"%d%%", percent];
            BOOL isLowPowerMode = [NSProcessInfo processInfo].isLowPowerModeEnabled;
            self.cbPercentLabel.textColor = isLowPowerMode ? [UIColor blackColor] : [UIColor whiteColor];
        }

        // 2. 将电量精准传给系统原生 _UIBatteryView 控件 (0.0 ~ 1.0)
        if (self.cbBatteryView) {
            [self.cbBatteryView setChargePercent:level];
            
            // 同步低电量模式状态（开启时内部填充条会自动变红/黄）
            BOOL isLowPower = [NSProcessInfo processInfo].isLowPowerModeEnabled;
            if ([self.cbBatteryView respondsToSelector:@selector(setSaverModeActive:)]) {
                [self.cbBatteryView setSaverModeActive:isLowPower];
            }
        }
    });
}

%end
