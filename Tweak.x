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
        
        // 1. 电量文字
        _percentLabel = [[UILabel alloc] init];
        _percentLabel.font = [UIFont systemFontOfSize:10.5f weight:UIFontWeightRegular];
        _percentLabel.textColor = [UIColor whiteColor];
        _percentLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_percentLabel];
        
        // 2. 电池内部填充条
        _fillView = [[UIView alloc] init];
        _fillView.backgroundColor = [UIColor whiteColor];
        _fillView.layer.cornerRadius = 1.5f;
        _fillView.clipsToBounds = YES;
        [self addSubview:_fillView];

        // 3. 实时通知监听
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
    UIColor *themeColor = isLowPower ? [UIColor blackColor] : [UIColor whiteColor];
    
    self.percentLabel.textColor = themeColor;
    self.fillView.backgroundColor = themeColor;

    // 大胆放大拉长电池图标 (28x14)
    CGFloat iconW = 28.0f;
    CGFloat iconH = 14.0f;
    CGFloat fontH = 12.0f;
    CGFloat spacing = 4.0f;
    
    // 计算总体高度并向上微调，拉到正中间位置
    CGFloat totalH = iconH + spacing + fontH;
    CGFloat startY = (h - totalH) / 2.0f - 4.0f; // 向上偏移 4pt 居中
    
    CGFloat iconX = (w - iconW) / 2.0f;
    CGFloat iconY = startY;
    
    // 填充条计算
    CGFloat padding = 2.0f;
    CGFloat maxFillW = iconW - (padding * 2) - 2.0f;
    CGFloat currentFillW = maxFillW * level;
    if (currentFillW < 1.0f) currentFillW = 1.0f;
    
    self.fillView.frame = CGRectMake(iconX + padding, iconY + padding, currentFillW, iconH - (padding * 2));
    
    // 文字位置跟随向上
    self.percentLabel.frame = CGRectMake(0, iconY + iconH + spacing, w, fontH);
}

- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    if (w <= 0 || h <= 0) return;

    CGFloat iconW = 28.0f;
    CGFloat iconH = 14.0f;
    CGFloat fontH = 12.0f;
    CGFloat spacing = 4.0f;
    
    CGFloat totalH = iconH + spacing + fontH;
    CGFloat startY = (h - totalH) / 2.0f - 4.0f;
    
    CGFloat iconX = (w - iconW) / 2.0f;
    CGFloat iconY = startY;

    BOOL isLowPower = [NSProcessInfo processInfo].isLowPowerModeEnabled;
    UIColor *themeColor = isLowPower ? [UIColor blackColor] : [UIColor whiteColor];

    // 绘制放大版电池框
    UIBezierPath *bodyPath = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(iconX, iconY, iconW - 2.5f, iconH) cornerRadius:4.0f];
    bodyPath.lineWidth = 1.5f;
    [themeColor setStroke];
    [bodyPath stroke];
    
    // 绘制电池 Cap
    UIBezierPath *capPath = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(iconX + iconW - 2.0f, iconY + 4.0f, 2.0f, iconH - 8.0f) cornerRadius:0.8f];
    [themeColor setFill];
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

    // 只隐藏图标矢量层，保留原生黄色背景
    for (UIView *sub in self.subviews) {
        if (sub.tag != 9999) {
            NSString *clsName = NSStringFromClass([sub class]);
            if ([clsName containsString:@"Package"] || [clsName containsString:@"CA"]) {
                sub.alpha = 0.0f;
            }
        }
    }

    CBCustomBatteryView *batteryView = [self viewWithTag:9999];
    if (!batteryView) {
        batteryView = [[CBCustomBatteryView alloc] initWithFrame:self.bounds];
        batteryView.tag = 9999;
        batteryView.backgroundColor = [UIColor clearColor];
        [self addSubview:batteryView];
    }

    batteryView.frame = self.bounds;
    [batteryView updateBatteryData];
}

%end
