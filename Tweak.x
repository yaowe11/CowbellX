#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface CCUIContentModuleContainerView : UIView
@property (nonatomic, strong) NSString *moduleIdentifier;
@property (nonatomic, strong) UILabel *cbPercentLabel;
- (void)cb_updatePercentText;
- (BOOL)cb_isLowPowerModule;
@end

@interface CCUIRoundButton : UIView
@property (nonatomic, strong) UIImageView *glyphImageView;
@end

@interface CCUILabeledRoundButtonViewController : UIViewController
@property (nonatomic, strong) CCUIRoundButton *buttonContainer;
@property (nonatomic, strong) UIImageView *glyphImageView;
- (void)cb_applyDynamicBatteryIcon;
@end

// 精确绘制 1% 精细度的原生风格电池
static UIImage *DrawNativeBatteryWithExactLevel(float level) {
    CGSize size = CGSizeMake(24, 12);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull rendererContext) {
        // 1. 电池外框
        CGRect outerRect = CGRectMake(1, 1, 20, 10);
        UIBezierPath *outerPath = [UIBezierPath bezierPathWithRoundedRect:outerRect cornerRadius:3];
        [[UIColor whiteColor] setStroke];
        outerPath.lineWidth = 1.25;
        [outerPath stroke];
        
        // 2. 正极头
        CGRect tipRect = CGRectMake(21.5, 3.5, 1.5, 5);
        UIBezierPath *tipPath = [UIBezierPath bezierPathWithRoundedRect:tipRect cornerRadius:0.75];
        [[UIColor whiteColor] setFill];
        [tipPath fill];
        
        // 3. 1% 精确内部填充
        float percentage = fmaxf(0.0f, fminf(1.0f, level));
        float maxFillWidth = 16.0f; 
        float fillWidth = maxFillWidth * percentage;
        
        if (fillWidth > 0.5f) {
            CGRect fillRect = CGRectMake(2.8, 2.8, fillWidth, 6.4);
            UIBezierPath *fillPath = [UIBezierPath bezierPathWithRoundedRect:fillRect cornerRadius:1.5];
            [[UIColor whiteColor] setFill];
            [fillPath fill];
        }
    }];
}

// Hook 按钮控制器，强行覆盖图标设置
%hook CCUILabeledRoundButtonViewController

- (void)viewDidLayoutSubviews {
    %orig;

    // 判断是否为低电量模块
    NSString *clsName = NSStringFromClass([self class]);
    UIViewController *parent = self.parentViewController;
    NSString *parentCls = parent ? NSStringFromClass([parent class]) : @"";

    if ([clsName containsString:@"LowPower"] || [parentCls containsString:@"LowPower"]) {
        [self cb_applyDynamicBatteryIcon];
    }
}

- (void)setGlyphImage:(UIImage *)image {
    UIViewController *parent = self.parentViewController;
    NSString *clsName = NSStringFromClass([self class]);
    NSString *parentCls = parent ? NSStringFromClass([parent class]) : @"";

    if ([clsName containsString:@"LowPower"] || [parentCls containsString:@"LowPower"]) {
        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        float level = [UIDevice currentDevice].batteryLevel;
        UIImage *dynImage = DrawNativeBatteryWithExactLevel(level);
        %orig(dynImage);
    } else {
        %orig(image);
    }
}

%new
- (void)cb_applyDynamicBatteryIcon {
    UIImageView *imageView = nil;
    if ([self respondsToSelector:@selector(glyphImageView)]) {
        imageView = self.glyphImageView;
    }
    if (!imageView && [self respondsToSelector:@selector(buttonContainer)]) {
        CCUIRoundButton *btn = self.buttonContainer;
        if ([btn respondsToSelector:@selector(glyphImageView)]) {
            imageView = btn.glyphImageView;
        }
    }
    
    if (imageView) {
        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        float level = [UIDevice currentDevice].batteryLevel;
        imageView.image = DrawNativeBatteryWithExactLevel(level);
        imageView.contentMode = UIViewContentModeCenter;
    }
}

%end

// Hook 控制中心外部卡片容器（负责百分比 Label）
%hook CCUIContentModuleContainerView

%property (nonatomic, strong) UILabel *cbPercentLabel;

- (void)layoutSubviews {
    %orig;

    if (![self cb_isLowPowerModule]) {
        if (self.cbPercentLabel) {
            self.cbPercentLabel.hidden = YES;
        }
        return;
    }

    CGFloat width = self.bounds.size.width;
    CGFloat height = self.bounds.size.height;

    if (width <= 0 || height <= 0 || width > 100 || height > 100) return;

    for (UIView *subview in self.subviews) {
        if (subview != self.cbPercentLabel) {
            subview.transform = CGAffineTransformIdentity;
        }
    }

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
        responder = [responder nextResponder];
    }

    return NO;
}

%new
- (void)cb_updatePercentText {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.cbPercentLabel) return;

        float level = [UIDevice currentDevice].batteryLevel;
        int percent = (level >= 0) ? (int)round(level * 100.0f) : 100;
        self.cbPercentLabel.text = [NSString stringWithFormat:@"%d%%", percent];

        BOOL isLowPowerMode = [NSProcessInfo processInfo].isLowPowerModeEnabled;
        if (isLowPowerMode) {
            self.cbPercentLabel.textColor = [UIColor blackColor];
        } else {
            self.cbPercentLabel.textColor = [UIColor whiteColor];
        }
    });
}

%end
