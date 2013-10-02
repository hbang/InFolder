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

- (NSArray *)sendMessageAndReceiveResponse:(CFDictionaryRef)dictionary {
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
	NSArray *response = [(NSArray *)CFPropertyListCreateWithData(0, data, kCFPropertyListImmutable, NULL, NULL) autorelease];
	
	CFRelease(data);
	free(buffer);
	
	return response;
}

- (void)getFolderNames {
	@try {
		NSArray *newIconState = [self sendMessageAndReceiveResponse:(CFDictionaryRef)[NSDictionary dictionaryWithObjectsAndKeys:
			@"getIconState", @"command",
			@"2", @"formatVersion",
			nil]];
		_iconState = [newIconState copy];
	} @catch (NSException *exception) {
		[[NSAlert alertWithMessageText:NSLocalizedString(@"Whoops, something went wrong.", @"") defaultButton:NSLocalizedString(@"OK", nil) alternateButton:nil otherButton:nil informativeTextWithFormat:@"%@", exception.reason] beginSheetModalForWindow:_window modalDelegate:nil didEndSelector:nil contextInfo:NULL];
		return;
	}
	
	_folders = [[NSMutableArray alloc] init];
	
	for (NSArray *page in _iconState) {
		for (NSDictionary *icon in page) {
			if ([icon objectForKey:@"listType"] && [[icon objectForKey:@"listType"] isEqualToString:@"folder"]) {
				[_folders addObject:icon];
				[_parentPopupButton addItemWithTitle:[icon objectForKey:@"displayName"]];
				[_childPopupButton addItemWithTitle:[icon objectForKey:@"displayName"]];
			}
		}
	}
	
	if (_childPopupButton.numberOfItems > 1) {
		[_childPopupButton selectItemAtIndex:1];
	}
	
	if (_folders.count) {
		_parentPopupButton.enabled = YES;
		_childPopupButton.enabled = YES;
		_performButton.enabled = YES;
		_refreshButton.enabled = YES;
	}
}

#pragma mark - IBActions

- (IBAction)perform:(id)sender {
	NSDictionary *parentIcon = [_folders objectAtIndex:_parentPopupButton.indexOfSelectedItem];
	NSDictionary *childIcon = [_folders objectAtIndex:_childPopupButton.indexOfSelectedItem];
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
	
	NSMutableArray *newIconState = [_iconState mutableCopy];
	
	for (NSArray *page in _iconState) {
		iconIndex = 0;
		
		for (NSDictionary *icon in page) {
			if (icon == parentIcon) {
				NSMutableArray *mutablePage = page.mutableCopy;
				NSMutableDictionary *mutableIcon = icon.mutableCopy;
				NSMutableArray *mutableList = ((NSArray *)[mutableIcon objectForKey:@"iconLists"]).mutableCopy;
				
				[mutableList addObject:@[ childIcon ]];
				
				[mutableIcon setObject:mutableList forKey:@"iconLists"];
				[mutableList release];
				
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
