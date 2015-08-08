#include "MTKBAvoiding.h"

@implementation MTKBAvoiding
-(void)screenSizeDidChange {
  // default implementation does nothing
}
-(void)adjustContentInset {
  UIScrollView* view=(UIScrollView*)self.view;
  UIEdgeInsets inset=view.contentInset;
  if(inset.bottom!=kbHeight){
    inset.bottom=kbHeight;
    view.contentInset=view.scrollIndicatorInsets=inset;
    [self screenSizeDidChange];
  }
}
-(void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  if(deferAdjust){
    deferAdjust=NO;
    [self adjustContentInset];
  }
}
-(void)viewWillDisappear:(BOOL)animated {
  [super viewWillDisappear:animated];
  deferAdjust=YES;
}
-(void)viewDidLoad {
  NSNotificationCenter* center=[NSNotificationCenter defaultCenter];
  [center addObserver:self selector:@selector(keyboardWillChange:)
   name:UIKeyboardWillShowNotification object:nil];
  [center addObserver:self selector:@selector(keyboardWillChange:)
   name:UIKeyboardWillHideNotification object:nil];
}
-(void)keyboardWillChange:(NSNotification*)note {
  if([note.name isEqualToString:UIKeyboardWillShowNotification]){
    CGRect frame=[[note.userInfo
     objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    kbHeight=UIInterfaceOrientationIsPortrait(
     [UIApplication sharedApplication].statusBarOrientation)?
     frame.size.height:frame.size.width;
  }
  else {kbHeight=0;}
  if(!deferAdjust){[self adjustContentInset];}
}
-(BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
  return YES;
}
-(void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)orientation {
  if(!kbHeight){[self screenSizeDidChange];}
}
-(void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [super dealloc];
}
@end
