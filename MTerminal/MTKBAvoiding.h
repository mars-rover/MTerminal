#import <UIKit/UIKit.h>

@interface MTKBAvoiding : UIViewController {
  CGFloat kbHeight;
  BOOL deferAdjust;
}
-(void)screenSizeDidChange;
@end
