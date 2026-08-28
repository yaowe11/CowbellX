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
- (void)cb_updateBatteryIcon;
@end

// 精确控制原生图标 1% 变化的函数
static void UpdateRoundButtonBatteryIcon(CCUIRoundButton *button) {
    if (!button) return;
    
    UIImageView *imageView = nil;
    if ([button respondsToSelector:@selector(glyphImageView)]) {
        imageView = button.glyphImageView;
    }
    
    if (!imageView) {
        for (UIView *sub in button.subviews) {
            if ([sub isKindOfClass:[UIImageView class]]) {
                imageView = (UIImageView *)sub;
                break;
            }
        }
    }
    
    if (!imageView) return;

    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    float level = [UIDevice currentDevice].batteryLevel;
    int percent = (level >= 0) ? (int)round(level * 100.0f) : 100;

    // 1. 使用系统原生满电 SF Symbol 作为纯净基础图标
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightMedium];
    UIImage *baseSymbol = [UIImage systemImageNamed:@"battery.100" withConfiguration:config];
    if (baseSymbol) {
        imageView.image = baseSymbol;
    }

    // 2. 用 CAShapeLayer 作为 Mask 动态裁剪内部填充宽度（实现 1% 实时平滑变化）
    // 保留最左侧外框，根据百分比缩放右侧填充
    CAShapeLayer *maskLayer = (CAShapeLayer *)imageView.layer.mask;
    if (![maskLayer isKindOfClass:[CAShapeLayer class]]) {
        maskLayer = [CAShapeLayer layer];
        imageView.layer.mask = maskLayer;
    }

    CGFloat imgW = imageView.bounds.size.width > 0 ? imageView.bounds.size.width : 26;
    CGFloat imgH = imageView.bounds.size.height > 0 ? imageView.bounds.size.height : 13;

    // 计算内部电量块的缩放比：保留外框（约20%宽度），剩余80%宽度按 1% 准确裁剪
    CGFloat p = fmaxf(0.0f, fminf(1.0f, (float)percent / 100.0f));
    CGFloat visibleWidth = imgW * (0.20f + 0.80f * p);

    UIBezierPath *path = [UIBezierPath bezierPathWithRect:CGRectMake(0, 0, visibleWidth, imgH)];
    maskLayer.path = path.CGPath;
}

%hook CCUIRoundButton

- (void)layoutSubviews {
    %orig;
    
    // 检查父级链是否属于低电量模块
    UIResponder *responder = self;
    BOOL isLowPower = NO;
    while (responder) {
        NSString *clsName = NSStringFromClass([responder class]);
        if ([clsName containsString:@"LowPower"]) {
            isLowPower = YES;
            break;
        }
        responder = [responder nextResponder];
    }

    if (isLowPower) {
        [self cb_updateBatteryIcon];
    }
}

%new
- (void)cb_updateBatteryIcon {
    UpdateRoundButtonBatteryIcon(self);
}

%end

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
