#import <UIKit/UIKit.h>

@interface CCUICAPackageView : UIView
@property (nonatomic, copy) NSString *packageName;
@property (nonatomic, strong) UILabel *cb_bottomLabel; // 底层文字（白色）
@property (nonatomic, strong) UIView *cb_clipContainer;  // 动态裁剪容器
@property (nonatomic, strong) UILabel *cb_topLabel;    // 顶层文字（黑色，被裁切）
- (void)cb_updatePercent;
@end

%hook CCUICAPackageView

%property (nonatomic, strong) UILabel *cb_bottomLabel;
%property (nonatomic, strong) UIView *cb_clipContainer;
%property (nonatomic, strong) UILabel *cb_topLabel;

- (void)layoutSubviews {
    %orig;

    NSString *pkgName = @"";
    if ([self respondsToSelector:@selector(packageName)]) {
        pkgName = self.packageName ? self.packageName : @"";
    }

    if (![pkgName containsString:@"LowPower"] && ![pkgName containsString:@"Battery"]) {
        return;
    }

    // 1. 初始化双层 Label 和裁剪容器
    if (!self.cb_bottomLabel) {
        // 底层 Label：未被电量覆盖部分显示的颜色（白色）
        self.cb_bottomLabel = [[UILabel alloc] init];
        self.cb_bottomLabel.textColor = [UIColor whiteColor];
        self.cb_bottomLabel.font = [UIFont systemFontOfSize:9.3f weight:UIFontWeightMedium];
        self.cb_bottomLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:self.cb_bottomLabel];

        // 裁剪容器：跟随电量宽度动态伸缩，超出部分直接 Clip
        self.cb_clipContainer = [[UIView alloc] init];
        self.cb_clipContainer.clipsToBounds = YES;
        self.cb_clipContainer.userInteractionEnabled = NO;
        self.cb_clipContainer.backgroundColor = [UIColor clearColor];
        [self addSubview:self.cb_clipContainer];

        // 顶层 Label：被电量覆盖部分显示的颜色（深色/黑色）
        self.cb_topLabel = [[UILabel alloc] init];
        self.cb_topLabel.textColor = [UIColor colorWithWhite:0.05 alpha:1.0];
        self.cb_topLabel.font = [UIFont systemFontOfSize:9.3f weight:UIFontWeightMedium];
        self.cb_topLabel.textAlignment = NSTextAlignmentCenter;
        [self.cb_clipContainer addSubview:self.cb_topLabel];

        // 监听电量与低电量广播
        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(cb_updatePercent)
                                                     name:UIDeviceBatteryLevelDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(cb_updatePercent)
                                                     name:NSProcessInfoPowerStateDidChangeNotification
                                                   object:nil];
        [self cb_updatePercent];
    }

    // 2. 布局与 Clip 范围计算
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    if (w > 0 && h > 0) {
        [self.cb_bottomLabel sizeToFit];
        CGFloat lblW = self.cb_bottomLabel.bounds.size.width;
        CGFloat lblH = self.cb_bottomLabel.bounds.size.height;

        // 文字居中放置在原生图标下方
        CGRect labelFrame = CGRectMake((w - lblW) / 2.0f, h * 0.68f, lblW, lblH);
        self.cb_bottomLabel.frame = labelFrame;

        // 获取当前电量百分比 (0.0 ~ 1.0)
        float level = [UIDevice currentDevice].batteryLevel;
        if (level < 0) level = 1.0f;

        // 计算裁剪容器的宽度（按整体宽度与电量比例计算）
        CGFloat clipWidth = w * level;
        self.cb_clipContainer.frame = CGRectMake(0, 0, clipWidth, h);

        // 顶层 Label 必须使用与底层 Label 完全一致的 absolute frame，确保字形精准重合
        self.cb_topLabel.frame = labelFrame;
    }
}

%new
- (void)cb_updatePercent {
    dispatch_async(dispatch_get_main_queue(), ^{
        float level = [UIDevice currentDevice].batteryLevel;
        if (level < 0) level = 1.0f;
        NSString *text = [NSString stringWithFormat:@"%d%%", (int)round(level * 100)];

        if (self.cb_bottomLabel && self.cb_topLabel) {
            self.cb_bottomLabel.text = text;
            self.cb_topLabel.text = text;
            [self setNeedsLayout];
        }
    });
}

%end
