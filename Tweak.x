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
        _fillView.layer.cornerRadius = 1.8f;
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

    BOOL isLowPower = [NSProcessInfo processInfo].isLowPowerModeEnabled;
    UIColor *yellowColor = [UIColor colorWithRed:255/255.0 green:204/255.0 blue:0/255.0 alpha:1.0];
    
    // 低电量模式：容量变黄，外框/数字%变黑；关闭时全白
    self.percentLabel.textColor = isLowPower ? [UIColor blackColor] : [UIColor whiteColor];
    self.fillView.backgroundColor = isLowPower ? yellowColor : [UIColor whiteColor];

    // 1. 尺寸调整：宽度收窄至 34.0f，高度保持 14.0f
    CGFloat iconW = 34.0f;
    CGFloat iconH = 14.0f;
    
    CGFloat iconX = (w - iconW) / 2.0f;
    CGFloat iconY = (h - iconH) / 2.0f + 0.5f; 

    // 2. 内部电量填充条计算
    CGFloat padding = 2.0f;
    CGFloat maxFillW = iconW - (padding * 2) - 3.0f;
    CGFloat currentFillW = maxFillW * level;
    if (currentFillW < 2.0f) currentFillW = 2.0f;
    
    self.fillView.frame = CGRectMake(iconX + padding, iconY + padding, currentFillW, iconH - (padding * 2));
    self.fillView.layer.cornerRadius = 1.8f;
    
    // 3. 百分比文字定位
    self.percentLabel.frame = CGRectMake(0, iconY + iconH + 3.5f, w, 11.0f);
}

- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.
