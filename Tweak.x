#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Photos/Photos.h>

@interface CCUICAPackageView : UIView
- (NSString *)cb_dumpLayers:(CALayer *)layer depth:(int)depth;
@end

%hook CCUICAPackageView

- (void)setState:(NSString *)state animated:(BOOL)animated {
    %orig;

    // 1. 抓取层级文本
    NSString *hierarchy = [self cb_dumpLayers:self.layer depth:0];

    // 2. 将图标 View 渲染为图片保存到相册
    UIGraphicsBeginImageContextWithOptions(self.bounds.size, NO, 0.0);
    [self.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    if (image) {
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            [PHAssetChangeRequest creationRequestForAssetFromImage:image];
        } completionHandler:nil];
    }

    // 3. 屏幕弹窗显示抓取到的图层树
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
        while (rootVC.presentedViewController) {
            rootVC = rootVC.presentedViewController;
        }
        
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"CAPackage 内部图层"
                                                                       message:hierarchy
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [rootVC presentViewController:alert animated:YES completion:nil];
    });
}

%new
- (NSString *)cb_dumpLayers:(CALayer *)layer depth:(int)depth {
    if (!layer) return @"";
    
    NSMutableString *result = [NSMutableString string];
    NSMutableString *indent = [NSMutableString string];
    for (int i = 0; i < depth; i++) [indent appendString:@"  "];
    
    NSString *layerName = layer.name ? layer.name : @"<無名>";
    [result appendFormat:@"%@• %@ (%.0fx%.0f)\n", indent, layerName, layer.bounds.size.width, layer.bounds.size.height];
    
    for (CALayer *sub in layer.sublayers) {
        [result appendString:[self cb_dumpLayers:sub depth:depth + 1]];
    }
    return result;
}

%end
