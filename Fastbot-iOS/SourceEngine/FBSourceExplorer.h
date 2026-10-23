#import <XCTest/XCTest.h>
@interface FBSourceExplorer : NSObject
- (BOOL)runWithTestCase:(XCTestCase *)testCase environment:(NSDictionary<NSString *,NSString *> *)environment error:(NSError **)error;
@end
