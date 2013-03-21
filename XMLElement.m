//
// Copyright 2013 Aaron Sittig. All rights reserved
// All code is governed by the BSD-style license at
// http://github.com/aaron--/xmlelement
//

#import "XMLElement.h"
#import <libxml2/libxml/parser.h>
#import <libxml2/libxml/tree.h>

NSError* XMLElementErrorForXMLError(xmlError* error);
void XMLElementSilenceErrors(void * ctx, const char * msg, ...);
static xmlGenericErrorFunc silence = &XMLElementSilenceErrors;

@interface XMLDoc : NSObject
@property xmlDoc* ref; // Wrap xmlDoc to get reference counting
@end

@implementation XMLDoc

+ (XMLDoc*)docWithData:(NSData*)data error:(NSError**)error
{
  return [[XMLDoc alloc] initWithData:data error:error];
}

- (id)initWithData:(NSData*)data error:(NSError**)error
{
  xmlParserCtxt*  context;
  xmlError*       parseError;
  xmlDoc*         document;

  if(!(self = [super init])) return nil;
  
  // Silence Errors
  initGenericErrorDefaultFunc(&silence);
  
  // Parse Data
  context = xmlNewParserCtxt();
  document = xmlCtxtReadMemory(context, [data bytes], (int)data.length, "", nil, 0);
  
  // Handle Parse Error
  if(!document) {
    parseError = xmlCtxtGetLastError(context);
    if(parseError && error)
      *error = XMLElementErrorForXMLError(parseError);
    xmlResetLastError();
    xmlFreeDoc(document);
    xmlFreeParserCtxt(context);
    return nil;
  }
  
  // Cleanup and Return
  xmlFreeParserCtxt(context);
  self.ref = document;
  return self;
}

- (void)dealloc
{
  // The xmlDoc tree will only get dealloc'd when
  // the last XMLElement with a reference to this
  // XMLDoc is deallocated. The xmlDoc tree is
  // only created when making an element from
  // xml data, not by elements made by searches
  xmlFreeDoc(self.ref);
}

@end

@interface XMLElement ()
@property XMLDoc*               doc;
@property xmlNode*              node;
@property NSString*             nameCache;
@property NSString*             cdataCache;
@property NSMutableDictionary*  attributesCache;
@end

@implementation XMLElement

+ (XMLElement*)rootWithData:(NSData*)data error:(NSError**)error
{
  return [[XMLElement alloc] initWithData:data error:error];
}

- (id)initWithData:(NSData*)data error:(NSError**)error
{
  XMLDoc*   document;
  
  // Convert Data to XMLDoc
  document = [XMLDoc docWithData:data error:error];
  if(*error) return nil;
  
  // Call through to designated init
  if(!(self = [self initWithDoc:document node:nil])) return nil;
  return self;
}

- (id)initWithDoc:(XMLDoc*)doc node:(xmlNode*)node
{
  if(!(self = [super init])) return nil;
  self.doc = doc;
  self.node = node ? node : xmlDocGetRootElement(doc.ref);
  return self;
}

- (NSString*)name
{
  // Build Cache
  if(!self.nameCache) {
    self.nameCache = [NSString stringWithUTF8String:(const char*)self.node->name];
  }
  
  // Return Cache
  return self.nameCache;
}

- (NSString*)cdata
{
  xmlChar*  content;
  
  // Build Cache
  if(!self.cdataCache) {
    content = xmlNodeGetContent(self.node);
    self.cdataCache = content ? [NSString stringWithUTF8String:(const char*)content] : @"";
    xmlFree(content);
  }
  
  // Return Cache
  return self.cdataCache;
}

- (NSDictionary*)attributes
{
  NSString*   attrKey;
  NSString*   attrValue;
  xmlChar*    xmlValue;
  
  // Build Cache
  if(!self.attributesCache) {
    self.attributesCache = [NSMutableDictionary dictionary];
    for(xmlAttrPtr attr = self.node->properties; attr != nil; attr = attr->next) {
      xmlValue  = xmlGetProp(self.node, attr->name);
      attrKey   = [NSString stringWithUTF8String:(const char*)attr->name];
      attrValue = [NSString stringWithUTF8String:(const char*)xmlValue];
      if(xmlValue)xmlFree(xmlValue);
      [self.attributesCache setObject:attrValue forKey:attrKey];
    }
  }
  
  // Return Cache
  return self.attributesCache;
}

- (XMLElement*)find:(NSString*)query
{
  return [self find:query from:self.node];
}

- (void)find:(NSString*)query forEach:(void(^)(XMLElement* element))block
{
  [self find:query from:self.node forEach:block];
}

- (XMLElement*)find:(NSString*)query from:(xmlNode*)from
{
  NSArray*    components;
  NSString*   tagName;
  xmlChar*    tagNameXML;
  xmlNode*    cursor;
  NSString*   newQuery;
  XMLElement*   found;
  
  // Require Query
  if(!query) return nil;
  
  // Parse Query and Init Cursor
  components = [query componentsSeparatedByString:@"."];
  cursor = from;
  
  // Current Query Component Name
  tagName = (NSString*)components[0];
  tagNameXML = (xmlChar*)[tagName UTF8String];
  
  // For Single Component Iterate through Children with Tag Name (Base Case)
  if(components.count == 1) {
    
    // Loop and Invoke block, but Filter first by Name unless Wildcard
    cursor = cursor->children;
    do {
      if(!cursor) continue;
      if(cursor->type != XML_ELEMENT_NODE) continue;
      if(xmlStrcmp(cursor->name, tagNameXML) && ![tagName isEqual:@"*"]) continue;
      return [[XMLElement alloc] initWithDoc:self.doc node:cursor];
    }
    while(( cursor = cursor->next ));
  }
  
  // For Multiple Components, Recurse Down
  if(components.count > 1) {
    components = [components subarrayWithRange:NSMakeRange(1, components.count-1)];
    newQuery = [components componentsJoinedByString:@"."];
    
    // Recurse with Shortened Query for Every Node that matches component
    cursor = cursor->children;
    do {
      if(!cursor) continue;
      if(cursor->type != XML_ELEMENT_NODE) continue;
      if(xmlStrcmp(cursor->name, tagNameXML) && ![tagName isEqual:@"*"]) continue;
      found = [self find:newQuery from:cursor];
      if(found) return found;
    }
    while(( cursor = cursor->next ));
  }
  
  // No matches found
  return nil;
}

- (void)find:(NSString*)query from:(xmlNode*)from forEach:(void(^)(XMLElement*))block
{
  NSArray*    components;
  NSString*   tagName;
  xmlChar*    tagNameXML;
  xmlNode*    cursor;
  NSString*   newQuery;
  
  // Require Query and Block
  if(!query) return;
  if(!block) return;
  
  // Parse Query and Init Cursor
  components = [query componentsSeparatedByString:@"."];
  cursor = from;
  
  // Current Query Component Name
  tagName = (NSString*)components[0];
  tagNameXML = (xmlChar*)[tagName UTF8String];
  
  // For Single Component Iterate through Children with Tag Name (Base Case)
  if(components.count == 1) {
    
    // Loop and Invoke block, but Filter first by Name unless Wildcard
    cursor = cursor->children;
    do {
      if(!cursor) continue;
      if(cursor->type != XML_ELEMENT_NODE) continue;
      if(xmlStrcmp(cursor->name, tagNameXML) && ![tagName isEqual:@"*"]) continue;
      block([[XMLElement alloc] initWithDoc:self.doc node:cursor]);
    }
    while(( cursor = cursor->next ));
  }
  
  // For Multiple Components, Recurse Down
  if(components.count > 1) {
    components = [components subarrayWithRange:NSMakeRange(1, components.count-1)];
    newQuery = [components componentsJoinedByString:@"."];
    
    // Recurse with Shortened Query for Every Node that matches component
    cursor = cursor->children;
    do {
      if(!cursor) continue;
      if(cursor->type != XML_ELEMENT_NODE) continue;
      if(xmlStrcmp(cursor->name, tagNameXML) && ![tagName isEqual:@"*"]) continue;
      [self find:newQuery from:cursor forEach:block];
    }
    while(( cursor = cursor->next ));
  }
}

#pragma mark - Errors

+ (NSString*)errorDomain      { return @"com.makesay.XMLElementError"; }
+ (NSInteger)unknownErrorCode { return 0; }
+ (NSInteger)parseErrorCode   { return 1; }
+ (NSInteger)findErrorCode    { return 2; }

@end

NSError* XMLElementErrorForXMLError(xmlError* error)
{
  NSString*   lineText;
  NSString*   message;
  NSInteger   errorCode;
  
  // Require Valid Error
  if(!error) return nil;
  
  // User Readable Message String
  lineText = error->line ? [NSString stringWithFormat:@"Line %d: ", error->line] : @"";
  message = [NSString stringWithUTF8String:error->message];
  message = [lineText stringByAppendingString:message];
  
  // Error Code Mapping
  switch(error->domain) {
    case XML_FROM_PARSER: errorCode = XMLElement.parseErrorCode;   break;
    default:              errorCode = XMLElement.unknownErrorCode; break;
  }
  
  return [NSError errorWithDomain:XMLElement.errorDomain
                             code:errorCode
                         userInfo:@{NSLocalizedDescriptionKey: message}];
}

void XMLElementSilenceErrors(void * ctx, const char * msg, ...) { }

