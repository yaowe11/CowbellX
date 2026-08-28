#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface CCUIContentModuleContainerView : UIView
@property (nonatomic, strong) NSString *moduleIdentifier;
@property (nonatomic, strong) UILabel *cbPercentLabel;
- (void)cb_updatePercentText;
- (BOOL)cb_isLowPowerModule;
- (UIImageView *)cb_findGlyphImageViewInView:(UIView *)view;
@end

// 动态绘制原生风格、1%精细度的电池图标
static UIImage *DrawNativeBatteryWithLevel(float level) {
    CGSize size = CGSizeMake(24, 12);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull rendererContext) {
        // 1. 外框
        CGRect outerRect = CGRectMake(1, 1, 20, 10);
        UIBezierPath *outerPath = [UIBezierPath bezierPathWithRoundedRect:outerRect cornerRadius:3];
        [[UIColor whiteColor] setStroke];
        outerPath.lineWidth = 1.2;
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

%hook CCUIContentModuleContainerView

%property (nonatomic, strong) UILabel *cbPercentLabel;

- (void)layoutSubviews {
    %orig;

    // 1. 非低电量模块直接隐藏并返回
    if (![self cb_isLowPowerModule]) {
        if (self.cbPercentLabel) {
            self.cbPercentLabel.hidden = YES;
        }
        return;
    }

    CGFloat width = self.bounds.size.width;
    CGFloat height = self.bounds.size.height;

    if (width <= 0 || height <= 0 || width > 100 || height > 100) return;

    // 2. 保持原生子视图 Transform 不变形
    for (UIView *subview in self.subviews) {
        if (subview != self.cbPercentLabel) {
            subview.transform = CGAffineTransformIdentity;
        }
    }

    // 3. 放置百分比文字 Label
    if (!self.cbPercentLabel) {
        UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(0, height - 22, width, 12)];
        lab.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
        lab.textAlignment = NSTextAlignmentCenter;
        lab.userInteractionEnabled = NO;

        self.cbPercentLabel = lab;
        [self addSubview:lab];

        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        
        // 监听电量与低电量开关状态
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

// 递归寻找模块内部原生的图标 UIImageView
%new
- (UIImageView *)cb_findGlyphImageViewInView:(UIView *)view {
    if (!view) return nil;
    
    // 跳过自己创建的 Label
    if (view == self.cbPercentLabel) return nil;
    
    if ([view isKindOfClass:[UIImageView class]]) {
        return (UIImageView *)view;
    }
    
    for (UIView *sub in view.subviews) {
        UIImageView *found = [self cb_findGlyphImageViewInView:sub];
        if (found) return found;
    }
    return nil;
}

%new
- (void)cb_updatePercentText {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.cbPercentLabel) return;

        // 1. 获取并刷新电量百分比
        float level = [UIDevice currentDevice].batteryLevel;
        int percent = (level >= 0) ? (int)round(level * 100.0f) : 100;
        self.cbPercentLabel.text = [NSString stringWithFormat:@"%d%%", percent];

        // 2. 颜色逻辑
        BOOL isLowPowerMode = [NSProcessInfo processInfo].isLowPowerModeEnabled;
        if (isLowPowerMode) {
            self.cbPercentLabel.textColor = [UIColor blackColor];
        } else {
            self.cbPercentLabel.textColor = [UIColor whiteColor];
        }

        // 3. 关键点：定位原生图标 ImageView 并将其替换为 1% 精细度的实时电量图
        UIImageView *glyphImageView = [self cb_findGlyphImageViewInView:self];
        if (glyphImageView) {
            UIImage *dynBattery = DrawNativeBatteryWithLevel(level);
            if (dynBattery) {
                glyphImageView.image = dynBattery;
                glyphImageView.contentMode = UIViewContentModeCenter;
            }
        }
    });
}

%end
