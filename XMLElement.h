//
//  XMLElement
//
//  XMLElement is a read only parser that uses libxml2
//  for the heavy lifting, and provides convenient access
//  to the elements, attributes, and cdata of xml docs
//
//  TODO: Write real documentation
//

@interface XMLElement : NSObject

+ (XMLElement*)rootWithData:(NSData*)data error:(NSError**)error;

@property (readonly) NSString*      name;
@property (readonly) NSString*      cdata;
@property (readonly) NSDictionary*  attributes;

- (XMLElement*)find:(NSString*)query;
- (void)find:(NSString*)query forEach:(void(^)(XMLElement*))block;

@end

@interface XMLElement (Errors)

+ (NSString*)errorDomain;
+ (NSInteger)unknownErrorCode;
+ (NSInteger)parseErrorCode;

@end
