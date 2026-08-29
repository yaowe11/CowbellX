#import <UIKit/UIKit.h>

@interface CCUICAPackageView : UIView
@property (nonatomic, copy) NSString *packageName;
@end

// 自定义动态电池视图
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
        
        // 1. 电量文字（9.5pt Regular）
        _percentLabel = [[UILabel alloc] init];
        _percentLabel.font = [UIFont systemFontOfSize:9.5f weight:UIFontWeightRegular];
        _percentLabel.textColor = [UIColor whiteColor];
        _percentLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_percentLabel];
        
        // 2. 电池内部填充条
        _fillView = [[UIView alloc] init];
        _fillView.backgroundColor = [UIColor whiteColor];
        _fillView.layer.cornerRadius = 1.0f;
        _fillView.clipsToBounds = YES;
        [self addSubview:_fillView];

        // 3. 核心修复：开启系统电量监控并注册通知，实现真正的实时刷新
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

        // 强行重绘与布局，实时更新百分比和线条颜色
        [self setNeedsLayout];
        [self setNeedsDisplay];
    });
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;

    if (w <= 0 || h <= 0) return;

    // 1. 读取电量
    float level = [UIDevice currentDevice].batteryLevel;
    if (level < 0) level = 1.0f;
    
    self.percentLabel.text = [NSString stringWithFormat:@"%d%%", (int)round(level * 100)];
    
    // 2. 颜色自动反转：低电量模式开启（黄色背景）时切为黑字/黑框，关闭时切为白字/白框
    BOOL isLowPower = [NSProcessInfo processInfo].isLowPowerModeEnabled;
    UIColor *themeColor = isLowPower ? [UIColor blackColor] : [UIColor whiteColor];
    
    self.percentLabel.textColor = themeColor;
    self.fillView.backgroundColor = themeColor;

    // 3. 精准布局
    self.percentLabel.frame = CGRectMake(0, h - 14.0f, w, 13.0f);
    
    CGFloat iconW = 22.0f;
    CGFloat iconH = 11.0f;
    CGFloat iconX = (w - iconW) / 2.0f - 0.5f;
    CGFloat iconY = (h - 14.0f - iconH) / 2.0f - 1.0f;
    
    CGFloat padding = 1.5f;
    CGFloat maxFillW = iconW - (padding * 2) - 1.5f;
    CGFloat currentFillW = maxFillW * level;
    if (currentFillW < 1.0f) currentFillW = 1.0f;
    
    self.fillView.frame = CGRectMake(iconX + padding, iconY + padding, currentFillW, iconH - (padding * 2));
}

- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    if (w <= 0 || h <= 0) return;

    CGFloat iconW = 22.0f;
    CGFloat iconH = 11.0f;
    CGFloat iconX = (w - iconW) / 2.0f - 0.5f;
    CGFloat iconY = (h - 14.0f - iconH) / 2.0f - 1.0f;

    BOOL isLowPower = [NSProcessInfo processInfo].isLowPowerModeEnabled;
    UIColor *themeColor = isLowPower ? [UIColor blackColor] : [UIColor whiteColor];

    // 绘制电池外框
    UIBezierPath *bodyPath = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(iconX, iconY, iconW - 2.0f, iconH) cornerRadius:3.0f];
    bodyPath.lineWidth = 1.2f;
    [themeColor setStroke];
    [bodyPath stroke];
    
    // 绘制电池正极 Cap
    UIBezierPath *capPath = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(iconX + iconW - 1.5f, iconY + 3.0f, 1.5f, iconH - 6.0f) cornerRadius:0.5f];
    [themeColor setFill];
    [capPath fill];
}

@end

%hook CCUICAPackageView

- (void)layoutSubviews {
    %orig;

    // 精准识别低电量模块
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

    // 隐藏原生的矢量图层
    for (UIView *sub in self.subviews) {
        if (sub.tag != 9999) {
            sub.alpha = 0.0f;
        }
    }

    // 挂载自定义电池视图
    CBCustomBatteryView *batteryView = [self viewWithTag:9999];
    if (!batteryView) {
        batteryView = [[CBCustomBatteryView alloc] initWithFrame:self.bounds];
        batteryView.tag = 9999;
        batteryView.backgroundColor = [UIColor clearColor];
        [self addSubview:batteryView];
    }

    batteryView.frame = self.bounds;
    
    // 刷新数据并强制绘制
    [batteryView updateBatteryData];
}

%end
