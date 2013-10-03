//
//  HBIFAppDelegate.m
//  InFolder
//
//  Created by Adam D on 21/09/13.
//  Copyright (c) 2013 HASHBANG Productions. All rights reserved.
//

#import "HBIFAppDelegate.h"
#import "MobileDevice.h"
#import <sys/socket.h>

#define AMSVC_SPRINGBOARD_SERVICES CFSTR("com.apple.springboardservices")

void HBIFDeviceNotificationReceived(am_device_notification_callback_info *info, void *context) {
	[(HBIFAppDelegate *)[NSApplication sharedApplication].delegate deviceNotificationReceivedWithInfo:info];
}

@implementation HBIFAppDelegate

@synthesize window = _window, deviceLabel = _deviceLabel, parentPopupButton = _parentPopupButton, childPopupButton = _childPopupButton, performButton = _performButton, refreshButton = _refreshButton, progressIndicator = _progressIndicator;

#pragma mark - NSApplicationDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
	am_device_notification *deviceNotification;
	AMDeviceNotificationSubscribe(HBIFDeviceNotificationReceived, 0, 0, NULL, &deviceNotification);
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
	return YES;
}

#pragma mark - MobileDevice stuff

- (void)deviceNotificationReceivedWithInfo:(am_device_notification_callback_info *)info {
	switch (info->msg) {
		case ADNCI_MSG_CONNECTED:
		{
			if (_device) {
				break;
			}

			am_device *device = info->dev;
			
			if (AMDeviceConnect(device) == MDERR_OK && AMDeviceIsPaired(device) && AMDeviceValidatePairing(device) == MDERR_OK && AMDeviceStartSession(device) == MDERR_OK) {
				NSString *firmware = [(NSString *)AMDeviceCopyValue(device, 0, CFSTR("ProductVersion")) autorelease];
				
				if (firmware.intValue < 7) {
					NSLog(@"device has incompatible firmware");
					
					[self disconnectFromDevice:device];
					device = NULL;
					
					[[NSAlert alertWithMessageText:NSLocalizedString(@"This device is incompatible.", @"") defaultButton:NSLocalizedString(@"OK", @"") alternateButton:nil otherButton:nil informativeTextWithFormat:NSLocalizedString(@"The device you connected is running iOS %@. It must be running at least iOS 7.", @""), firmware] beginSheetModalForWindow:_window modalDelegate:nil didEndSelector:nil contextInfo:NULL];
					break;
				}
				
				_connection = 0;
				
				if (AMDeviceStartService(device, AMSVC_SPRINGBOARD_SERVICES, &_connection, NULL) != MDERR_OK) {
					NSLog(@"starting SpringBoardServices failed");
					
					[self disconnectFromDevice:device];
					device = NULL;
					
					// there seem to be some false positives, so let's just not tell the user for now.
					// [[NSAlert alertWithMessageText:NSLocalizedString(@"Failed to start the SpringBoardServices service.", @"") defaultButton:NSLocalizedString(@"OK", @"") alternateButton:nil otherButton:nil informativeTextWithFormat:NSLocalizedString(@"Try disconnecting and reconnecting your device. You may also need to unlock your device if it is passcode protected.", @"")] beginSheetModalForWindow:_window modalDelegate:nil didEndSelector:nil contextInfo:NULL];
					break;
				}
				
				AMDeviceRetain(device);
				_device = device;
				
				_deviceLabel.stringValue = [(NSString *)AMDeviceCopyValue(device, 0, CFSTR("DeviceName")) autorelease];
				
				[self getFolderNames];
			}
			
			break;
		}
			
		case ADNCI_MSG_DISCONNECTED:
		{
			if (info->dev != _device) {
				break;
			}
			
			_deviceLabel.stringValue = NSLocalizedString(@"No Device Connected", @"");
			[_parentPopupButton removeAllItems];
			[_childPopupButton removeAllItems];
			
			_parentPopupButton.enabled = NO;
			_childPopupButton.enabled = NO;
			_performButton.enabled = NO;
			_refreshButton.enabled = NO;
			[_progressIndicator stopAnimation:self];
			
			[self disconnectFromDevice:_device];
			_device = NULL;
			_connection = 0;
			break;
		}
		
		default:
			NSLog(@"unknown device notification received: %x", info->msg);
			break;
	}
}

- (void)disconnectFromDevice:(am_device *)device {
	AMDeviceRelease(device);
	AMDeviceStopSession(device);
	AMDeviceDisconnect(device);
}

- (void)sendMessage:(CFDictionaryRef)dictionary {
	NSParameterAssert(dictionary);
	
	CFPropertyListRef data = CFPropertyListCreateData(NULL, dictionary, kCFPropertyListBinaryFormat_v1_0, 0, NULL);
	
	if (data == NULL) {
		[NSException raise:@"HBIFDataSendingException" format:@"data == NULL"];
		return;
	}
	
	CFIndex length = CFDataGetLength(data);
	uint32_t size = 0;
	size = htonl(length);
	
	if (send(_connection, &size, sizeof(uint32_t), 0) != sizeof(size)) {
		[NSException raise:@"HBIFDataSendingException" format:@"sending message size failed"];
		return;
	}
	
	ssize_t bytesSent = 0;
	bytesSent = send(_connection, CFDataGetBytePtr(data), length, 0);
	
	if (bytesSent != length) {
		[NSException raise:@"HBIFDataSendingException" format:@"sending message data failed"];
		return;
	}
	
	CFRelease(data);
}

- (CFArrayRef)sendMessageAndReceiveResponse:(CFDictionaryRef)dictionary {
	[self sendMessage:dictionary];
	
	uint32_t size = 0;
	
	if (recv(_connection, &size, sizeof(size), 0) != sizeof(uint32_t)) {
		[NSException raise:@"HBIFDataReceivingException" format:@"receiving reply size failed"];
		return nil;
	}
	
	size = (uint32_t)ntohl(size);
	
	if (size < 1) {
		[NSException raise:@"HBIFDataReceivingException" format:@"no data received"];
		return nil;
	}
	
	unsigned char *buffer = malloc(size);
	
	if (buffer == NULL) {
		[NSException raise:@"HBIFDataReceivingException" format:@"allocating reply buffer failed"];
		return nil;
	}
	
	uint32_t remaining = size;
	unsigned char *dataBuffer = buffer;
		
	while (remaining) {
		uint32_t received = (uint32_t)recv(_connection, dataBuffer, remaining, 0);
		
		if (received == 0) {
			[NSException raise:@"HBIFDataReceivingException" format:@"reply truncated"];
			return nil;
		}
		
		remaining -= received;
		dataBuffer += received;
	}
	
	CFDataRef data = CFDataCreateWithBytesNoCopy(0, buffer, size, kCFAllocatorNull);
	CFArrayRef response = CFPropertyListCreateWithData(0, data, kCFPropertyListImmutable, NULL, NULL);
	
	CFRelease(data);
	free(buffer);
	
	return response;
}

- (void)getFolderNames {
	@try {
        CFTypeRef keys[2];
        keys[0] = CFSTR("command");
        keys[1] = CFSTR("formatVersion");
        
        CFTypeRef values[2];
        values[0] = CFSTR("getIconState");
        values[1] = CFSTR("2");
        
        CFDictionaryRef message = CFDictionaryCreate(NULL, keys, values, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
		CFArrayRef newIconState = [self sendMessageAndReceiveResponse:message];
        CFRelease(message);
		_iconState = CFArrayCreateMutableCopy(NULL, 0, newIconState);
	} @catch (NSException *exception) {
		[[NSAlert alertWithMessageText:NSLocalizedString(@"Whoops, something went wrong.", @"") defaultButton:NSLocalizedString(@"OK", nil) alternateButton:nil otherButton:nil informativeTextWithFormat:@"%@", exception.reason] beginSheetModalForWindow:_window modalDelegate:nil didEndSelector:nil contextInfo:NULL];
		return;
	}
	
	_folders = CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
	
	for (int pagenum = 0;pagenum < CFArrayGetCount(_iconState);pagenum++) {
        CFArrayRef page = CFArrayGetValueAtIndex(_iconState, pagenum);
		for (int iconnum = 0;iconnum < CFArrayGetCount(page);iconnum++) {
            CFDictionaryRef icon = CFArrayGetValueAtIndex(page, iconnum);
			if (CFStringCompare(CFDictionaryGetValue(icon, CFSTR("listType")), CFSTR("folder"),0)) {
                CFArrayAppendValue(_folders, icon);
				[_parentPopupButton addItemWithTitle:CFDictionaryGetValue(icon, CFSTR("displayName"))];
				[_childPopupButton addItemWithTitle:CFDictionaryGetValue(icon, CFSTR("displayName"))];
			}
		}
	}
	
	if (_childPopupButton.numberOfItems > 1) {
		[_childPopupButton selectItemAtIndex:1];
	}
	
	if (CFArrayGetCount(_folders)) {
		_parentPopupButton.enabled = YES;
		_childPopupButton.enabled = YES;
		_performButton.enabled = YES;
		_refreshButton.enabled = YES;
	}
}

#pragma mark - IBActions

- (IBAction)perform:(id)sender {
	NSDictionary *parentIcon = CFArrayGetValueAtIndex(_folders, _parentPopupButton.indexOfSelectedItem);
	NSDictionary *childIcon = CFArrayGetValueAtIndex(_folders, _childPopupButton.indexOfSelectedItem);
	NSString *parentName = _parentPopupButton.titleOfSelectedItem;
	NSString *childName = _childPopupButton.titleOfSelectedItem;
	
	if (parentIcon == childIcon) {
		[[NSAlert alertWithMessageText:NSLocalizedString(@"Please choose a different child folder.", @"") defaultButton:NSLocalizedString(@"OK", @"") alternateButton:nil otherButton:nil informativeTextWithFormat:NSLocalizedString(@"You can’t move a folder into itself!", @"")] beginSheetModalForWindow:_window modalDelegate:nil didEndSelector:nil contextInfo:NULL];
		return;
	}
	
	[_progressIndicator startAnimation:self];
	_parentPopupButton.enabled = NO;
	_childPopupButton.enabled = NO;
	_performButton.enabled = NO;
	_refreshButton.enabled = NO;
	
	unsigned pageIndex = 0;
	unsigned iconIndex = 0;
	
    CFMutableArrayRef newIconState = CFArrayCreateMutableCopy(NULL, 0, _iconState);
	
	for (int pagenum = 0;pagenum < CFArrayGetCount(_iconState);pagenum++) {
        CFArrayRef page = CFArrayGetValueAtIndex(_iconState, pagenum);
		iconIndex = 0;
		
		for (int iconnum=0;iconnum<CFArrayGetCount(page);iconnum++) {
            CFDictionaryRef icon = CFArrayGetValueAtIndex(page, iconnum);
			if (icon == parentIcon) {
				CFMutableArrayRef mutablePage = CFArrayCreateMutableCopy(NULL, 0, page);
				CFMutableDictionaryRef mutableIcon = CFDictionaryCreateMutableCopy(NULL, 0, icon);
				CFMutableArrayRef mutableList = CFArrayCreateMutableCopy(NULL, 0, CFDictionaryGetValue(mutableIcon, CFSTR("iconLists")));
				
				[mutableList addObject:@[ childIcon ]];
				
				[mutableIcon setObject:mutableList forKey:@"iconLists"];
                CFDictionarySetValue(mutableIcon, CFSTR("iconLists"), mutableList);
				CFRelease(mutableList);
				
				[mutablePage replaceObjectAtIndex:iconIndex withObject:mutableIcon];
				[mutableIcon release];
				
				[newIconState replaceObjectAtIndex:pageIndex withObject:mutablePage];
				[mutablePage release];
			} else if (icon == childIcon) {
				NSMutableArray *mutablePage = page.mutableCopy;
				[mutablePage removeObjectAtIndex:iconIndex];
				[newIconState replaceObjectAtIndex:pageIndex withObject:mutablePage];
				[mutablePage release];
				
				NSUInteger childIconIndex = [_folders indexOfObject:icon];
				[_folders removeObject:icon];
				[_parentPopupButton removeItemAtIndex:childIconIndex];
				[_childPopupButton removeItemAtIndex:childIconIndex];
				
				iconIndex--;
			}
			
			iconIndex++;
		}
		
		pageIndex++;
	}
		
	[self sendMessage:(CFDictionaryRef)[NSDictionary dictionaryWithObjectsAndKeys:
		@"setIconState", @"command",
		newIconState, @"iconState",
		nil]];
	
	[_progressIndicator stopAnimation:self];
	_parentPopupButton.enabled = YES;
	_childPopupButton.enabled = YES;
	_performButton.enabled = YES;
	_refreshButton.enabled = YES;

	[[NSAlert alertWithMessageText:NSLocalizedString(@"Success!", @"") defaultButton:NSLocalizedString(@"OK", @"") alternateButton:nil otherButton:nil informativeTextWithFormat:NSLocalizedString(@"The folder “%@” has successfully been moved into the folder “%@”.", @""), childName, parentName] beginSheetModalForWindow:_window modalDelegate:nil didEndSelector:nil contextInfo:NULL];
	
	_iconState = [newIconState copy];
	
	[newIconState release];
}

- (IBAction)performRefresh:(NSButton *)button {
	[_iconState release];
	
	[self getFolderNames];
}

@end
