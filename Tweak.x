#import <UIKit/UIKit.h>

@interface CCUICAPackageView : UIView
@property (nonatomic, copy) NSString *packageName;
@end

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
        _fillBar.layer.cornerRadius = 1.5f;
        _fillBar.clipsToBounds = YES;
        [self addSubview:_fillBar];

        // 2. 电量百分比文字（字号放大）
        _percentLabel = [[UILabel alloc] init];
        _percentLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
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

    BOOL isLowPowerMode = [[NSProcessInfo processInfo] isLowPowerModeEnabled];

    // 1. 设置百分比文字
    _percentLabel.text = [NSString stringWithFormat:@"%d%%", (int)(level * 100)];

    // 2. 调整尺寸（变大）
    CGFloat iconW = 28.0f; // 电池外框宽度放大
    CGFloat iconH = 14.0f; // 电池外框高度放大
    CGFloat labelH = 16.0f; // 文本高度
    CGFloat spacing = 3.0f; // 电池与文字之间的间距

    // 3. 整体垂直居中算法
    CGFloat totalH = iconH + spacing + labelH;
    CGFloat startY = (self.bounds.size.height - totalH) / 2.0f;
    CGFloat iconX = (self.bounds.size.width - iconW) / 2.0f - 1.0f;

    // 4. 填充条尺寸与位置
    CGFloat padding = 2.0f;
    CGFloat maxFillW = iconW - (padding * 2) - 2.0f; // 扣除右侧极耳
    CGFloat currentFillW = maxFillW * level;
    if (currentFillW < 1.0f) currentFillW = 1.0f;

    _fillBar.frame = CGRectMake(iconX + padding, startY + padding, currentFillW, iconH - (padding * 2));
    _percentLabel.frame = CGRectMake(0, startY + iconH + spacing, self.bounds.size.width, labelH);

    // 状态颜色：开启低电量模式时为黄色，正常为白色
    _fillBar.backgroundColor = isLowPowerMode ? [UIColor systemYellowColor] : [UIColor whiteColor];
}

// 绘制放大后的标准电池外框与右侧极耳
- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];

    CGFloat iconW = 28.0f;
    CGFloat iconH = 14.0f;
    CGFloat labelH = 16.0f;
    CGFloat spacing = 3.0f;

    CGFloat totalH = iconH + spacing + labelH;
    CGFloat startY = (self.bounds.size.height - totalH) / 2.0f;
    CGFloat iconX = (self.bounds.size.width - iconW) / 2.0f - 1.0f;

    // 绘制电池主体外框（加大圆角与边框）
    UIBezierPath *bodyPath = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(iconX, startY, iconW - 2.5f, iconH) cornerRadius:3.5f];
    bodyPath.lineWidth = 1.3f;
    [[UIColor whiteColor] setStroke];
    [bodyPath stroke];

    // 绘制右侧极耳 (Cap)
    UIBezierPath *capPath = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(iconX + iconW - 2.0f, startY + 4.0f, 1.5f, iconH - 8.0f) cornerRadius:0.5f];
    [[UIColor whiteColor] setFill];
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

    // 隐藏系统矢量图标
    for (UIView *sub in self.subviews) {
        if (sub.tag != 6666) {
            sub.alpha = 0.0f;
        }
    }

    // 挂载居中放大版视图
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
