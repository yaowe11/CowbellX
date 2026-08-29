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
        
        _fillView = [[UIView alloc] init];
        _fillView.layer.cornerRadius = 2.0f;
        _fillView.clipsToBounds = YES;
        [self addSubview:_fillView];

        _percentLabel = [[UILabel alloc] init];
        _percentLabel.font = [UIFont systemFontOfSize:9.3f weight:UIFontWeightRegular];
        _percentLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_percentLabel];

        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(updateBatteryData) name:UIDeviceBatteryLevelDidChangeNotification object:nil];
        [nc addObserver:self selector:@selector(updateBatteryData) name:NSProcessInfoPowerStateDidChangeNotification object:nil];
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
    
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    if (w <= 0 || h <= 0) return;

    float level = [UIDevice currentDevice].batteryLevel;
    if (level < 0) level = 1.0f;
    
    self.percentLabel.text = [NSString stringWithFormat:@"%d%%", (int)round(level * 100)];

    BOOL isLowPower = [NSProcessInfo processInfo].isLowPowerModeEnabled;
    UIColor *themeColor = isLowPower ? [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0] : [UIColor whiteColor];
    
    self.percentLabel.textColor = isLowPower ? [UIColor blackColor] : [UIColor whiteColor];
    self.fillView.backgroundColor = themeColor;

    CGFloat totalW = 32.0f, iconH = 14.0f;
    CGFloat iconX = (w - totalW) / 2.0f, iconY = (h - iconH) / 2.0f - 1.0f; 
    CGFloat bodyW = totalW - 3.3f, padding = 2.0f;

    CGFloat currentFillW = (bodyW - padding * 2.0f) * level;
    if (currentFillW < 2.0f) currentFillW = 2.0f;
    
    self.fillView.frame = CGRectMake(iconX + padding, iconY + padding, currentFillW, iconH - padding * 2.0f);
    self.percentLabel.frame = CGRectMake(0, iconY + iconH + 5.5f, w, 11.0f);
}

- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    if (w <= 0 || h <= 0) return;

    CGFloat totalW = 32.0f, iconH = 14.0f;
    CGFloat iconX = (w - totalW) / 2.0f, iconY = (h - iconH) / 2.0f - 1.0f;

    BOOL isLowPower = [NSProcessInfo processInfo].isLowPowerModeEnabled;
    UIColor *strokeColor = isLowPower ? [UIColor blackColor] : [UIColor whiteColor];

    CGFloat bodyW = totalW - 3.3f;
    UIBezierPath *bodyPath = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(iconX, iconY, bodyW, iconH) cornerRadius:4.2f];
    bodyPath.lineWidth = 1.4f;
    [strokeColor setStroke];
    [bodyPath stroke];
    
    CGFloat capW = 1.8f, capH = 4.8f, capX = iconX + bodyW + 1.5f, capY = iconY + (iconH - capH) / 2.0f;
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

    NSString *pkgName = [self respondsToSelector:@selector(packageName)] ? self.packageName : @"";
    BOOL isLowPower = [pkgName containsString:@"LowPower"] || [pkgName containsString:@"Battery"];

    if (!isLowPower) {
        for (UIResponder *r = self; r; r = r.nextResponder) {
            NSString *cls = NSStringFromClass([r class]);
            if ([cls containsString:@"Brightness"] || [cls containsString:@"Display"]) return;
            if ([cls containsString:@"LowPower"]) { isLowPower = YES; break; }
        }
    }

    if (!isLowPower) return;

    for (UIView *subview in self.subviews) {
        if (subview.tag != 9999) subview.alpha = 0.0f;
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
