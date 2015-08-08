#include "MTController.h"
#include "MTRowView.h"
#include "MTScratchpad.h"
#import "VT100.h"

@interface UIKeyboardImpl
+(id)sharedInstance;
-(BOOL)isShifted;
-(BOOL)isShiftLocked;
-(void)setShift:(BOOL)shift;
@end

static CGColorRef $_createRGBColor(CGColorSpaceRef rgbspace,CFMutableDictionaryRef unique,NSString* str,unsigned int v) {
  if(str){[[NSScanner scannerWithString:str] scanHexInt:&v];}
  const void* existing=CFDictionaryGetValue(unique,(void*)(v&0xffffff));
  return existing?(CGColorRef)CFRetain(existing):
   CGColorCreate(rgbspace,(CGFloat[]){
   ((v>>16)&0xff)/255.,((v>>8)&0xff)/255.,(v&0xff)/255.,1});
}
static CGSize $_screenSize(UIScrollView* view) {
  CGSize size=view.bounds.size;
  UIEdgeInsets inset=view.contentInset;
  size.height-=inset.top+inset.bottom;
  return size;
}
static enum {
  kTapZoneTopLeft,
  kTapZoneTop,
  kTapZoneTopRight,
  kTapZoneLeft,
  kTapZoneCenter,
  kTapZoneRight,
  kTapZoneBottomLeft,
  kTapZoneBottom,
  kTapZoneBottomRight,
} $_tapZone(UIGestureRecognizer* gesture,CGPoint* optr) {
  UIScrollView* view=(UIScrollView*)gesture.view;
  CGPoint origin=[gesture locationInView:view];
  if(optr){*optr=origin;}
  CGPoint offset=view.contentOffset;
  origin.x-=offset.x;
  origin.y-=offset.y;
  CGSize size=$_screenSize(view);
  CGFloat margin=(size.width<size.height?size.width:size.height)/5;
  if(margin<60){margin=60;}
  BOOL right=(origin.x>size.width-margin);
  return (origin.y<margin)?right?kTapZoneTopRight:
   (origin.x<margin)?kTapZoneTopLeft:kTapZoneTop:
   (origin.y>size.height-margin)?right?kTapZoneBottomRight:
   (origin.x<margin)?kTapZoneBottomLeft:kTapZoneBottom:
   right?kTapZoneRight:(origin.x<margin)?kTapZoneLeft:kTapZoneCenter;
}
static NSString* $_getTitle(VT100* terminal) {
  CFStringRef title=terminal.title;
  if(title){return (NSString*)title;}
  title=[terminal copyProcessName];
  NSString* tstr=(title && CFStringGetLength(title))?
   [NSString stringWithFormat:@"<%@>",title]:@"<?>";
  if(title){CFRelease(title);}
  return tstr;
}

@interface MTRespondingTableView : UITableView @end
@implementation MTRespondingTableView
-(BOOL)canBecomeFirstResponder {return YES;}
@end

@implementation MTController
-(id)init {
  if((self=[super init])){
    // set up color palette
    NSUserDefaults* defaults=[NSUserDefaults standardUserDefaults];
    CGColorSpaceRef rgbspace=CGColorSpaceCreateDeviceRGB();
    CFMutableDictionaryRef unique=CFDictionaryCreateMutable(NULL,0,NULL,NULL);
    const unsigned char cvalues[]={0,0x5f,0x87,0xaf,0xd7,1};
    unsigned int i,z=16;
    for (i=0;i<6;i++){
      unsigned int rv=cvalues[i],j;
      CGFloat r=rv/255.;rv<<=16;
      for (j=0;j<6;j++){
        unsigned int gv=cvalues[j],k;
        CGFloat g=gv/255.;gv<<=8;
        for (k=0;k<6;k++){
          unsigned int bv=cvalues[k];
          CFDictionaryAddValue(unique,(void*)(rv|gv|bv),
           colorTable[z++]=CGColorCreate(rgbspace,(CGFloat[]){r,g,bv/255.,1}));
        }
      }
    }
    for (i=0;i<24;i++){
      unsigned int cv=i*10+8;
      CGFloat c=cv/255.;
      CFDictionaryAddValue(unique,(void*)((cv<<16)|(cv<<8)|cv),
       colorTable[z++]=CGColorCreate(rgbspace,(CGFloat[]){c,c,c,1}));
    }
    nullColor=CGColorCreate(rgbspace,(CGFloat[]){0,0,0,0});
    const unsigned int xterm16[]={
     0x000000,0xcd0000,0x00cd00,0xcdcd00,0x0000ee,0xcd00cd,0x00cdcd,0xe5e5e5,
     0x7f7f7f,0xff0000,0x00ff00,0xffff00,0x5c5cff,0xff00ff,0x00ffff,0xffffff};
    NSArray* palette=[defaults stringArrayForKey:@"palette"];
    NSUInteger count=palette.count;
    for (i=0;i<16;i++){
      colorTable[i]=$_createRGBColor(rgbspace,unique,
       (i<count)?[palette objectAtIndex:i]:nil,xterm16[i]);
    }
    bgDefault=$_createRGBColor(rgbspace,unique,
     [defaults stringForKey:@"bgColor"],0x000000);
    bgCursor=$_createRGBColor(rgbspace,unique,
     [defaults stringForKey:@"bgCursorColor"],0x5f5f5f);
    fgDefault=$_createRGBColor(rgbspace,unique,
     [defaults stringForKey:@"fgColor"],0xd7d7d7);
    fgBold=$_createRGBColor(rgbspace,unique,
     [defaults stringForKey:@"fgBoldColor"],0xffffff);
    fgCursor=$_createRGBColor(rgbspace,unique,
     [defaults stringForKey:@"fgCursorColor"],0xe5e5e5);
    CFRelease(rgbspace);
    CFRelease(unique);
    // set up typeface
    ctFont=CTFontCreateWithName(
     (CFStringRef)[defaults stringForKey:@"fontName"]?:CFSTR("Courier"),
     [defaults floatForKey:@"fontSize"]?:10,NULL);
    id advance=[defaults objectForKey:@"columnWidth"];
    unichar mchar='$';// default model character
    if([advance isKindOfClass:[NSString class]]){
      // use a different model character to calculate the column width
      if([advance length]){mchar=[advance characterAtIndex:0];}
    }
    else if((colWidth=[advance floatValue])>0){mchar=0;}
    if(mchar){
      CGGlyph mglyph;
      CTFontGetGlyphsForCharacters(ctFont,&mchar,&mglyph,1);
      colWidth=CTFontGetAdvancesForGlyphs(ctFont,
       kCTFontDefaultOrientation,&mglyph,NULL,1);
    }
    if(![defaults boolForKey:@"fontProportional"]){
      // turn off all optional ligatures
      const int values[]={kCommonLigaturesOffSelector,kRareLigaturesOffSelector,
       kLogosOffSelector,kRebusPicturesOffSelector,kDiphthongLigaturesOffSelector,
       kSquaredLigaturesOffSelector,kAbbrevSquaredLigaturesOffSelector,
       kSymbolLigaturesOffSelector,kContextualLigaturesOffSelector,
       kHistoricalLigaturesOffSelector};
      const size_t nvalues=sizeof(values)/sizeof(int);
      const int key=kLigaturesType;
      CFNumberRef ligkey=CFNumberCreate(NULL,kCFNumberIntType,&key);
      CFMutableArrayRef ffsettings=CFArrayCreateMutable(NULL,nvalues,&kCFTypeArrayCallBacks);
      for (i=0;i<nvalues;i++){
        CFNumberRef ligvalue=CFNumberCreate(NULL,kCFNumberIntType,&values[i]);
        CFDictionaryRef ligsetting=CFDictionaryCreate(NULL,
         (const void*[]){kCTFontFeatureTypeIdentifierKey,kCTFontFeatureSelectorIdentifierKey},
         (const void*[]){ligkey,ligvalue},2,NULL,&kCFTypeDictionaryValueCallBacks);
        CFRelease(ligvalue);
        CFArrayAppendValue(ffsettings,ligsetting);
        CFRelease(ligsetting);
      }
      CFRelease(ligkey);
      // set fixed advance
      CFNumberRef advance=CFNumberCreate(NULL,kCFNumberCGFloatType,&colWidth);
      CFDictionaryRef attrdict=CFDictionaryCreate(NULL,
       (const void*[]){kCTFontFixedAdvanceAttribute,kCTFontFeatureSettingsAttribute},
       (const void*[]){advance,ffsettings},2,NULL,&kCFTypeDictionaryValueCallBacks);
      CFRelease(advance);
      CFRelease(ffsettings);
      CTFontDescriptorRef desc=CTFontDescriptorCreateWithAttributes(attrdict);
      CFRelease(attrdict);
      // try to derive a new font
      CTFontRef font=CTFontCreateCopyWithAttributes(ctFont,0,NULL,desc);
      CFRelease(desc);
      if(font){
        CFRelease(ctFont);
        ctFont=font;
      }
    }
    glyphAscent=CTFontGetAscent(ctFont);
    glyphHeight=glyphAscent+CTFontGetDescent(ctFont);
    glyphMidY=glyphAscent-CTFontGetXHeight(ctFont)/2;
    NSNumber* leading=[defaults objectForKey:@"lineSpacing"];
    rowHeight=glyphHeight+(leading?leading.floatValue:CTFontGetLeading(ctFont));
    CTFontSymbolicTraits traits=CTFontGetSymbolicTraits(ctFont)
     ^kCTFontBoldTrait^kCTFontItalicTrait;
    ctFontBold=CTFontCreateCopyWithSymbolicTraits(ctFont,0,NULL,
     traits,kCTFontBoldTrait)?:CFRetain(ctFont);
    ctFontItalic=CTFontCreateCopyWithSymbolicTraits(ctFont,0,NULL,
     traits,kCTFontItalicTrait)?:CFRetain(ctFont);
    ctFontBoldItalic=CTFontCreateCopyWithSymbolicTraits(ctFont,0,NULL,
     traits,kCTFontBoldTrait^kCTFontItalicTrait)?:CFRetain(ctFont);
    // set up text decoration attributes
    int ul1=kCTUnderlineStyleSingle,ul2=kCTUnderlineStyleDouble;
    ctUnderlineStyleSingle=CFNumberCreate(NULL,kCFNumberIntType,&ul1);
    ctUnderlineStyleDouble=CFNumberCreate(NULL,kCFNumberIntType,&ul2);
    // set up bell sound
    CFBundleRef bundle=CFBundleGetMainBundle();
    CFURLRef soundURL=CFBundleCopyResourceURL(bundle,CFSTR("bell"),CFSTR("caf"),NULL);
    if(soundURL){
      bellSound=AudioServicesCreateSystemSoundID(soundURL,
       &bellSoundID)==kAudioServicesNoError;
      CFRelease(soundURL);
    }
    // set up display
    screenSection=[[NSIndexSet alloc] initWithIndex:0];
    allTerminals=[[NSMutableArray alloc] init];
  }
  return self;
}
-(BOOL)isRunning {
  for (VT100* terminal in allTerminals){
    if(terminal.isRunning){return YES;}
  }
  return NO;
}
-(void)animationDidStop:(NSString*)animationID finished:(NSNumber*)finished context:(UITableView*)tableView {
  if(animationID){
    CGRect frame=tableView.frame;
    frame.origin.x=0;
    tableView.frame=frame;
  }
  [self terminal:activeTerminal changed:NULL
   deleted:NULL inserted:NULL bell:NO];
}
-(void)screenSizeDidChange {
  UITableView* tableView=(UITableView*)self.view;
  CGSize size=$_screenSize(tableView);
  CFIndex width=size.width/colWidth;
  CFIndex height=size.height/rowHeight;
  if(activeTerminal){[activeTerminal setWidth:width height:height];}
  else {
    VT100* terminal=[[VT100 alloc] initWithWidth:width height:height];
    terminal.delegate=self;
    terminal.encoding=kCFStringEncodingUTF8;
    [allTerminals insertObject:terminal atIndex:activeIndex];
    [activeTerminal=terminal release];
  }
  if(previousIndex!=activeIndex){
    CGRect frame=tableView.frame;
    frame.origin.x=frame.size.width*(previousIndex==NSNotFound
     || previousIndex<activeIndex?-1:1);
    [UIView beginAnimations:@"ScreenTransition" context:tableView];
    [UIView setAnimationDelegate:self];
    [UIView setAnimationDidStopSelector:
     @selector(animationDidStop:finished:context:)];
    tableView.frame=frame;
    [UIView commitAnimations];
    previousIndex=activeIndex;
  }
  else {[self animationDidStop:nil finished:nil context:tableView];}
}
-(void)actionSheet:(UIActionSheet*)sheet clickedButtonAtIndex:(NSInteger)index {
  if(index==sheet.cancelButtonIndex){return;}
  NSUInteger count=allTerminals.count;
  if(index==sheet.destructiveButtonIndex){
    [allTerminals removeObjectAtIndex:index=activeIndex];
    if(--count){
      if(index==count){index--;}
      else {previousIndex=NSNotFound;}
    }
  }
  activeIndex=index;
  activeTerminal=(index<count)?[allTerminals objectAtIndex:index]:nil;
  [self screenSizeDidChange];
}
-(BOOL)canBecomeFirstResponder {
  return YES;
}
-(UIKeyboardAppearance)keyboardAppearance {
  return UIKeyboardAppearanceDark;
}
-(UITextAutocapitalizationType)autocapitalizationType {
  return UITextAutocapitalizationTypeNone;
}
-(UITextAutocorrectionType)autocorrectionType {
  return UITextAutocorrectionTypeNo;
}
-(UITextRange*)selectedTextRange {
  return nil;// disable the native arrow keys
}
-(BOOL)hasText {
  return YES;// always enable the backspace key
}
-(void)deleteBackward {
  [activeTerminal sendKey:kVT100KeyBackArrow];
  if(!ctrlLock){
    [[UIMenuController sharedMenuController]
     setMenuVisible:NO animated:YES];
  }
}
-(void)insertText:(NSString*)text {
  if(text.length==1){
    unichar c=[text characterAtIndex:0];
    if(c<0x80){
      [activeTerminal sendKey:((c==0x20 || c>=0x40)
       && [UIMenuController sharedMenuController].menuVisible)?c&0x1f:c];
      text=nil;
    }
  }
  if(text){[activeTerminal sendString:(CFStringRef)text];}
  if(!ctrlLock){
    [[UIMenuController sharedMenuController]
     setMenuVisible:NO animated:YES];
  }
}
-(NSInteger)numberOfSectionsInTableView:(UITableView*)tableView {
  return 1;
}
-(NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
  return activeTerminal.numberOfLines;
}
-(UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)ipath {
  UITableViewCell* cell=[tableView dequeueReusableCellWithIdentifier:@"Cell"];
  MTRowView* rowView;
  if(cell){rowView=(MTRowView*)cell.backgroundView;}
  else {
    cell=[[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
     reuseIdentifier:@"Cell"] autorelease];
    cell.backgroundView=rowView=[[[MTRowView alloc] initWithBackgroundColor:bgDefault
     ascent:glyphAscent height:glyphHeight midY:glyphMidY] autorelease];
  }
  CFIndex length,cursorColumn;
  screen_char_t* ptr=[activeTerminal charactersAtLineIndex:ipath.row
   length:&length cursorColumn:&cursorColumn];
  if(ptr){
    unichar* ucbuf=malloc(length*sizeof(unichar));
    CFIndex i;
    for (i=0;i<length;i++){ucbuf[i]=ptr[i].c?:' ';}
    CFStringRef ucstr=CFStringCreateWithCharactersNoCopy(NULL,ucbuf,length,kCFAllocatorMalloc);
    CFMutableAttributedStringRef string=CFAttributedStringCreateMutable(NULL,length);
    CFAttributedStringBeginEditing(string);
    CFAttributedStringReplaceString(string,CFRangeMake(0,0),ucstr);
    CFRelease(ucstr);// will automatically free(ucbuf)
    CTFontRef fontface=NULL;
    CGColorRef bgcolor=NULL,fgcolor=NULL,stcolor=NULL,ulcolor=NULL;
    CFNumberRef ulstyle=NULL;
    CFIndex ffspan=0,bgcspan=0,fgcspan=0,stcspan=0,ulcspan=0,ulsspan=0;
    for (i=0;i<=length;i++,ptr++){
      CTFontRef ff;
      CGColorRef bgc,fgc,stc,ulc;
      CFNumberRef uls;
      if(i==length){
        ff=NULL;
        bgc=fgc=stc=ulc=NULL;
        uls=NULL;
      }
      else {
        BOOL bold=ptr->weight==kFontWeightBold;
        ff=bold?ptr->italicize?ctFontBoldItalic:ctFontBold:
         ptr->italicize?ctFontItalic:ctFont;
        if(i==cursorColumn){
          bgc=bgCursor;
          fgc=fgCursor;
        }
        else {
          bgc=ptr->bgcolor_isset?colorTable[ptr->bgcolor]:bgDefault;
          fgc=ptr->fgcolor_isset?colorTable[(bold && ptr->fgcolor<8)?
           ptr->fgcolor+8:ptr->fgcolor]:bold?fgBold:fgDefault;
          if(ptr->inverse){
            CGColorRef _fgc=fgc;
            fgc=bgc;
            bgc=_fgc;
          }
        }
        stc=(ptr->strikethrough && fgc!=bgc)?fgc:NULL;
        switch(ptr->underline){
          case kUnderlineSingle:
            ulc=fgc;
            uls=ctUnderlineStyleSingle;
            break;
          case kUnderlineDouble:
            ulc=fgc;
            uls=ctUnderlineStyleDouble;
            break;
          default:
            ulc=NULL;
            uls=NULL;
            break;
        }
        if(ptr->hidden){fgc=nullColor;}
        if(bgc==bgDefault){bgc=NULL;}
      }
      if(fontface==ff){ffspan++;}
      else {
        if(fontface) CFAttributedStringSetAttribute(
         string,CFRangeMake(i-ffspan,ffspan),
         kCTFontAttributeName,fontface);
        fontface=ff;
        ffspan=1;
      }
      if(bgcolor==bgc){bgcspan++;}
      else {
        if(bgcolor) CFAttributedStringSetAttribute(
         string,CFRangeMake(i-bgcspan,bgcspan),
         kMTBackgroundColorAttributeName,bgcolor);
        bgcolor=bgc;
        bgcspan=1;
      }
      if(fgcolor==fgc){fgcspan++;}
      else {
        if(fgcolor) CFAttributedStringSetAttribute(
         string,CFRangeMake(i-fgcspan,fgcspan),
         kCTForegroundColorAttributeName,fgcolor);
        fgcolor=fgc;
        fgcspan=1;
      }
      if(stcolor==stc){stcspan++;}
      else {
        if(stcolor) CFAttributedStringSetAttribute(
         string,CFRangeMake(i-stcspan,stcspan),
         kMTStrikethroughColorAttributeName,stcolor);
        stcolor=stc;
        stcspan=1;
      }
      if(ulcolor==stc){ulcspan++;}
      else {
        if(ulcolor) CFAttributedStringSetAttribute(
         string,CFRangeMake(i-ulcspan,ulcspan),
         kCTUnderlineColorAttributeName,ulcolor);
        ulcolor=ulc;
        ulcspan=1;
      }
      if(ulstyle==uls){ulsspan++;}
      else {
        if(ulstyle) CFAttributedStringSetAttribute(
         string,CFRangeMake(i-ulsspan,ulsspan),
         kCTUnderlineStyleAttributeName,ulstyle);
        ulstyle=uls;
        ulsspan=1;
      }
    }
    CFAttributedStringEndEditing(string);
    [rowView renderString:string];
    CFRelease(string);
  }
  return cell;
}
-(void)handleKeyboardGesture:(UIGestureRecognizer*)gesture {
  if(gesture.state==UIGestureRecognizerStateBegan)
    [self.isFirstResponder?self.view:self becomeFirstResponder];
}
-(void)handleSwipeGesture:(UISwipeGestureRecognizer*)gesture {
  switch(gesture.direction){
    case UISwipeGestureRecognizerDirectionRight:
      if(activeIndex==0){return;}
      activeIndex--;
      break;
    case UISwipeGestureRecognizerDirectionLeft:
      if(activeIndex==allTerminals.count-1){return;}
      activeIndex++;
      break;
    default:return;
  }
  activeTerminal=[allTerminals objectAtIndex:activeIndex];
  [self screenSizeDidChange];
}
-(void)handleTapGesture:(UIGestureRecognizer*)gesture {
  if(!activeTerminal){return;}
  [[UIMenuController sharedMenuController] setMenuVisible:NO animated:YES];
  UIKeyboardImpl* keyboard=[UIKeyboardImpl sharedInstance];
  BOOL shift=keyboard.isShifted;
  VT100Key key;
  switch($_tapZone(gesture,NULL)){
    case kTapZoneTop:key=shift?kVT100KeyPageUp:kVT100KeyUpArrow;break;
    case kTapZoneBottom:key=shift?kVT100KeyPageDown:kVT100KeyDownArrow;break;
    case kTapZoneLeft:key=shift?kVT100KeyHome:kVT100KeyLeftArrow;break;
    case kTapZoneRight:key=shift?kVT100KeyEnd:kVT100KeyRightArrow;break;
    case kTapZoneTopLeft:key=kVT100KeyInsert;break;
    case kTapZoneTopRight:key=kVT100KeyDelete;break;
    case kTapZoneBottomLeft:key=kVT100KeyEsc;break;
    case kTapZoneBottomRight:key=kVT100KeyTab;break;
    default:return;
  }
  [activeTerminal sendKey:key];
  if(shift && !keyboard.isShiftLocked){[keyboard setShift:NO];}
}
-(void)handleHoldGesture:(UIGestureRecognizer*)gesture {
  if(!activeTerminal){return;}
  if(gesture.state==UIGestureRecognizerStateBegan){
    if(repeatTimer){return;}
    UIMenuController* menu=[UIMenuController sharedMenuController];
    [menu setMenuVisible:NO animated:YES];
    VT100Key key;
    CGPoint origin;
    switch($_tapZone(gesture,&origin)){
      case kTapZoneTop:key=kVT100KeyUpArrow;break;
      case kTapZoneBottom:key=kVT100KeyDownArrow;break;
      case kTapZoneLeft:key=kVT100KeyLeftArrow;break;
      case kTapZoneRight:key=kVT100KeyRightArrow;break;
      case kTapZoneTopRight:{
        UIActionSheet* sheet=[[UIActionSheet alloc]
         initWithTitle:nil delegate:self cancelButtonTitle:@"Cancel"
         destructiveButtonTitle:activeTerminal.isRunning?
         @"Force Quit":@"Close Window" otherButtonTitles:nil];
        [sheet showInView:gesture.view];
        [sheet release];
        return;
      }
      case kTapZoneBottomRight:{
        UIActionSheet* sheet=[[UIActionSheet alloc]
         initWithTitle:nil delegate:self cancelButtonTitle:nil
         destructiveButtonTitle:nil otherButtonTitles:nil];
        for (VT100* terminal in allTerminals){
          [sheet addButtonWithTitle:[NSString stringWithFormat:@"%@%d: %@",
           (terminal==activeTerminal)?@"\u2713 ":
           terminal.bellDeferred?@"\u2407 ":@"",
           terminal.processID,$_getTitle(terminal)]];
        }
        [sheet addButtonWithTitle:@"(+)"];
        sheet.cancelButtonIndex=[sheet addButtonWithTitle:@"Cancel"];
        [sheet showInView:gesture.view];
        [sheet release];
        return;
      }
      case kTapZoneCenter:
        ctrlLock=NO;
        [menu setTargetRect:(CGRect){.origin=origin} inView:gesture.view];
        [menu setMenuVisible:YES animated:YES];
      default:return;
    }
    repeatTimer=[[NSTimer scheduledTimerWithTimeInterval:0.1
     target:self selector:@selector(repeatTimerFired:)
     userInfo:[NSNumber numberWithInt:key] repeats:YES] retain];
  }
  else if(gesture.state==UIGestureRecognizerStateEnded){
    if(!repeatTimer){return;}
    [repeatTimer invalidate];
    [repeatTimer release];
    repeatTimer=nil;
  }
}
-(void)repeatTimerFired:(NSTimer*)timer {
  [activeTerminal sendKey:[timer.userInfo intValue]];
}
-(BOOL)canPerformAction:(SEL)action withSender:(UIMenuController*)menu {
  if(!self.isFirstResponder){// keyboard is hidden
    if(!self.view.isFirstResponder){return NO;}
  }
  else if(action==@selector(ctrlLock:)){return !ctrlLock;}
  if(action==@selector(paste:)){
    return [[UIPasteboard generalPasteboard]
     containsPasteboardTypes:UIPasteboardTypeListString];
  }
  return action==@selector(reflow:);
}
-(void)paste:(UIMenuController*)menu {
  [activeTerminal sendString:(CFStringRef)[UIPasteboard generalPasteboard].string];
}
-(void)reflow:(UIMenuController*)menu {
  NSMutableString* content=[NSMutableString string];
  CFIndex count=activeTerminal.numberOfLines,i,blankspan=0;
  for (i=0;i<count;i++){
    CFIndex length,j;
    screen_char_t* ptr=[activeTerminal
     charactersAtLineIndex:i length:&length cursorColumn:NULL];
    while(length && !ptr[length-1].c){length--;}
    if(i && !ptr->wrapped){
      [content appendString:@"\n"];
      if(!length){blankspan++;}
    }
    if(length){
      blankspan=0;
      unichar* ucbuf=malloc(length*sizeof(unichar));
      for (j=0;j<length;j++){ucbuf[j]=ptr[j].c?:0xA0;}
      CFStringRef ucstr=CFStringCreateWithCharactersNoCopy(NULL,ucbuf,length,kCFAllocatorMalloc);
      [content appendString:(NSString*)ucstr];
      CFRelease(ucstr);// will automatically free(ucbuf)
    }
  }
  if(blankspan){
    NSUInteger length=content.length;
    [content deleteCharactersInRange:NSMakeRange(length-blankspan,blankspan)];
  }
  CFStringRef fontName=CTFontCopyFullName(ctFont);
  MTScratchpad* scratch=[[MTScratchpad alloc]
   initWithTitle:$_getTitle(activeTerminal) content:content
   font:[UIFont fontWithName:(NSString*)fontName size:CTFontGetSize(ctFont)]
   textColor:[UIColor colorWithCGColor:fgDefault] refController:self];
  CFRelease(fontName);
  UINavigationController* nav=[[UINavigationController alloc]
   initWithRootViewController:scratch];
  [scratch release];
  nav.navigationBar.barStyle=UIBarStyleBlack;
  [self presentModalViewController:nav animated:YES];
  [nav release];
}
-(void)ctrlLock:(UIMenuController*)menu {
  ctrlLock=menu.menuVisible=YES;
  [menu update];
}
-(void)loadView {
  UITableView* tableView=[[MTRespondingTableView alloc]
   initWithFrame:CGRectMake(0,0,0,0) style:UITableViewStylePlain];
  tableView.allowsSelection=NO;
  tableView.backgroundColor=[UIColor colorWithCGColor:bgDefault];
  const CGFloat* RGB=CGColorGetComponents(bgDefault);
  tableView.indicatorStyle=(RGB[0]>0.5 || RGB[1]>0.5 || RGB[2]>0.5)?
   UIScrollViewIndicatorStyleBlack:UIScrollViewIndicatorStyleWhite;
  tableView.separatorStyle=UITableViewCellSeparatorStyleNone;
  tableView.rowHeight=rowHeight;
  tableView.dataSource=self;
  // install gesture recognizers
  UILongPressGestureRecognizer* kbGesture=[[UILongPressGestureRecognizer alloc]
   initWithTarget:self action:@selector(handleKeyboardGesture:)];
  kbGesture.numberOfTouchesRequired=2;
  [tableView addGestureRecognizer:kbGesture];
  [kbGesture release];
  UISwipeGestureRecognizer* swipeGesture;
  swipeGesture=[[UISwipeGestureRecognizer alloc]
   initWithTarget:self action:@selector(handleSwipeGesture:)];
  swipeGesture.direction=UISwipeGestureRecognizerDirectionLeft;
  [tableView addGestureRecognizer:swipeGesture];
  [swipeGesture release];
  swipeGesture=[[UISwipeGestureRecognizer alloc]
   initWithTarget:self action:@selector(handleSwipeGesture:)];
  swipeGesture.direction=UISwipeGestureRecognizerDirectionRight;
  [tableView addGestureRecognizer:swipeGesture];
  [swipeGesture release];
  UITapGestureRecognizer* tapGesture=[[UITapGestureRecognizer alloc]
   initWithTarget:self action:@selector(handleTapGesture:)];
  [tableView addGestureRecognizer:tapGesture];
  [tapGesture release];
  UILongPressGestureRecognizer* holdGesture=[[UILongPressGestureRecognizer alloc]
   initWithTarget:self action:@selector(handleHoldGesture:)];
  holdGesture.minimumPressDuration=0.25;
  [tableView addGestureRecognizer:holdGesture];
  [holdGesture release];
  [self.view=tableView release];
  // add custom edit menu items
  UIMenuItem* reflowitem=[[UIMenuItem alloc]
   initWithTitle:@"\u2630" action:@selector(reflow:)];
  UIMenuItem* ctrlitem=[[UIMenuItem alloc]
   initWithTitle:@"Ctrl Lock" action:@selector(ctrlLock:)];
  [UIMenuController sharedMenuController].menuItems=[NSArray
   arrayWithObjects:reflowitem,ctrlitem,nil];
  [reflowitem release];
  [ctrlitem release];
}
-(BOOL)terminalShouldReportChanges:(VT100*)terminal {
  return terminal==activeTerminal;
}
-(void)terminal:(VT100*)terminal changed:(CFSetRef)changes deleted:(CFSetRef)deletions inserted:(CFSetRef)insertions bell:(BOOL)bell {
  if(bell && bellSound){AudioServicesPlaySystemSound(bellSoundID);}
  UITableView* tableView=(UITableView*)self.view;
  [UIView setAnimationsEnabled:NO];
  if(changes){
    [tableView beginUpdates];
    unsigned int i;
    for (i=0;i<3;i++){
      CFSetRef iset=(i==0)?changes:(i==1)?deletions:insertions;
      CFIndex count=CFSetGetCount(iset),j;
      id* items=malloc(count*sizeof(id));
      CFSetGetValues(iset,(const void**)items);
      for (j=0;j<count;j++){
        items[j]=[NSIndexPath indexPathForRow:(NSUInteger)items[j] inSection:0];
      }
      NSArray* ipaths=[NSArray arrayWithObjects:items count:count];
      free(items);
      switch(i){
        case 0:[tableView reloadRowsAtIndexPaths:ipaths
         withRowAnimation:UITableViewRowAnimationNone];break;
        case 1:[tableView deleteRowsAtIndexPaths:ipaths
         withRowAnimation:UITableViewRowAnimationNone];break;
        case 2:[tableView insertRowsAtIndexPaths:ipaths
         withRowAnimation:UITableViewRowAnimationNone];break;
      }
    }
    [tableView endUpdates];
  }
  else {
    [tableView reloadSections:screenSection
     withRowAnimation:UITableViewRowAnimationNone];
  }
  [UIView setAnimationsEnabled:YES];
  [tableView scrollToRowAtIndexPath:
   [NSIndexPath indexPathForRow:terminal.numberOfLines-1 inSection:0]
   atScrollPosition:UITableViewScrollPositionBottom animated:NO];
}
-(void)dealloc {
  unsigned int i;
  for (i=0;i<256;i++){CFRelease(colorTable[i]);}
  CFRelease(nullColor);
  CFRelease(bgDefault);
  CFRelease(bgCursor);
  CFRelease(fgDefault);
  CFRelease(fgBold);
  CFRelease(fgCursor);
  CFRelease(ctFont);
  CFRelease(ctFontBold);
  CFRelease(ctFontItalic);
  CFRelease(ctFontBoldItalic);
  CFRelease(ctUnderlineStyleSingle);
  CFRelease(ctUnderlineStyleDouble);
  if(bellSound){AudioServicesDisposeSystemSoundID(bellSoundID);}
  [repeatTimer release];
  [screenSection release];
  [allTerminals release];
  [super dealloc];
}
@end
