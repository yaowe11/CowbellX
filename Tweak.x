#import <UIKit/UIKit.h>

@interface CCUICAPackageView : UIView
@property (nonatomic, copy) NSString *packageName;
@end

// 自定义动态电池视图：独立于 CAStatePackage
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
        
        // 1. 电量文字（精修比例与字重）
        _percentLabel = [[UILabel alloc] init];
        _percentLabel.font = [UIFont systemFontOfSize:11.0f weight:UIFontWeightSemibold];
        _percentLabel.textColor = [UIColor whiteColor];
        _percentLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_percentLabel];
        
        // 2. 电池内部填充条
        _fillView = [[UIView alloc] init];
        _fillView.backgroundColor = [UIColor whiteColor];
        _fillView.layer.cornerRadius = 1.5f;
        _fillView.clipsToBounds = YES;
        [self addSubview:_fillView];

        // 3. 补全电量实时监听
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

    // 1. 读取实时电量
    float level = [UIDevice currentDevice].batteryLevel;
    if (level < 0) level = 1.0f;
    
    self.percentLabel.text = [NSString stringWithFormat:@"%d%%", (int)round(level * 100)];
    
    // 2. 低电量模式自动黑白反转
    BOOL isLowPower = [NSProcessInfo processInfo].isLowPowerModeEnabled;
    UIColor *themeColor = isLowPower ? [UIColor blackColor] : [UIColor whiteColor];
    
    self.percentLabel.textColor = themeColor;
    self.fillView.backgroundColor = themeColor;

    // 3. 完全对齐理想截图的布局参数
    self.percentLabel.frame = CGRectMake(0, h - 14.0f, w, 13.0f);
    
    CGFloat iconW = 22.0f;
    CGFloat iconH = 11.0f;
    CGFloat iconX = (w - iconW) / 2.0f - 1.0f;
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
    CGFloat iconX = (w - iconW) / 2.0f - 1.0f;
    CGFloat iconY = (h - 14.0f - iconH) / 2.0f - 1.0f;

    BOOL isLowPower = [NSProcessInfo processInfo].isLowPowerModeEnabled;
    UIColor *themeColor = isLowPower ? [UIColor blackColor] : [UIColor whiteColor];

    // 绘制电池主外框
    UIBezierPath *bodyPath = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(iconX, iconY, iconW - 2.0f, iconH) cornerRadius:3.0f];
    bodyPath.lineWidth = 1.2f;
    [themeColor setStroke];
    [bodyPath stroke];
    
    // 绘制电池右侧正极 Cap
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

    // 关键点：隐藏原生的矢量图层（保证二级菜单跟随原生 PackageView 一起彻底隐藏）
    for (UIView *sub in self.subviews) {
        if (sub.tag != 9999) {
            sub.alpha = 0.0f;
        }
    }

    // 挂载理想样式的自定义电池视图
    CBCustomBatteryView *batteryView = [self viewWithTag:9999];
    if (!batteryView) {
        batteryView = [[CBCustomBatteryView alloc] initWithFrame:self.bounds];
        batteryView.tag = 9999;
        batteryView.backgroundColor = [UIColor clearColor];
        [self addSubview:batteryView];
    }

    batteryView.frame = self.bounds;
    
    // 主动更新电量数据，保证划出控制中心时画面最新
    [batteryView updateBatteryData];
}

%end
