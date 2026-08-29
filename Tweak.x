#import <UIKit/UIKit.h>

@interface CCUICAPackageView : UIView
@property (nonatomic, copy) NSString *packageName;
@end

@interface CBCustomBatteryView : UIView
@property (nonatomic, strong) UIView *fillView;
@property (nonatomic, strong) UILabel *percentLabel;
- (void)updateBatteryData;
@end

@implementation CBCustomBatteryView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = [UIColor clearColor];
        
        // 1. 电量填充块
        _fillView = [[UIView alloc] init];
        _fillView.layer.cornerRadius = 2.0f;
        _fillView.clipsToBounds = YES;
        [self addSubview:_fillView];

        // 2. 百分比文字（9.3pt Regular）
        _percentLabel = [[UILabel alloc] init];
        _percentLabel.font = [UIFont systemFontOfSize:9.3f weight:UIFontWeightRegular];
        _percentLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_percentLabel];

        // 3. 监听电量与低电量状态
        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(updateBatteryData)
                                                     name:UIDeviceBatteryLevelDidChangeNotification
                                                   object:nil];
                                                   
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(updateBatteryData)
                                                     name:NSProcessInfoPowerStateDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)updateBatteryData {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![UIDevice currentDevice].isBatteryMonitoringEnabled) {
            [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        }
        [self setNeedsLayout];
        [self setNeedsDisplay];
    });
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;

    if (w <= 0 || h <= 0) return;

    float level = [UIDevice currentDevice].batteryLevel;
    if (level < 0) level = 1.0f;
    
    self.percentLabel.text = [NSString stringWithFormat:@"%d%%", (int)round(level * 100)];

    // 低电量模式：原生背景会变黄，因此前景色（图标+文字）需设为纯黑；未开启低电量时全白
    BOOL isLowPower = [NSProcessInfo processInfo].isLowPowerModeEnabled;
    UIColor *themeColor = isLowPower ? [UIColor blackColor] : [UIColor whiteColor];
    
    self.percentLabel.textColor = themeColor;
    self.fillView.backgroundColor = themeColor;

    // 电池与文字布局参数
    CGFloat iconW = 34.0f;
    CGFloat iconH = 17.0f;
    
    CGFloat iconX = (w - iconW) / 2.0f;
    CGFloat iconY = (h - iconH) / 2.0f - 2.5f; 

    // 计算内部电量填充条
    CGFloat padding = 2.5f;
    CGFloat maxFillW = iconW - (padding * 2) - 3.0f;
    CGFloat currentFillW = maxFillW * level;
    if (currentFillW < 2.0f) currentFillW = 2.0f;
    
    self.fillView.frame = CGRectMake(iconX + padding, iconY + padding, currentFillW, iconH - (padding * 2));
    self.fillView.layer.cornerRadius = 2.0f;
    
    // 文字定位在电池正下方 2.5pt 处
    self.percentLabel.frame = CGRectMake(0, iconY + iconH + 2.5f, w, 11.0f);
}

- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    if (w <= 0 || h <= 0) return;

    CGFloat iconW = 34.0f;
    CGFloat iconH = 17.0f;
    CGFloat iconX = (w - iconW) / 2.0f;
    CGFloat iconY = (h - iconH) / 2.0f - 2.5f;

    BOOL isLowPower = [NSProcessInfo processInfo].isLowPowerModeEnabled;
    UIColor *strokeColor = isLowPower ? [UIColor blackColor] : [UIColor whiteColor];

    // 绘制电池主体外框
    UIBezierPath *bodyPath = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(iconX, iconY, iconW - 3.0f, iconH) cornerRadius:5.0f];
    bodyPath.lineWidth = 2.0f;
    [strokeColor setStroke];
    [bodyPath stroke];
    
    // 绘制电池正极 Cap
    UIBezierPath *capPath = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(iconX + iconW - 2.5f, iconY + 5.0f, 2.5f, iconH - 10.0f) cornerRadius:1.0f];
    [strokeColor setFill];
    [capPath fill];
}

@end

%hook CCUICAPackageView

- (void)layoutSubviews {
    %orig;

    NSString *pkgName = @"";
    if ([self respondsToSelector:@selector(packageName)]) {
        pkgName = self.packageName ? self.packageName : @"";
    }

    BOOL isLowPower = [pkgName containsString:@"LowPower"] || [pkgName containsString:@"Battery"];

    if (!isLowPower) {
        UIResponder *r = self;
        while (r) {
            NSString *cls = NSStringFromClass([r class]);
            if ([cls containsString:@"Brightness"] || [cls containsString:@"Display"]) return;
            if ([cls containsString:@"LowPower"]) {
                isLowPower = YES;
                break;
            }
            r = r.nextResponder;
        }
    }

    if (!isLowPower) return;

    // 精准清空原生的 CAPackage 矢量绘制，只留下最底层的背景
    for (UIView *subview in self.subviews) {
        if (subview.tag != 9999) {
            subview.alpha = 0.0f;
        }
    }

    CBCustomBatteryView *batteryView = [self viewWithTag:9999];
    if (!batteryView) {
        batteryView = [[CBCustomBatteryView alloc] initWithFrame:self.bounds];
        batteryView.tag = 9999;
        [self addSubview:batteryView];
    }

    batteryView.frame = self.bounds;
    batteryView.alpha = 1.0f;
    [batteryView updateBatteryData];
}

%end
