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
        
        // 1. 电量填充条
        _fillView = [[UIView alloc] init];
        _fillView.layer.cornerRadius = 2.0f;
        _fillView.clipsToBounds = YES;
        [self addSubview:_fillView];

        // 2. 下方百分比文字（9.3pt Regular）
        _percentLabel = [[UILabel alloc] init];
        _percentLabel.font = [UIFont systemFontOfSize:9.3f weight:UIFontWeightRegular];
        _percentLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_percentLabel];

        // 3. 监听系统电量及低电量状态
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

    // 诉求3：开启低电量模式后，图标与文字变黄（#FFCC00）；关闭时保持纯白
    BOOL isLowPower = [NSProcessInfo processInfo].isLowPowerModeEnabled;
    UIColor *themeColor = isLowPower ? [UIColor colorWithRed:255/255.0 green:204/255.0 blue:0/255.0 alpha:1.0] : [UIColor whiteColor];
    
    self.percentLabel.textColor = themeColor;
    self.fillView.backgroundColor = themeColor;

    // 诉求2：电池整体拉长（38.0f）
    CGFloat iconW = 38.0f;
    CGFloat iconH = 17.0f;
    
    // 诉求1：电池位置往下移（Y轴真正居中，不再上偏）
    CGFloat iconX = (w - iconW) / 2.0f;
    CGFloat iconY = (h - iconH) / 2.0f + 1.0f; 

    // 计算内部填充宽度
    CGFloat padding = 2.5f;
    CGFloat maxFillW = iconW - (padding * 2) - 3.0f;
    CGFloat currentFillW = maxFillW * level;
    if (currentFillW < 2.0f) currentFillW = 2.0f;
    
    self.fillView.frame = CGRectMake(iconX + padding, iconY + padding, currentFillW, iconH - (padding * 2));
    self.fillView.layer.cornerRadius = 2.0f;
    
    // 诉求4：百分比文字再往下移（间距从 2.5pt 拉大到 4.5pt）
    self.percentLabel.frame = CGRectMake(0, iconY + iconH + 4.5f, w, 11.0f);
}

- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    if (w <= 0 || h <= 0) return;

    // 参数保持与 layoutSubviews 一致
    CGFloat iconW = 38.0f;
    CGFloat iconH = 17.0f;
    CGFloat iconX = (w - iconW) / 2.0f;
    CGFloat iconY = (h - iconH) / 2.0f + 1.0f;

    // 诉求3：低电量模式下绘制外框为黄色
    BOOL isLowPower = [NSProcessInfo processInfo].isLowPowerModeEnabled;
    UIColor *strokeColor = isLowPower ? [UIColor colorWithRed:255/255.0 green:204/255.0 blue:0/255.0 alpha:1.0] : [UIColor whiteColor];

    // 绘制拉长后的电池主体外框 (宽38.0)
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

    // 1. 彻底清空原生矢量图标
    for (UIView *subview in self.subviews) {
        if (subview.tag != 9999) {
            subview.alpha = 0.0f;
        }
    }

    // 2. 防高亮与防白底：强制将背景保持透明/默认暗色
    self.backgroundColor = [UIColor clearColor];

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
