#include "MTScratchpad.h"

@implementation MTScratchpad
-(id)initWithTitle:(NSString*)title content:(NSString*)_content font:(UIFont*)_font textColor:(UIColor*)_textColor refController:(UIViewController*)_refController {
  if((self=[super init])){
    content=[_content retain];
    font=[_font retain];
    textColor=[_textColor retain];
    refController=[_refController retain];
    UINavigationItem* navitem=self.navigationItem;
    navitem.title=title;
    [navitem.leftBarButtonItem=[[UIBarButtonItem alloc]
     initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
     target:self action:@selector(dismiss)] release];
    navitem.rightBarButtonItem=self.editButtonItem;
  }
  return self;
}
-(void)dismiss {
  [self dismissViewControllerAnimated:YES completion:NULL];
}
-(void)setEditing:(BOOL)editing animated:(BOOL)animated {
  [super setEditing:editing animated:animated];
  UITextView* view=(UITextView*)self.view;
  view.editable=editing;
  [view becomeFirstResponder];
}
-(void)loadView {
  UITextView* view=[[UITextView alloc] init];
  view.editable=NO;
  view.autocapitalizationType=UITextAutocapitalizationTypeNone;
  view.autocorrectionType=UITextAutocorrectionTypeNo;
  view.keyboardAppearance=UIKeyboardAppearanceDark;
  UIScrollView* refview=(UIScrollView*)refController.view;
  view.indicatorStyle=refview.indicatorStyle;
  view.backgroundColor=refview.backgroundColor;
  view.text=content;
  view.font=font;
  view.textColor=textColor;
  [self.view=view release];
}
-(void)dealloc {
  [content release];
  [font release];
  [textColor release];
  [refController release];
  [super dealloc];
}
@end
