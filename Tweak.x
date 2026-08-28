#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#pragma mark - Hook CCUIContentModuleContainerView

@interface CCUIContentModuleContainerViewController : UIViewController
@property (nonatomic, strong) UIViewController *contentViewController;
@end

@interface CCUIContentModuleContainerView : UIView
@property (nonatomic, strong) NSString *moduleIdentifier;
@property (nonatomic, strong) UIImageView *cbBatteryImageView;
@property (nonatomic, strong) UILabel *cbPercentLabel;
@property (nonatomic, assign) BOOL cb_observerRegistered;

- (BOOL)cb_isLowPowerModule;
- (void)cb_updateStateAndData;
- (void)cb_hideSystemSymbolImageViewInView:(UIView *)view;
@end

%hook CCUIContentModuleContainerView

%property (nonatomic, strong) UIImageView *cbBatteryImageView;
%property (nonatomic, strong) UILabel *cbPercentLabel;
%property (nonatomic, assign) BOOL cb_observerRegistered;

- (void)didMoveToWindow {
    %orig;
    BOOL isLowPower = [self cb_isLowPowerModule];

    if (self.window && isLowPower) {
        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        if (!self.cb_observerRegistered) {
            self.cb_observerRegistered = YES;
            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(cb_updateStateAndData)
                                                         name:UIDeviceBatteryLevelDidChangeNotification
                                                       object:nil];
            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(cb_updateStateAndData)
                                                         name:NSProcessInfoPowerStateDidChangeNotification
                                                       object:nil];
        }
    } else {
        if (self.cb_observerRegistered) {
            [[NSNotificationCenter defaultCenter] removeObserver:self];
            self.cb_observerRegistered = NO;
        }
    }
}

- (void)layoutSubviews {
    %orig;

    if (![self cb_isLowPowerModule]) {
        if (self.cbPercentLabel) self.cbPercentLabel.hidden = YES;
        if (self.cbBatteryImageView) self.cbBatteryImageView.hidden = YES;
        return;
    }

    CGFloat width = self.bounds.size.width;
    CGFloat height = self.bounds.size.height;
    if (width <= 0 || height <= 0 || width > 120 || height > 120) return;

    // 1. 递归隐藏控制中心默认的静态 Icon
    [self cb_hideSystemSymbolImageViewInView:self];

    UIResponder *responder = self;
    while (responder && ![responder isKindOfClass:[UIViewController class]]) {
        responder = responder.nextResponder;
    }
    if ([responder isKindOfClass:NSClassFromString(@"CCUIContentModuleContainerViewController")]) {
        CCUIContentModuleContainerViewController *containerVC = (CCUIContentModuleContainerViewController *)responder;
        if ([containerVC respondsToSelector:@selector(contentViewController)]) {
            UIViewController *innerVC = containerVC.contentViewController;
            if (innerVC && innerVC.view) {
                [self cb_hideSystemSymbolImageViewInView:innerVC.view];
            }
        }
    }

    // 2. 布局：还原最一开始最完美的居中与尺寸比例
    CGFloat iconW = 38.0f;
    CGFloat iconH = 18.0f;
    CGFloat spacing = 2.0f;
    CGFloat labelH = 13.0f;

    CGFloat totalH = iconH + spacing + labelH;
    CGFloat startY = (height - totalH) / 2.0f;

    // 3. SF‑Symbol UIImageView
    CGRect iconFrame = CGRectMake((width - iconW) / 2.0f, startY, iconW, iconH);
    if (!self.cbBatteryImageView) {
        UIImageView *imgView = [[UIImageView alloc] initWithFrame:iconFrame];
        imgView.contentMode = UIViewContentModeScaleAspectFit;
        imgView.userInteractionEnabled = NO;
        self.cbBatteryImageView = imgView;
        [self addSubview:imgView];
    } else {
        self.cbBatteryImageView.hidden = NO;
        self.cbBatteryImageView.frame = iconFrame;
    }
    [self bringSubviewToFront:self.cbBatteryImageView];

    // 4. 百分比 Label
    CGRect labelFrame = CGRectMake(0, startY + iconH + spacing, width, labelH);
    if (!self.cbPercentLabel) {
        UILabel *lab = [[UILabel alloc] initWithFrame:labelFrame];
        lab.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightMedium];
        lab.textAlignment = NSTextAlignmentCenter;
        lab.userInteractionEnabled = NO;

        self.cbPercentLabel = lab;
        [self addSubview:lab];
    } else {
        self.cbPercentLabel.hidden = NO;
        self.cbPercentLabel.frame = labelFrame;
    }
    [self bringSubviewToFront:self.cbPercentLabel];

    // 5. 刷新数据
    [self cb_updateStateAndData];
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
- (void)cb_hideSystemSymbolImageViewInView:(UIView *)parentView {
    for (UIView *subview in parentView.subviews) {
        if (subview == self.cbBatteryImageView || subview == self.cbPercentLabel) {
            continue;
        }
        if ([subview isKindOfClass:[UIImageView class]] ||
            [NSStringFromClass([subview class]) containsString:@"CAPackageView"]) {
            subview.hidden = YES;
        }
        if (subview.subviews.count > 0) {
            [self cb_hideSystemSymbolImageViewInView:subview];
        }
    }
}

%new
- (void)cb_updateStateAndData {
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        float level = [UIDevice currentDevice].batteryLevel;
        if (level < 0) level = 1.0f;
        BOOL isLowPowerMode = [NSProcessInfo processInfo].isLowPowerModeEnabled;

        NSString *symbolName = @"battery.100";
        if (level <= 0.05f) {
            symbolName = @"battery.0";
        } else if (level <= 0.35f) {
            symbolName = @"battery.25";
        } else if (level <= 0.65f) {
            symbolName = @"battery.50";
        } else if (level <= 0.88f) {
            symbolName = @"battery.75";
        } else {
            symbolName = @"battery.100";
        }

        UIImage *systemIcon = nil;
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:18.0 weight:UIImageSymbolWeightRegular];
        systemIcon = [UIImage systemImageNamed:@"battery.100" variableValue:level configuration:config];

        if (!systemIcon) {
            systemIcon = [UIImage systemImageNamed:symbolName withConfiguration:config];
        }

        if (strongSelf.cbBatteryImageView) {
            strongSelf.cbBatteryImageView.image = systemIcon;
            strongSelf.cbBatteryImageView.tintColor = isLowPowerMode ? [UIColor blackColor] : [UIColor whiteColor];
        }

        if (strongSelf.cbPercentLabel) {
            int percent = (int)round(level * 100.0f);
            strongSelf.cbPercentLabel.text = [NSString stringWithFormat:@"%d%%", percent];
            strongSelf.cbPercentLabel.textColor = isLowPowerMode ? [UIColor blackColor] : [UIColor whiteColor];
        }
    });
}

- (void)dealloc {
    if (self.cb_observerRegistered) {
        [[NSNotificationCenter defaultCenter] removeObserver:self];
    }
    %orig;
}

%end