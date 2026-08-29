#import <UIKit/UIKit.h>

@interface CCUICAPackageView : UIView
@property (nonatomic, copy) NSString *packageName;
@end

// Cowbell 核心自定义电池控件
@interface CBCowbellView : UIView
@property (nonatomic, strong) UIView *fillBar;
@property (nonatomic, strong) UILabel *percentLabel;
@end

@implementation CBCowbellView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = [UIColor clearColor];

        // 1. 内部动态电量填充条
        _fillBar = [[UIView alloc] init];
        _fillBar.layer.cornerRadius = 1.0f;
        _fillBar.clipsToBounds = YES;
        [self addSubview:_fillBar];

        // 2. 底部百分比数字
        _percentLabel = [[UILabel alloc] init];
        _percentLabel.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightMedium];
        _percentLabel.textColor = [UIColor whiteColor];
        _percentLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_percentLabel];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    // 获取真实电量 (0.0 ~ 1.0)
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    float level = [UIDevice currentDevice].batteryLevel;
    if (level < 0.0f) level = 1.0f;

    // 获取当前是否开启了低电量模式
    BOOL isLowPowerMode = [[NSProcessInfo processInfo] isLowPowerModeEnabled];

    // 设置百分比文字
    _percentLabel.text = [NSString stringWithFormat:@"%d%%", (int)(level * 100)];
    _percentLabel.frame = CGRectMake(0, self.bounds.size.height - 15.0f, self.bounds.size.width, 14.0f);

    // 电池外框尺寸（精准对齐控制中心 Icon）
    CGFloat iconW = 21.0f;
    CGFloat iconH = 10.5f;
    CGFloat iconX = (self.bounds.size.width - iconW) / 2.0f - 1.0f;
    CGFloat iconY = (self.bounds.size.height - 15.0f - iconH) / 2.0f - 1.0f;

    // 填充条根据电量计算宽度
    CGFloat padding = 1.5f;
    CGFloat maxFillW = iconW - (padding * 2) - 1.5f; // 扣除右侧极耳
    CGFloat currentFillW = maxFillW * level;
    if (currentFillW < 1.0f) currentFillW = 1.0f;

    _fillBar.frame = CGRectMake(iconX + padding, iconY + padding, currentFillW, iconH - (padding * 2));

    // 状态颜色：开启低电量模式时为黄色，正常为白色
    _fillBar.backgroundColor = isLowPowerMode ? [UIColor systemYellowColor] : [UIColor whiteColor];
}

// 绘制原生标准的电池外框与右侧极耳
- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];

    CGFloat iconW = 21.0f;
    CGFloat iconH = 10.5f;
    CGFloat iconX = (self.bounds.size.width - iconW) / 2.0f - 1.0f;
    CGFloat iconY = (self.bounds.size.height - 15.0f - iconH) / 2.0f - 1.0f;

    // 绘制电池主体外框
    UIBezierPath *bodyPath = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(iconX, iconY, iconW - 2.0f, iconH) cornerRadius:3.0f];
    bodyPath.lineWidth = 1.1f;
    [[UIColor whiteColor] setStroke];
    [bodyPath stroke];

    // 绘制右侧极耳 (Cap)
    UIBezierPath *capPath = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(iconX + iconW - 1.5f, iconY + 3.0f, 1.2f, iconH - 6.0f) cornerRadius:0.5f];
    [[UIColor whiteColor] setFill];
    [capPath fill];
}

@end

%hook CCUICAPackageView

- (void)layoutSubviews {
    %orig;

    // 1. 响应链精准判断是否为低电量模块
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

    // 2. 将原本复杂的系统矢量图标设为全透明隐藏
    for (UIView *sub in self.subviews) {
        if (sub.tag != 6666) {
            sub.alpha = 0.0f;
        }
    }

    // 3. 挂载 Cowbell 效果视图
    CBCowbellView *cowbell = [self viewWithTag:6666];
    if (!cowbell) {
        cowbell = [[CBCowbellView alloc] initWithFrame:self.bounds];
        cowbell.tag = 6666;
        [self addSubview:cowbell];
    }

    cowbell.frame = self.bounds;
    [cowbell setNeedsDisplay];
    [cowbell setNeedsLayout];
}

%end
