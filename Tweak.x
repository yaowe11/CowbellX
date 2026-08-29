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

        // 2. 百分比文字
        _percentLabel = [[UILabel alloc] init];
        _percentLabel.font = [UIFont systemFontOfSize:9.3f weight:UIFontWeightRegular];
        _percentLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_percentLabel];

        // 3. 监听状态
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

    BOOL isLowPower = [NSProcessInfo processInfo].isLowPowerModeEnabled;
    UIColor *yellowColor = [UIColor colorWithRed:255/255.0 green:204/255.0 blue:0/255.0 alpha:1.0];
    
    self.percentLabel.textColor = isLowPower ? [UIColor blackColor] : [UIColor whiteColor];
    self.fillView.backgroundColor = isLowPower ? yellowColor : [UIColor whiteColor];

    // 图标整体包含 Cap 的总尺寸
    CGFloat totalW = 32.0f;
    CGFloat iconH = 14.0f;
    CGFloat iconX = (w - totalW) / 2.0f;
    CGFloat iconY = (h - iconH) / 2.0f - 1.0f; 

    // 主体宽度：留出 Cap(1.8f) 和 间隔(1.5f) 的空间
    CGFloat bodyW = totalW - 1.8f - 1.5f; // 28.7f

    // 内部填充条布局
    CGFloat padding = 2.0f;
    CGFloat maxFillW = bodyW - (padding * 2.0f);
    CGFloat currentFillW = maxFillW * level;
    if (currentFillW < 2.0f) currentFillW = 2.0f;
    
    self.fillView.frame = CGRectMake(iconX + padding, iconY + padding, currentFillW, iconH - (padding * 2.0f));
    self.fillView.layer.cornerRadius = 2.0f;
    
    // 百分比文字定位
    self.percentLabel.frame = CGRectMake(0, iconY + iconH + 5.5f, w, 11.0f);
}

- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    if (w <= 0 || h <= 0) return;

    CGFloat totalW = 32.0f;
    CGFloat iconH = 14.0f;
    CGFloat iconX = (w - totalW) / 2.0f;
    CGFloat iconY = (h - iconH) / 2.0f - 1.0f;

    BOOL isLowPower = [NSProcessInfo processInfo].isLowPowerModeEnabled;
    UIColor *strokeColor = isLowPower ? [UIColor blackColor] : [UIColor whiteColor];

    // 1. 绘制电池主体外框 (外框圆角 4.2f，线宽 1.4f)
    CGFloat bodyW = totalW - 1.8f - 1.5f; // 28.7f
    UIBezierPath *bodyPath = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(iconX, iconY, bodyW, iconH) cornerRadius:4.2f];
    bodyPath.lineWidth = 1.4f;
    [strokeColor setStroke];
    [bodyPath stroke];
    
    // 2. 绘制电池正极 Cap（与主体间隔 1.5f，右侧完全圆角弧度，高度 4.8f）
    CGFloat capW = 1.8f;
    CGFloat capH = 4.8f;
    CGFloat capGap = 1.5f; // 原生同款离缝间隔
    CGFloat capX = iconX + bodyW + capGap;
    CGFloat capY = iconY + (iconH - capH) / 2.0f;
    
    UIBezierPath *capPath = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(capX, capY, capW, capH)
                                                  byRoundingCorners:(UIRectCornerTopRight | UIRectCornerBottomRight)
                                                        cornerRadii:CGSizeMake(1.2f, 1.2f)];
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

    // 隐去原生图标
    for (UIView *subview in self.subviews) {
        if (subview.tag != 9999) {
            subview.alpha = 0.0f;
        }
    }

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
