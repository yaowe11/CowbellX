#import <UIKit/UIKit.h>

@interface CCUICAPackageView : UIView
@property (nonatomic, copy) NSString *packageName;
@end

// 自定义动态电池视图：独立于 CAStatePackage，原生可靠
@interface CBCustomBatteryView : UIView
@property (nonatomic, assign) float batteryLevel;
@property (nonatomic, strong) UIView *fillView;
@property (nonatomic, strong) UILabel *percentLabel;
@end

@implementation CBCustomBatteryView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.userInteractionEnabled = NO;
        
        // 1. 电量文字
        _percentLabel = [[UILabel alloc] init];
        _percentLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
        _percentLabel.textColor = [UIColor whiteColor];
        _percentLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_percentLabel];
        
        // 2. 电池内部填充条（完全自定义 View，按百分比精准拉伸）
        _fillView = [[UIView alloc] init];
        _fillView.backgroundColor = [UIColor whiteColor];
        _fillView.layer.cornerRadius = 1.5f;
        _fillView.clipsToBounds = YES;
        [self addSubview:_fillView];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    // 布局文字
    _percentLabel.frame = CGRectMake(0, self.bounds.size.height - 14, self.bounds.size.width, 13);
    
    // 读取电量
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    float level = [UIDevice currentDevice].batteryLevel;
    if (level < 0) level = 1.0f;
    
    _percentLabel.text = [NSString stringWithFormat:@"%d%%", (int)(level * 100)];
    
    // 电池框固定尺寸与位置 (根据 60% 截图比例精准对齐)
    CGFloat iconW = 22.0f;
    CGFloat iconH = 11.0f;
    CGFloat iconX = (self.bounds.size.width - iconW) / 2.0f - 1.0f;
    CGFloat iconY = (self.bounds.size.height - 14 - iconH) / 2.0f - 1.0f;
    
    // 内部填充区域 (Padding)
    CGFloat padding = 1.5f;
    CGFloat maxFillW = iconW - (padding * 2) - 1.5f; // 扣除正极极耳
    CGFloat currentFillW = maxFillW * level;
    if (currentFillW < 1.0f) currentFillW = 1.0f;
    
    _fillView.frame = CGRectMake(iconX + padding, iconY + padding, currentFillW, iconH - (padding * 2));
}

// 在自定义视图上直接绘制高精度的电池外框与极耳
- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    
    CGFloat iconW = 22.0f;
    CGFloat iconH = 11.0f;
    CGFloat iconX = (self.bounds.size.width - iconW) / 2.0f - 1.0f;
    CGFloat iconY = (self.bounds.size.height - 14 - iconH) / 2.0f - 1.0f;
    
    // 绘制电池主外框
    UIBezierPath *bodyPath = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(iconX, iconY, iconW - 2.0f, iconH) cornerRadius:3.0f];
    bodyPath.lineWidth = 1.2f;
    [[UIColor whiteColor] setStroke];
    [bodyPath stroke];
    
    // 绘制电池右侧正极 Cap
    UIBezierPath *capPath = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(iconX + iconW - 1.5f, iconY + 3.0f, 1.5f, iconH - 6.0f) cornerRadius:0.5f];
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

    // 关键操作：隐藏原本不听话的矢量 CAStatePackage 图层
    for (UIView *sub in self.subviews) {
        if (sub.tag != 9999) {
            sub.alpha = 0.0f; // 彻底隐去原生图标
        }
    }

    // 挂载我们自定义的完美电池视图
    CBCustomBatteryView *batteryView = [self viewWithTag:9999];
    if (!batteryView) {
        batteryView = [[CBCustomBatteryView alloc] initWithFrame:self.bounds];
        batteryView.tag = 9999;
        batteryView.backgroundColor = [UIColor clearColor];
        [self addSubview:batteryView];
    }

    batteryView.frame = self.bounds;
    [batteryView setNeedsDisplay];
    [batteryView setNeedsLayout];
}

%end
