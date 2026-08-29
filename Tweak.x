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
        _fillBar.layer.cornerRadius = 1.0f;
        _fillBar.clipsToBounds = YES;
        [self addSubview:_fillBar];

        // 2. 百分比文字（瘦长紧凑字号，精确对齐 73% 效果）
        _percentLabel = [[UILabel alloc] init];
        _percentLabel.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightRegular];
        _percentLabel.textColor = [UIColor whiteColor];
        _percentLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_percentLabel];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    // 读取真实电量
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    float level = [UIDevice currentDevice].batteryLevel;
    if (level < 0.0f) level = 1.0f;

    BOOL isLowPowerMode = [[NSProcessInfo processInfo] isLowPowerModeEnabled];

    _percentLabel.text = [NSString stringWithFormat:@"%d%%", (int)(level * 100)];

    // 关键：复刻 73% 截图的精确长宽比 (31 x 13)
    CGFloat iconW = 31.0f; 
    CGFloat iconH = 13.0f; 
    CGFloat labelH = 13.0f; 
    CGFloat spacing = 4.0f; // 拉开间距，让居中感更强

    // 整体垂直绝对居中
    CGFloat totalH = iconH + spacing + labelH;
    CGFloat startY = (self.bounds.size.height - totalH) / 2.0f;
    CGFloat iconX = (self.bounds.size.width - iconW) / 2.0f;

    // 填充条计算
    CGFloat padding = 1.5f;
    CGFloat maxFillW = iconW - (padding * 2) - 2.0f; // 扣除右侧极耳
    CGFloat currentFillW = maxFillW * level;
    if (currentFillW < 1.0f) currentFillW = 1.0f;

    _fillBar.frame = CGRectMake(iconX + padding, startY + padding, currentFillW, iconH - (padding * 2));
    _percentLabel.frame = CGRectMake(0, startY + iconH + spacing, self.bounds.size.width, labelH);

    // 低电量模式自动变黄
    _fillBar.backgroundColor = isLowPowerMode ? [UIColor systemYellowColor] : [UIColor whiteColor];
}

// 绘制扁长比例的电池外框与右侧极耳
- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];

    CGFloat iconW = 31.0f;
    CGFloat iconH = 13.0f;
    CGFloat labelH = 13.0f;
    CGFloat spacing = 4.0f;

    CGFloat totalH = iconH + spacing + labelH;
    CGFloat startY = (self.bounds.size.height - totalH) / 2.0f;
    CGFloat iconX = (self.bounds.size.width - iconW) / 2.0f;

    // 1. 主外框（细线条、完美圆角）
    UIBezierPath *bodyPath = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(iconX, startY, iconW - 2.5f, iconH) cornerRadius:3.2f];
    bodyPath.lineWidth = 1.1f;
    [[UIColor whiteColor] setStroke];
    [bodyPath stroke];

    // 2. 右侧极耳
    UIBezierPath *capPath = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(iconX + iconW - 2.0f, startY + 3.5f, 1.2f, iconH - 7.0f) cornerRadius:0.5f];
    [[UIColor whiteColor] setFill];
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

    // 隐藏系统原生 package 图层
    for (UIView *sub in self.subviews) {
        if (sub.tag != 6666) {
            sub.alpha = 0.0f;
        }
    }

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
