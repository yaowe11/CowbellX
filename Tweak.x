#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface CCUIContentModuleContainerView : UIView
@property (nonatomic, strong) NSString *moduleIdentifier;
@property (nonatomic, strong) UILabel *cbPercentLabel;
@property (nonatomic, strong) UIView *cbSystemBatteryView;
- (void)cb_updatePercentText;
- (BOOL)cb_isLowPowerModule;
@end

%hook CCUIContentModuleContainerView

%property (nonatomic, strong) UILabel *cbPercentLabel;
%property (nonatomic, strong) UIView *cbSystemBatteryView;

- (void)layoutSubviews {
    %orig;

    if (![self cb_isLowPowerModule]) {
        if (self.cbPercentLabel) self.cbPercentLabel.hidden = YES;
        if (self.cbSystemBatteryView) self.cbSystemBatteryView.hidden = YES;
        return;
    }

    CGFloat width = self.bounds.size.width;
    CGFloat height = self.bounds.size.height;

    if (width <= 0 || height <= 0 || width > 100 || height > 100) return;

    // 1. 仅将原生图标移出可视区域或缩小，不暴力隐藏整体，保证点击事件正常
    for (UIView *subview in self.subviews) {
        if (subview != self.cbPercentLabel && subview != self.cbSystemBatteryView) {
            // 将模块内部的原生 Icon 缩隐，避免叠加
            for (UIView *child in subview.subviews) {
                if ([child isKindOfClass:[UIImageView class]]) {
                    child.alpha = 0.0;
                }
            }
        }
    }

    // 2. 使用系统原生 _UIBatteryView (1%~100% 动态填充)
    if (!self.cbSystemBatteryView) {
        Class batteryClass = NSClassFromString(@"_UIBatteryView");
        if (batteryClass) {
            // 创建系统原生电池视图
            UIView *batView = [[batteryClass alloc] initWithFrame:CGRectMake((width - 22) / 2.0, (height - 30) / 2.0 - 2, 22, 11.5)];
            self.cbSystemBatteryView = batView;
            [self addSubview:batView];
        }

        // 创建百分比 Label
        UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(0, height - 19, width, 12)];
        lab.font = [UIFont systemFontOfSize:9.5 weight:UIFontWeightMedium];
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
        self.cbSystemBatteryView.hidden = NO;
        self.cbPercentLabel.hidden = NO;
        self.cbSystemBatteryView.frame = CGRectMake((width - 22) / 2.0, (height - 30) / 2.0 - 2, 22, 11.5);
        self.cbPercentLabel.frame = CGRectMake(0, height - 19, width, 12);
    }

    if (self.cbSystemBatteryView) [self bringSubviewToFront:self.cbSystemBatteryView];
    if (self.cbPercentLabel) [self bringSubviewToFront:self.cbPercentLabel];
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

        // 1. 获取准确电量浮点值 (0.00 - 1.00)
        float level = [UIDevice currentDevice].batteryLevel;
        if (level < 0) level = 1.0f;
        
        int percent = (int)round(level * 100.0f);
        self.cbPercentLabel.text = [NSString stringWithFormat:@"%d%%", percent];

        // 2. 配色（低电量模式变黑，普通模式变白）
        BOOL isLowPowerMode = [NSProcessInfo processInfo].isLowPowerModeEnabled;
        UIColor *currentColor = isLowPowerMode ? [UIColor blackColor] : [UIColor whiteColor];

        self.cbPercentLabel.textColor = currentColor;

        // 3. 将真实电量与颜色赋给系统 _UIBatteryView
        if (self.cbSystemBatteryView) {
            // 设置电量百分比 (0.0 - 1.0)
            if ([self.cbSystemBatteryView respondsToSelector:@selector(setChargePercent:)]) {
                NSMethodSignature *sig = [self.cbSystemBatteryView methodSignatureForSelector:@selector(setChargePercent:)];
                if (sig) {
                    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                    [inv setTarget:self.cbSystemBatteryView];
                    [inv setSelector:@selector(setChargePercent:)];
                    CGFloat chargePercent = (CGFloat)level;
                    [inv setArgument:&chargePercent atIndex:2];
                    [inv invoke];
                }
            }

            // 设置填充颜色
            if ([self.cbSystemBatteryView respondsToSelector:@selector(setFillColor:)]) {
                [self.cbSystemBatteryView performSelector:@selector(setFillColor:) withObject:currentColor];
            } else {
                self.cbSystemBatteryView.tintColor = currentColor;
            }
        }
    });
}

%end