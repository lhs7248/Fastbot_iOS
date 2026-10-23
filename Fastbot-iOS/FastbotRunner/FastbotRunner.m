#if FASTBOT_SOURCE
#import <XCTest/XCTest.h>
#import "FBSourceExplorer.h"
@interface FastbotRunner : XCTestCase
@end
@implementation FastbotRunner
- (void)testFastbot {
    self.continueAfterFailure=NO;
    NSError *error=nil;
    BOOL completed=[[FBSourceExplorer new] runWithTestCase:self environment:NSProcessInfo.processInfo.environment error:&error];
    XCTAssertTrue(completed,@"%@",error.localizedDescription ?: @"Source exploration failed");
}
@end
#else

//MIT License
//
//** ** **
//The Fastbot-iOS is licensed under the MIT License:
//
//Copyright (c) 2021 Bytedance Inc.
//
//Permission is hereby granted, free of charge, to any person obtaining a copy
//of this software and associated documentation files (the "Software"), to deal
//in the Software without restriction, including without limitation the rights
//to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//copies of the Software, and to permit persons to whom the Software is
//furnished to do so, subject to the following conditions:
//
//The above copyright notice and this permission notice shall be included in all
//copies or substantial portions of the Software.
//
//THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//SOFTWARE.


//  FastbotRunner.m
//  
//  Created by fastbot on 2021/6/6.
//

#import <XCTest/XCTest.h>
#import "fastbot_native.h"

@interface FastbotRunner : XCTestCase

@property (nonatomic, assign) BOOL shouldKeepRunning;
@end

@implementation FastbotRunner

- (void)setUp {
    // Put setup code here. This method is called before the invocation of each test method in the class.
    self.shouldKeepRunning = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(exitRunloop) name:@"fastbot-done" object:nil];
    // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
}

-(void) testFastbot
{
    NSDictionary* startEnv = [[NSProcessInfo processInfo] environment];
    fastbot *fastbot_native = [[Fastbot_native alloc] init:startEnv];
    // Register before starting so system permission alerts use their actual button frames.
    [fastbot_native addUIInterruptionMonitor:^CGRect(NSArray<XCUIElement *> *alerts) {
        NSArray<NSString *> *labels = @[@"使用App时允许", @"使用 App 时允许", @"使用应用时允许", @"允许一次", @"允许", @"Allow While Using App", @"Allow Once", @"Allow", @"好", @"OK"];
        for (XCUIElement *alert in alerts) {
            NSLog(@"PERMISSION_CALLBACK alert=%@", alert.label);
            for (NSString *label in labels) {
                XCUIElement *button = alert.buttons[label];
                if (button.exists) {
                    NSLog(@"PERMISSION_CALLBACK choose=%@ frame=%@", label, NSStringFromCGRect(button.frame));
                    return button.frame;
                }
            }
        }
        return CGRectZero;
    }];
    [fastbot_native start];

    [[NSRunLoop currentRunLoop] addPort:[NSPort port] forMode:NSDefaultRunLoopMode];
    while (self.shouldKeepRunning && [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]]);
}


-(void) testPingNetwork
{
    int count = 180;
    while (count--) {
        NSString *getResponeStr = [netclient get:@{} hostport:-1 hostip:@"http://www.bytedance.com" pathStr:@""];
        if(getResponeStr.length > 10)
        {
            [FBLogger log:@"ping network success"];
            return;
        }
        [FBLogger log:@"By tapping FastbotRunner on the device, the screen of the device would go black for about one minute. During the black screen interval, users should press the home button on the device to go back to the main screen. Wait patiently until the network setting dialog window pops up. Users should allow the pop up request in order to continue."];
        [NSThread sleepForTimeInterval:1.0];
    }
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
}

- (void)exitRunloop {
    self.shouldKeepRunning = NO;
}

@end

#endif
