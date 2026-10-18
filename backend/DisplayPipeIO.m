// Independent implementation. IOAV private API ABI remains unvalidated for writes.
#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <CoreGraphics/CoreGraphics.h>
#import <dlfcn.h>
typedef CFTypeRef (*Create)(CFAllocatorRef,io_service_t);
typedef IOReturn (*Copy)(CFTypeRef,CFDataRef*);
static NSString *hex(NSData *d){const unsigned char *b=d.bytes; NSMutableString *s=[NSMutableString string];for(NSUInteger i=0;i<d.length;i++)[s appendFormat:@"%02x",b[i]];return s;}
static id clean(id x){if([x isKindOfClass:[NSData class]])return hex(x);if([x isKindOfClass:[NSArray class]]){NSMutableArray *a=[NSMutableArray array];for(id v in x)[a addObject:clean(v)];return a;}if([x isKindOfClass:[NSDictionary class]]){NSMutableDictionary *d=[NSMutableDictionary dictionary];for(id k in x)d[[k description]]=clean(x[k]);return d;}return x?:[NSNull null];}
static NSDictionary *props(io_service_t s){CFMutableDictionaryRef p=NULL;if(IORegistryEntryCreateCFProperties(s,&p,kCFAllocatorDefault,0))return @{};return CFBridgingRelease(p);}
static BOOL valid(NSData *d){if(d.length<128||d.length%128)return NO;const unsigned char *b=d.bytes;unsigned char header[]={0,255,255,255,255,255,255,0};if(memcmp(b,header,8)||d.length!=(NSUInteger)(b[126]+1)*128)return NO;for(NSUInteger i=0;i<d.length;i+=128){unsigned sum=0;for(unsigned j=0;j<128;j++)sum+=b[i+j];if(sum%256)return NO;}return YES;}
typedef IOReturn (*Set)(CFTypeRef,uint32_t,CFDataRef);
static int writeTemporary(int argc,const char **argv){
 if(argc!=8||strcmp(argv[7],"I_ACCEPT_UNVALIDATED_PRIVATE_API")||(strcmp(argv[5],"0")&&strcmp(argv[5],"1")))return 20;
 uint32_t mode=(uint32_t)atoi(argv[5]);
 NSData *expected=[NSData dataWithContentsOfFile:@(argv[4])], *candidate=[NSData dataWithContentsOfFile:@(argv[6])];
 if(!valid(expected)||!valid(candidate)||expected.length!=candidate.length||memcmp((const unsigned char*)expected.bytes+8,(const unsigned char*)candidate.bytes+8,10))return 21;
 void *h=dlopen("/System/Library/Frameworks/IOKit.framework/IOKit",RTLD_LAZY|RTLD_LOCAL);Create create=(Create)dlsym(h,"IOAVServiceCreateWithService");Copy copy=(Copy)dlsym(h,"IOAVServiceCopyEDID");Set set=(Set)dlsym(h,"IOAVServiceSetVirtualEDIDMode");if(!create||!copy||!set)return 22;
 io_iterator_t it=0;if(IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching("DCPAVServiceProxy"),&it))return 23;
 io_service_t s,target=0;unsigned matches=0;while((s=IOIteratorNext(it))){uint64_t rid=0;io_string_t path={0};IORegistryEntryGetRegistryEntryID(s,&rid);IORegistryEntryGetPath(s,kIOServicePlane,path);NSString *ridString=[NSString stringWithFormat:@"%llu",rid];if([ridString isEqual:@(argv[2])]&&!strcmp(path,argv[3])&&[props(s)[@"Location"] isEqual:@"External"]){matches++;if(!target){target=s;continue;}}IOObjectRelease(s);}IOObjectRelease(it);if(matches!=1||!target){if(target)IOObjectRelease(target);return 24;}
 CFTypeRef av=create(kCFAllocatorDefault,target);IOObjectRelease(target);if(!av)return 25;CFDataRef before=NULL;IOReturn rc=copy(av,&before);if(rc||!before||![(__bridge NSData*)before isEqual:expected]){if(before)CFRelease(before);CFRelease(av);return 26;}CFRelease(before);
 // Only explicit temporary mode 1/data or mode 0/NULL. Never EEPROM/DDC.
 IOReturn status=set(av,mode,mode?(__bridge CFDataRef)candidate:NULL);
 CFDataRef after=NULL;IOReturn readStatus=copy(av,&after);
 NSDictionary *result=@{@"setterStatus":@(status),@"copyStatus":@(readStatus),@"effectiveEDID":after?hex((__bridge NSData*)after):@"",@"recoveryValidated":@NO};NSData *json=[NSJSONSerialization dataWithJSONObject:result options:0 error:nil];fwrite(json.bytes,1,json.length,stdout);puts("");if(after)CFRelease(after);CFRelease(av);return 0;
}
int main(int argc,const char **argv){@autoreleasepool{
 if(argc==2&&!strcmp(argv[1],"write-preflight")){puts("{\"state\":\"private-api-unvalidated\",\"setterCalled\":false}");return 0;}
 if(argc>=2&&!strcmp(argv[1],"temporary-write"))return writeTemporary(argc,argv);
 if(argc!=2 || strcmp(argv[1],"inventory")){fprintf(stderr,"only read-only inventory supported\n");return 2;}
 void *h=dlopen("/System/Library/Frameworks/IOKit.framework/IOKit",RTLD_LAZY|RTLD_LOCAL);Create create=(Create)dlsym(h,"IOAVServiceCreateWithService");Copy copy=(Copy)dlsym(h,"IOAVServiceCopyEDID");if(!create||!copy)return 3;
 NSMutableArray *services=[NSMutableArray array],*crossbar=[NSMutableArray array],*online=[NSMutableArray array];io_iterator_t it=0;
 if(IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching("DCPAVServiceProxy"),&it))return 4;
 io_service_t s;while((s=IOIteratorNext(it))){NSDictionary *p=props(s);if([p[@"Location"] isEqual:@"External"]){uint64_t rid=0;io_string_t path={0};IORegistryEntryGetRegistryEntryID(s,&rid);IORegistryEntryGetPath(s,kIOServicePlane,path);CFTypeRef av=create(kCFAllocatorDefault,s);if(av){CFDataRef data=NULL;IOReturn rc=copy(av,&data);NSMutableDictionary *d=[@{@"serviceID":[NSString stringWithFormat:@"%llu",rid],@"path":@(path),@"location":@"External",@"copyStatus":@(rc)} mutableCopy];if(data){d[@"edid"]=hex((__bridge NSData*)data);CFRelease(data);}[services addObject:d];CFRelease(av);}}IOObjectRelease(s);}IOObjectRelease(it);
 if(IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching("AppleDisplayConnectionManager"),&it))return 5;
 while((s=IOIteratorNext(it))){[crossbar addObject:clean(props(s))];IOObjectRelease(s);}IOObjectRelease(it);
 uint32_t n=0;if(CGGetOnlineDisplayList(0,NULL,&n)!=kCGErrorSuccess)return 6;CGDirectDisplayID *ids=calloc(n,sizeof(*ids));if(CGGetOnlineDisplayList(n,ids,&n)!=kCGErrorSuccess){free(ids);return 7;}for(uint32_t i=0;i<n;i++){CGDisplayModeRef m=CGDisplayCopyDisplayMode(ids[i]);[online addObject:@{@"id":@(ids[i]),@"builtin":@(CGDisplayIsBuiltin(ids[i])!=0),@"vendor":@(CGDisplayVendorNumber(ids[i])),@"product":@(CGDisplayModelNumber(ids[i])),@"serial":@(CGDisplaySerialNumber(ids[i])),@"refreshHz":@(m?CGDisplayModeGetRefreshRate(m):0),@"pixelWidth":@(m?CGDisplayModeGetPixelWidth(m):0),@"pixelHeight":@(m?CGDisplayModeGetPixelHeight(m):0)}];if(m)CGDisplayModeRelease(m);}free(ids);
 NSDictionary *out=@{@"schema":@1,@"readOnly":@YES,@"services":services,@"crossbar":crossbar,@"online":online};NSError *e=nil;NSData *json=[NSJSONSerialization dataWithJSONObject:out options:NSJSONWritingSortedKeys error:&e];if(!json)return 8;fwrite(json.bytes,1,json.length,stdout);puts("");return 0;
}}
