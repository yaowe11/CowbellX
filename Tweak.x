#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#pragma mark - 1. 自定义贝塞尔绘制电池 View (放大尺寸 + 优化配色)

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

    // 低电量模式下系统背景是黄色，图标用黑色；未开启低电量时背景是灰黑色，图标用白色
    UIColor *strokeColor = self.isLowPowerMode ? [UIColor blackColor] : [UIColor whiteColor];
    UIColor *fillColor = strokeColor;

    // 1. 电池外壳
    CGFloat bodyWidth = rect.size.width - 3.5f; // 给极耳留出 3.5px
    CGFloat bodyHeight = rect.size.height;
    CGRect bodyRect = CGRectMake(0.75f, 0.75f, bodyWidth - 1.5f, bodyHeight - 1.5f);
    
    UIBezierPath *outlinePath = [UIBezierPath bezierPathWithRoundedRect:bodyRect cornerRadius:3.5f];
    outlinePath.lineWidth = 1.35f;
    [strokeColor setStroke];
    [outlinePath stroke];

    // 2. 电池极耳 (Cap)
    CGFloat capWidth = 2.0f;
    CGFloat capHeight = bodyHeight * 0.42f;
    CGFloat capX = bodyWidth + 0.5f;
    CGFloat capY = (bodyHeight - capHeight) / 2.0f;
    
    UIBezierPath *capPath = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(capX, capY, capWidth, capHeight)
                                                  byRoundingCorners:(UIRectCornerTopRight | UIRectCornerBottomRight)
                                                        cornerRadii:CGSizeMake(1.2, 1.2)];
    [strokeColor setFill];
    [capPath fill];

    // 3. 内部电量填充
    CGFloat padding = 2.0f;
    CGFloat maxFillWidth = bodyRect.size.width - (padding * 2.0f);
    CGFloat fillHeight = bodyRect.size.height - (padding * 2.0f);
    
    float level = self.batteryLevel;
    if (level < 0.0f) level = 1.0f;
    if (level > 1.0f) level = 1.0f;
    
    CGFloat actualFillWidth = MAX(1.8f, maxFillWidth * level);
    CGRect fillRect = CGRectMake(bodyRect.origin.x + padding, bodyRect.origin.y + padding, actualFillWidth, fillHeight);
    
    UIBezierPath *fillPath = [UIBezierPath bezierPathWithRoundedRect:fillRect cornerRadius:1.5f];
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

    // 1. 穿透隐藏原生 Symbol 图标
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

    // 2. 放大图标尺寸至 30x14，拉开纵横比
    if (!self.cbBatteryIconView) {
        CBCustomBatteryIconView *bat = [[CBCustomBatteryIconView alloc] initWithFrame:CGRectMake(0, 0, 30, 14)];
        self.cbBatteryIconView = bat;
        [self addSubview:bat];
    } else {
        self.cbBatteryIconView.hidden = NO;
        self.cbBatteryIconView.frame = CGRectMake(0, 0, 30, 14);
    }
    
    // 重新校准居中点 (Y轴微调到 -3.0f，整体垂直居中平衡)
    self.cbBatteryIconView.center = CGPointMake(width / 2.0f, (height / 2.0f) - 3.0f);
    [self bringSubviewToFront:self.cbBatteryIconView];

    // 3. 校准底部百分比 Label 位置
    if (!self.cbPercentLabel) {
        UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(0, height - 15, width, 12)];
        lab.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightBold];
        lab.textAlignment = NSTextAlignmentCenter;
        lab.userInteractionEnabled = NO;

        self.cbPercentLabel = lab;
        [self addSubview:lab];
    } else {
        self.cbPercentLabel.hidden = NO;
        self.cbPercentLabel.frame = CGRectMake(0, height - 15, width, 12);
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
