//
//  HBIFAppDelegate.h
//  InFolder
//
//  Created by Adam D on 21/09/13.
//  Copyright (c) 2013 HASHBANG Productions. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MobileDevice.h"

@interface HBIFAppDelegate : NSObject <NSApplicationDelegate> {
	NSWindow *_window;
	NSTextField *_deviceLabel;
	NSPopUpButton *_parentPopupButton;
	NSPopUpButton *_childPopupButton;
	NSButton *_performButton;
	NSButton *_refreshButton;
	NSProgressIndicator *_progressIndicator;
	
	CFMutableArrayRef _iconState;
	CFMutableArrayRef _folders;
}

@property (assign) IBOutlet NSWindow *window;
@property (nonatomic, retain) IBOutlet NSTextField *deviceLabel;
@property (nonatomic, retain) IBOutlet NSPopUpButton *parentPopupButton;
@property (nonatomic, retain) IBOutlet NSPopUpButton *childPopupButton;
@property (nonatomic, retain) IBOutlet NSButton *performButton;
@property (nonatomic, retain) IBOutlet NSButton *refreshButton;
@property (nonatomic, retain) IBOutlet NSProgressIndicator *progressIndicator;

- (IBAction)perform:(NSButton *)button;
- (IBAction)performRefresh:(NSButton *)button;
- (void)deviceNotificationReceivedWithInfo:(am_device_notification_callback_info *)info;

@end
