#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface CCUIContentModuleContainerView : UIView
@property (nonatomic, strong) NSString *moduleIdentifier;
@property (nonatomic, strong) UILabel *cbPercentLabel;
- (void)cb_updatePercentText;
- (BOOL)cb_isLowPowerModule;
- (UIImageView *)cb_findActualGlyphImageViewInView:(UIView *)view;
@end

@interface CCUIRoundButton : UIView
@property (nonatomic, strong) UIImageView *glyphImageView;
@end

@interface CCUILabeledRoundButtonViewController : UIViewController
@property (nonatomic, strong) CCUIRoundButton *buttonContainer;
@property (nonatomic, strong) UIImageView *glyphImageView;
@end

%hook CCUIContentModuleContainerView

%property (nonatomic, strong) UILabel *cbPercentLabel;

- (void)layoutSubviews {
    %orig;

    if (![self cb_isLowPowerModule]) {
        if (self.cbPercentLabel) {
            self.cbPercentLabel.hidden = YES;
        }
        return;
    }

    CGFloat width = self.bounds.size.width;
    CGFloat height = self.bounds.size.height;

    if (width <= 0 || height <= 0 || width > 100 || height > 100) return;

    for (UIView *subview in self.subviews) {
        if (subview != self.cbPercentLabel) {
            subview.transform = CGAffineTransformIdentity;
        }
    }

    if (!self.cbPercentLabel) {
        UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(0, height - 22, width, 12)];
        lab.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
        lab.textAlignment = NSTextAlignmentCenter;
        lab.userInteractionEnabled = NO;

        self.cbPercentLabel = lab;
        [self addSubview:lab];

        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(cb_updatePercentText)
                                                     name:UIDeviceBatteryLevelDidChangeNotification
                                                   object:nil];
                                                   
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(cb_updatePercentText)
                                                     name:NSProcessInfoPowerStateDidChangeNotification
                                                   object:nil];
    } else {
        self.cbPercentLabel.hidden = NO;
        self.cbPercentLabel.frame = CGRectMake(0, height - 22, width, 12);
    }

    [self bringSubviewToFront:self.cbPercentLabel];
    [self cb_updatePercentText];
}

%new
- (BOOL)cb_isLowPowerModule {
    if ([self respondsToSelector:@selector(moduleIdentifier)]) {
        NSString *modID = [self performSelector:@selector(moduleIdentifier)];
        if ([modID isEqualToString:@"com.apple.control-center.LowPowerModule"] || 
            [modID containsString:@"LowPowerModule"]) {
            return YES;
        }
    }

    UIResponder *responder = self;
    while (responder) {
        NSString *clsName = NSStringFromClass([responder class]);
        if ([clsName containsString:@"CCUILowPowerModeModule"]) {
            return YES;
        }
        responder = [responder nextResponder];
    }

    return NO;
}

%new
- (UIImageView *)cb_findActualGlyphImageViewInView:(UIView *)view {
    if (!view || view == self.cbPercentLabel) return nil;
    
    if ([view isKindOfClass:[UIImageView class]]) {
        CGSize s = view.bounds.size;
        if (s.width > 10 && s.width < 40 && s.height > 10 && s.height < 40) {
            return (UIImageView *)view;
        }
    }
    
    for (UIView *sub in view.subviews) {
        UIImageView *found = [self cb_findActualGlyphImageViewInView:sub];
        if (found) return found;
    }
    return nil;
}

%new
- (void)cb_updatePercentText {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.cbPercentLabel) return;

        float level = [UIDevice currentDevice].batteryLevel;
        int percent = (level >= 0) ? (int)round(level * 100.0f) : 100;
        self.cbPercentLabel.text = [NSString stringWithFormat:@"%d%%", percent];

        BOOL isLowPowerMode = [NSProcessInfo processInfo].isLowPowerModeEnabled;
        if (isLowPowerMode) {
            self.cbPercentLabel.textColor = [UIColor blackColor];
        } else {
            self.cbPercentLabel.textColor = [UIColor whiteColor];
        }

        UIImageView *glyphImageView = [self cb_findActualGlyphImageViewInView:self];
        if (glyphImageView) {
            NSString *symbolName = @"battery.100";
            if (percent <= 15) {
                symbolName = @"battery.0";
            } else if (percent <= 40) {
                symbolName = @"battery.25";
            } else if (percent <= 65) {
                symbolName = @"battery.50";
            } else if (percent <= 88) {
                symbolName = @"battery.75";
            }

            UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightMedium];
            UIImage *nativeSymbol = [UIImage systemImageNamed:symbolName withConfiguration:config];

            if (nativeSymbol) {
                glyphImageView.image = nativeSymbol;
                glyphImageView.contentMode = UIViewContentModeScaleAspectFit;
            }
        }
    });
}

%end
