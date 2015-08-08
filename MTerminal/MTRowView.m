#include "MTRowView.h"
#include <libkern/OSAtomic.h>

typedef struct hspan_t {
  volatile int32_t retain_count;
  CGFloat x,width;
} hspan_t;

static hspan_t* hspan_retain(CFAllocatorRef allocator,hspan_t* span) {
  OSAtomicIncrement32Barrier(&span->retain_count);
  return span;
}
static void hspan_release(CFAllocatorRef allocator,hspan_t* span) {
  if(OSAtomicDecrement32Barrier(&span->retain_count)==0){free(span);}
}
static void $_appendSpan(CFMutableDictionaryRef map,CFTypeRef key,CGFloat x,CGFloat width) {
  CFMutableArrayRef spans=(CFMutableArrayRef)CFDictionaryGetValue(map,key);
  if(!spans){
    spans=CFArrayCreateMutable(NULL,0,&(CFArrayCallBacks){
     .retain=(CFArrayRetainCallBack)hspan_retain,
     .release=(CFArrayReleaseCallBack)hspan_release});
    CFDictionaryAddValue(map,key,spans);
    CFRelease(spans);
  }
  hspan_t* span=malloc(sizeof(hspan_t));
  span->retain_count=0;// CFArray will retain it
  span->x=x;
  span->width=width;
  CFArrayAppendValue(spans,span);
}

@implementation MTRowView
-(id)initWithBackgroundColor:(CGColorRef)_bgColor ascent:(CGFloat)_glyphAscent height:(CGFloat)_glyphHeight midY:(CGFloat)_glyphMidY {
  if((self=[super init])){
    bgColor=CGColorRetain(_bgColor);
    glyphAscent=_glyphAscent;
    glyphHeight=_glyphHeight;
    glyphMidY=_glyphMidY;
    bgMap=CFDictionaryCreateMutable(NULL,0,
     &kCFTypeDictionaryKeyCallBacks,
     &kCFTypeDictionaryValueCallBacks);
    stMap=CFDictionaryCreateMutable(NULL,0,
     &kCFTypeDictionaryKeyCallBacks,
     &kCFTypeDictionaryValueCallBacks);
  }
  return self;
}
-(void)renderString:(CFAttributedStringRef)string {
  if(ctLine){
    CFRelease(ctLine);
    CFDictionaryRemoveAllValues(bgMap);
    CFDictionaryRemoveAllValues(stMap);
  }
  ctLine=CTLineCreateWithAttributedString(string);
  CFArrayRef runs=CTLineGetGlyphRuns(ctLine);
  CFIndex nruns=CFArrayGetCount(runs),i;
  CGFloat x=0;
  for (i=0;i<nruns;i++){
    CTRunRef run=CFArrayGetValueAtIndex(runs,i);
    CGFloat width=CTRunGetTypographicBounds(run,
     CFRangeMake(0,0),NULL,NULL,NULL);
    CFDictionaryRef attr=CTRunGetAttributes(run);
    CGColorRef bgcolor=(CGColorRef)CFDictionaryGetValue(
     attr,kMTBackgroundColorAttributeName);
    if(bgcolor){$_appendSpan(bgMap,bgcolor,x,width);}
    CGColorRef stcolor=(CGColorRef)CFDictionaryGetValue(
     attr,kMTStrikethroughColorAttributeName);
    if(stcolor){$_appendSpan(stMap,stcolor,x,width);}
    x+=width;
  }
  [self setNeedsDisplay];
}
-(void)drawRect:(CGRect)drawRect {
  CGContextRef context=UIGraphicsGetCurrentContext();
  CGContextSetFillColorWithColor(context,bgColor);
  CGContextFillRect(context,drawRect);
  // draw background rectangles if necessary
  CFIndex nbg=CFDictionaryGetCount(bgMap);
  if(nbg){
    const void** keys=malloc(nbg*sizeof(CGColorRef));
    const void** values=malloc(nbg*sizeof(CFArrayRef));
    CFDictionaryGetKeysAndValues(bgMap,keys,values);
    CFIndex i;
    for (i=0;i<nbg;i++){
      CFIndex nvalues=CFArrayGetCount(values[i]),nrects=0,j;
      CGRect* rects=malloc(nvalues*sizeof(CGRect));
      for (j=0;j<nvalues;j++){
        hspan_t* span=(hspan_t*)CFArrayGetValueAtIndex(values[i],j);
        CGRect rect=CGRectMake(span->x,0,span->width,glyphHeight);
        if(CGRectIntersectsRect(rect,drawRect)){rects[nrects++]=rect;}
      }
      if(nrects){
        CGContextSetFillColorWithColor(context,(CGColorRef)keys[i]);
        CGContextFillRects(context,rects,nrects);
      }
      free(rects);
    }
    free(keys);
    free(values);
  }
  // draw correctly oriented text
  CGContextSetTextMatrix(context,CGAffineTransformMake(1,0,0,-1,0,0));
  CGContextSetTextPosition(context,0,glyphAscent);
  CTLineDraw(ctLine,context);
  // draw strikethrough lines if necessary
  CFIndex nst=CFDictionaryGetCount(stMap);
  if(nst && glyphMidY>=CGRectGetMinY(drawRect)
   && glyphMidY<=CGRectGetMaxY(drawRect)){
    const void** keys=malloc(nst*sizeof(CGColorRef));
    const void** values=malloc(nst*sizeof(CFArrayRef));
    CFDictionaryGetKeysAndValues(stMap,keys,values);
    CGFloat xmin=CGRectGetMinX(drawRect),xmax=CGRectGetMaxX(drawRect);
    CFIndex i;
    for (i=0;i<nst;i++){
      CFIndex nvalues=CFArrayGetCount(values[i]),j;
      BOOL first=YES;
      for (j=0;j<nvalues;j++){
        hspan_t* span=(hspan_t*)CFArrayGetValueAtIndex(values[i],j);
        CGFloat xstart=span->x,xend=xstart+span->width;
        if((xstart>=xmin || xend>=xmin) && (xstart<=xmax || xend<=xmax)){
          if(first){
            CGContextSetStrokeColorWithColor(context,(CGColorRef)keys[i]);
            first=NO;
          }
          CGContextMoveToPoint(context,xstart,glyphMidY);
          CGContextAddLineToPoint(context,xend,glyphMidY);
          CGContextStrokePath(context);
        }
      }
    }
    free(keys);
    free(values);
  }
}
-(void)dealloc {
  CGColorRelease(bgColor);
  if(ctLine){CFRelease(ctLine);}
  CFRelease(bgMap);
  CFRelease(stMap);
  [super dealloc];
}
@end
