#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#pragma mark - 1. Cowbell 1:1 精细贝塞尔电池 View

@interface CBCustomBatteryIconView : UIView
@property (nonatomic, assign) float batteryLevel;
@property (nonatomic, assign) BOOL isLowPowerMode;
@end

@implementation CBCustomBatteryIconView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        self.batteryLevel = 1.0f;
    }
    return self;
}

- (void)setBatteryLevel:(float)batteryLevel {
    if (_batteryLevel != batteryLevel) {
        _batteryLevel = batteryLevel;
        [self setNeedsDisplay];
    }
}

- (void)setIsLowPowerMode:(BOOL)isLowPowerMode {
    if (_isLowPowerMode != isLowPowerMode) {
        _isLowPowerMode = isLowPowerMode;
        [self setNeedsDisplay];
    }
}

- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];

    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context) return;

    CGContextSetShouldAntialias(context, YES);
    CGContextSetAllowsAntialiasing(context, YES);

    UIColor *strokeColor = self.isLowPowerMode ? [UIColor blackColor] : [UIColor whiteColor];
    UIColor *fillColor   = self.isLowPowerMode ? [UIColor systemYellowColor] : [UIColor whiteColor];

    // 1. 电池外壳
    CGFloat bodyWidth = rect.size.width - 3.0f; 
    CGFloat bodyHeight = rect.size.height;
    CGRect bodyRect = CGRectMake(0.75f, 0.75f, bodyWidth - 1.5f, bodyHeight - 1.5f);
    
    UIBezierPath *outlinePath = [UIBezierPath bezierPathWithRoundedRect:bodyRect cornerRadius:4.0f];
    outlinePath.lineWidth = 1.35f;
    [strokeColor setStroke];
    [outlinePath stroke];

    // 2. 电池极耳 (对齐原版圆润短小特征)
    CGFloat capWidth = 1.6f;
    CGFloat capHeight = bodyHeight * 0.32f; // 缩短极耳高度
    CGFloat capX = bodyWidth + 0.3f;
    CGFloat capY = (bodyHeight - capHeight) / 2.0f;
    
    UIBezierPath *capPath = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(capX, capY, capWidth, capHeight)
                                                  byRoundingCorners:(UIRectCornerTopRight | UIRectCornerBottomRight)
                                                        cornerRadii:CGSizeMake(1.2, 1.2)];
    [strokeColor setFill];
    [capPath fill];

    // 3. 内部填充 (缩小 padding，让白块更饱满)
    CGFloat padding = 1.2f; 
    CGFloat maxFillWidth = bodyRect.size.width - (padding * 2.0f);
    CGFloat fillHeight = bodyRect.size.height - (padding * 2.0f);
    
    float level = self.batteryLevel;
    if (level < 0.0f) level = 1.0f;
    if (level > 1.0f) level = 1.0f;
    
    CGFloat actualFillWidth = MAX(1.5f, maxFillWidth * level);
    CGRect fillRect = CGRectMake(bodyRect.origin.x + padding, bodyRect.origin.y + padding, actualFillWidth, fillHeight);
    
    UIBezierPath *fillPath = [UIBezierPath bezierPathWithRoundedRect:fillRect cornerRadius:2.2f];
    [fillColor setFill];
    [fillPath fill];
}

@end

#pragma mark - 2. Hook CCUIContentModuleContainerView

@interface CCUIContentModuleContainerViewController : UIViewController
@property (nonatomic, strong) UIViewController *contentViewController;
@end

@interface CCUIContentModuleContainerView : UIView
@property (nonatomic, strong) NSString *moduleIdentifier;
@property (nonatomic, strong) UILabel *cbPercentLabel;
@property (nonatomic, strong) CBCustomBatteryIconView *cbBatteryIconView;
@property (nonatomic, assign) BOOL cb_observerRegistered;

- (BOOL)cb_isLowPowerModule;
- (void)cb_updateStateAndData;
- (void)cb_hideSystemSymbolImageViewInView:(UIView *)view;
@end

%hook CCUIContentModuleContainerView

%property (nonatomic, strong) UILabel *cbPercentLabel;
%property (nonatomic, strong) CBCustomBatteryIconView *cbBatteryIconView;
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
        if (self.cbBatteryIconView) self.cbBatteryIconView.hidden = YES;
        return;
    }

    CGFloat width = self.bounds.size.width;
    CGFloat height = self.bounds.size.height;
    if (width <= 0 || height <= 0 || width > 120 || height > 120) return;

    // 1. 递归隐藏原生 Symbol 图标
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

    // 2. 电池位置 (绝对居中)
    CGFloat iconW = 35.0f;
    CGFloat iconH = 16.0f;
    
    if (!self.cbBatteryIconView) {
        CBCustomBatteryIconView *bat = [[CBCustomBatteryIconView alloc] initWithFrame:CGRectMake(0, 0, iconW, iconH)];
        self.cbBatteryIconView = bat;
        [self addSubview:bat];
    } else {
        self.cbBatteryIconView.hidden = NO;
        self.cbBatteryIconView.frame = CGRectMake(0, 0, iconW, iconH);
    }
    self.cbBatteryIconView.center = CGPointMake(width / 2.0f, (height / 2.0f) - 3.5f);
    [self bringSubviewToFront:self.cbBatteryIconView];

    // 3. 百分比 Label (增大字号并加粗，对齐原版 96% 效果)
    CGFloat labelH = 14.0f;
    CGFloat labelY = CGRectGetMaxY(self.cbBatteryIconView.frame) + 1.5f;
    
    if (!self.cbPercentLabel) {
        UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(0, labelY, width, labelH)];
        // 使用 Medium 字重与 12.0pt，保证 % 符号与数字大小协调
        lab.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
        lab.textAlignment = NSTextAlignmentCenter;
        lab.userInteractionEnabled = NO;

        self.cbPercentLabel = lab;
        [self addSubview:lab];
    } else {
        self.cbPercentLabel.hidden = NO;
        self.cbPercentLabel.frame = CGRectMake(0, labelY, width, labelH);
        self.cbPercentLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
    }
    [self bringSubviewToFront:self.cbPercentLabel];

    // 4. 刷新数据
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
        if (subview == self.cbBatteryIconView || subview == self.cbPercentLabel) {
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

        if (strongSelf.cbBatteryIconView) {
            strongSelf.cbBatteryIconView.isLowPowerMode = isLowPowerMode;
            strongSelf.cbBatteryIconView.batteryLevel = level;
        }

        if (strongSelf.cbPercentLabel) {
            int percent = (int)round(level * 100.0f);
            strongSelf.cbPercentLabel.text = [NSString stringWithFormat:@"%d%%", percent];
            strongSelf.cbPercentLabel.textColor = isLowPowerMode ? [UIColor colorWithWhite:0.15 alpha:1.0] : [UIColor whiteColor];
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
