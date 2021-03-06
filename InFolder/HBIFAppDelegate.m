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
#import "CFCrossPlatform-OSX.h"
#import "iMDCrossPlatform-OSX.h"
#import <assert.h>

#define AMSVC_SPRINGBOARD_SERVICES cf_str("com.apple.springboardservices")

void HBIFDeviceNotificationReceived(am_device_notification_callback_info *info, void *context) {
	[(HBIFAppDelegate *)[NSApplication sharedApplication].delegate deviceNotificationReceivedWithInfo:info];
}

am_device *device;
service_conn_t connection;
CFMutableArrayRef iconState;
CFMutableArrayRef folders;

void sendMessage (CFDictionaryRef dictionary) {
	assert(dictionary != NULL);
	
	CFDataRef data = cf_property_list_create_data(NULL, dictionary, 200, 0, NULL);
	
	if (data == NULL) {
		assert(1);
		return;
	}
	
	CFIndex length = cf_data_get_length(data);
	uint32_t size = 0;
	size = htonl(length);
	
	if (send(connection, (const char *)&size, sizeof(uint32_t), 0) != sizeof(size)) {
		assert(1);
		return;
	}
	
	ssize_t bytesSent = 0;
	bytesSent = send(connection, (const char *)cf_data_get_byte_ptr(data), length, 0);
	
	if (bytesSent != length) {
		assert(1);
		return;
	}
	
	cf_release(data);
}

CFArrayRef sendMessageAndReceiveResponse (CFDictionaryRef dictionary){
	sendMessage(dictionary);
    
	uint32_t size = 0;
	
	if (recv(connection, (char *)&size, sizeof(size), 0) != sizeof(uint32_t)) {
		assert(1);
		return nil;
	}
	
	size = (uint32_t)ntohl(size);
	
	if (size < 1) {
		assert(1);
		return nil;
	}
	
	char *buffer = (char *)malloc(size);
	
	if (buffer == NULL) {
		assert(1);
		return nil;
	}
	
	uint32_t remaining = size;
	char *dataBuffer = buffer;
    
	while (remaining) {
		uint32_t received = (uint32_t)recv(connection, dataBuffer, remaining, 0);
		
		if (received == 0) {
			assert(1);
			return nil;
		}
		
		remaining -= received;
		dataBuffer += received;
	}
	
	CFDataRef data = cf_data_create_with_bytes_no_copy(0, (const UInt8 *)buffer, size, lCFAllocatorNull);
	CFArrayRef response = (CFArrayRef)cf_property_list_create_with_data(0, data, 0, NULL, NULL);
	
	cf_release(data);
	free(buffer);
	
	return response;
}

void disconnectFromDevice(am_device *device) {
	am_device_release(device);
	am_device_stop_session(device);
	am_device_disconnect(device);
}

@implementation HBIFAppDelegate

@synthesize window = _window, deviceLabel = _deviceLabel, parentPopupButton = _parentPopupButton, childPopupButton = _childPopupButton, performButton = _performButton, refreshButton = _refreshButton, progressIndicator = _progressIndicator;

#pragma mark - NSApplicationDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
	am_device_notification *deviceNotification;
	am_device_notification_subscribe(HBIFDeviceNotificationReceived, 0, 0, NULL, &deviceNotification);
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
	return YES;
}

#pragma mark - MobileDevice stuff

- (void)deviceNotificationReceivedWithInfo:(am_device_notification_callback_info *)info {
    switch (info->msg) {
        case ADNCI_MSG_CONNECTED: {
			if (device != NULL) {
				break;
			}
            
			device = info->dev;
			am_device_retain(device);
			if (am_device_connect(device) == MDERR_OK && am_device_is_paired(device) && am_device_validate_pairing(device) == MDERR_OK && am_device_start_session(device) == MDERR_OK) {
				CFStringRef firmware = am_device_copy_value(device, 0, cf_str("ProductVersion"));
				if (cf_string_get_int_value(firmware) < 7) {
                    
					disconnectFromDevice(device);
					device = NULL;
#if TARGET_OS_MAC
					[[NSAlert alertWithMessageText:NSLocalizedString(@"This device is incompatible.", @"") defaultButton:NSLocalizedString(@"OK", @"") alternateButton:nil otherButton:nil informativeTextWithFormat:NSLocalizedString(@"The device you connected is running iOS %@. It must be running at least iOS 7.", @""), firmware] beginSheetModalForWindow:_window modalDelegate:nil didEndSelector:nil contextInfo:NULL];
#else
					System::Windows::Forms::MessageBox::Show("This device is incompatible.", "Error", System::Windows::Forms::MessageBoxButtons::OK),
#endif
					cf_release(firmware);
					break;
				}
                cf_release(firmware);
                
				connection = 0;
                
				assert(device != NULL);
				if (am_device_start_service(device, AMSVC_SPRINGBOARD_SERVICES, &connection, NULL) != MDERR_OK) {
                    
                    disconnectFromDevice(device);
					device = NULL;
                    
					// there seem to be some false positives, so let's just not tell the user for now.
#if TARGET_OS_MAC
					//[[NSAlert alertWithMessageText:NSLocalizedString(@"Failed to start the SpringBoardServices service.", @"") defaultButton:NSLocalizedString(@"OK", @"") alternateButton:nil otherButton:nil informativeTextWithFormat:NSLocalizedString(@"Try disconnecting and reconnecting your device. You may also need to unlock your device if it is passcode protected.", @"")] beginSheetModalForWindow:_window modalDelegate:nil didEndSelector:nil contextInfo:NULL];
#else
					//System::Windows::Forms::MessageBox::Show("Failed to start the SpringBoardServices service.", "Try disconnecting and reconnecting your device. You may also need to unlock your device if it is passcode protected.", System::Windows::Forms::MessageBoxButtons::OK);
#endif
					break;
				}
                
				am_device_retain(device);
                
#if TARGET_OS_MAC
				_deviceLabel.stringValue = [(NSString *)am_device_copy_value(device, 0, cf_str("DeviceName")) autorelease];
                
				[self getFolderNames];
#else
				
				const char *modelstr = deviceValueForKey("HardwareModel");
                
				System::String^ model = gcnew System::String(modelstr);
				bool supported = false;
				model = deviceNameFromHardwareModel(model,&supported);
				const char *firmwarearr = deviceValueForKey("ProductVersion");
				System::String^ firmwarestr = gcnew System::String(firmwarearr);
                
				System::String^ connectedText = System::String::Concat("Device Connected: ",model," (",firmwarestr,")");
				InFolder::BackgroundPanel^ backgroundPanel = InFolder::BackgroundPanel::singlePanel;
				backgroundPanel->SetLabelText(connectedText);
				backgroundPanel->SetControlsEnabled(supported);
#endif
			}
			break;
        }
            
        case ADNCI_MSG_DISCONNECTED: {
			if (info->dev != device) {
				break;
			}
			
#if TARGET_OS_MAC
			_deviceLabel.stringValue = NSLocalizedString(@"No Device Connected", @"");
			[_parentPopupButton removeAllItems];
			[_childPopupButton removeAllItems];
			
			_parentPopupButton.enabled = NO;
			_childPopupButton.enabled = NO;
			_performButton.enabled = NO;
			_refreshButton.enabled = NO;
			[_progressIndicator stopAnimation:self];
#else
			InFolder::BackgroundPanel^ backgroundPanel = InFolder::BackgroundPanel::singlePanel;
            backgroundPanel->setChildComboboxItems(gcnew array<System::String ^>{});
			backgroundPanel->setParentComboboxItems(gcnew array<System::String ^>{});
			backgroundPanel->SetLabelText("To begin, please connect your iPhone, iPod touch, or iPad.");
			backgroundPanel->SetControlsEnabled(false);
#endif
            disconnectFromDevice(device);
			device = NULL;
			connection = 0;
            break;
        }
            
        default:
            break;
    }
}

- (void)getFolderNames {
    CFTypeRef keys[2];
    keys[0] = cf_str("command");
    keys[1] = cf_str("formatVersion");
    
    CFTypeRef values[2];
    values[0] = cf_str("getIconState");
    values[1] = cf_str("2");
    
    CFDictionaryRef message = cf_dictionary_create(NULL, keys, values, 2, lCFTypeDictionaryKeyCallBacks, lCFTypeDictionaryValueCallBacks);
    CFArrayRef newIconState = sendMessageAndReceiveResponse(message);
    cf_release(message);
    iconState = cf_array_create_mutable_copy(NULL, 0, newIconState);
    cf_release(newIconState);
	
	folders = cf_array_create_mutable(NULL, 0, lCFTypeArrayCallBacks);
    
#if TARGET_OS_MAC
#else
	InFolder::BackgroundPanel^ backgroundPanel = InFolder::BackgroundPanel::singlePanel;
	backgroundPanel->clearComboBoxItems();
#endif
    
	for (int pagenum = 0;pagenum < cf_array_get_count(iconState);pagenum++) {
        CFArrayRef page = (CFArrayRef)cf_array_get_value_at_index(iconState, pagenum);
		for (int iconnum = 0;iconnum < cf_array_get_count(page);iconnum++) {
            CFDictionaryRef icon = (CFDictionaryRef)cf_array_get_value_at_index(page, iconnum);
            
			if(cf_get_type_id(icon) != cf_dictionary_get_type_id())
				continue;
            
			CFStringRef listType = (CFStringRef)cf_dictionary_get_value(icon, cf_str("listType"));
			if (listType == NULL)
				continue;
            
			if (cf_string_compare(listType, cf_str("folder"),0) == kCFCompareEqualTo) {
                cf_array_append_value(folders, icon);
#if TARGET_OS_MAC
				[_parentPopupButton addItemWithTitle:cf_dictionary_get_value(icon, cf_str("displayName"))];
				[_childPopupButton addItemWithTitle:cf_dictionary_get_value(icon, cf_str("displayName"))];
#else
				char *buf = (char *)malloc(0x21);
				CFStringRef cfDisplayName = (CFStringRef)cf_dictionary_get_value(icon, cf_str("displayName"));
				assert(cf_string_get_cstring(cfDisplayName,buf, 0x20, kCFStringEncodingUTF8) == true);
				System::String^ displayName = gcnew System::String(buf);
				InFolder::BackgroundPanel::singlePanel->InsertComboboxItem(displayName);
#endif
			}
		}
	}
    
#if TARGET_OS_MAC
	if (_childPopupButton.numberOfItems > 1) {
		[_childPopupButton selectItemAtIndex:1];
	}
	
	if (cf_array_get_count(folders)) {
		_parentPopupButton.enabled = YES;
		_childPopupButton.enabled = YES;
		_performButton.enabled = YES;
		_refreshButton.enabled = YES;
	}
#endif
}

#pragma mark - IBActions

- (IBAction)perform:(id)sender {
#if TARGET_OS_MAC
	CFDictionaryRef parentIcon = (CFDictionaryRef)cf_array_get_value_at_index(folders, _parentPopupButton.indexOfSelectedItem);
	CFDictionaryRef childIcon = (CFDictionaryRef)cf_array_get_value_at_index(folders, _childPopupButton.indexOfSelectedItem);
	CFStringRef parentName = (CFStringRef)_parentPopupButton.titleOfSelectedItem;
	CFStringRef childName = (CFStringRef)_childPopupButton.titleOfSelectedItem;
#else
	InFolder::BackgroundPanel^ backgroundPanel = InFolder::BackgroundPanel::singlePanel;
	CFDictionaryRef parentIcon = (CFDictionaryRef)cf_array_get_value_at_index(folders, backgroundPanel->SelectedParentComboBoxIndex());
	CFDictionaryRef childIcon = (CFDictionaryRef)cf_array_get_value_at_index(folders, backgroundPanel->SelectedChildComboBoxIndex());
	CFStringRef parentName = (CFStringRef)cf_string_create_with_cstring(NULL, (char *)System::Runtime::InteropServices::Marshal::StringToHGlobalAnsi(backgroundPanel->SelectedParentComboBoxText()).ToPointer(),kCFStringEncodingUTF8);
	CFStringRef childName = (CFStringRef)cf_string_create_with_cstring(NULL, (char *)System::Runtime::InteropServices::Marshal::StringToHGlobalAnsi(backgroundPanel->SelectedChildComboBoxText()).ToPointer(),kCFStringEncodingUTF8);
#endif
	
	if (parentIcon == childIcon) {
#if TARGET_OS_MAC
		[[NSAlert alertWithMessageText:NSLocalizedString(@"Please choose a different child folder.", @"") defaultButton:NSLocalizedString(@"OK", @"") alternateButton:nil otherButton:nil informativeTextWithFormat:NSLocalizedString(@"You can’t move a folder into itself!", @"")] beginSheetModalForWindow:_window modalDelegate:nil didEndSelector:nil contextInfo:NULL];
#else
		System::Windows::Forms::MessageBox::Show(L"You can’t move a folder into itself!",L"Please choose a different child folder.",System::Windows::Forms::MessageBoxButtons::OK);
#endif
		return;
	}
	
#if TARGET_OS_MAC
	[_progressIndicator startAnimation:self];
	_parentPopupButton.enabled = NO;
	_childPopupButton.enabled = NO;
	_performButton.enabled = NO;
	_refreshButton.enabled = NO;
#else
	backgroundPanel->SetControlsEnabled(false);
#endif
	
	unsigned pageIndex = 0;
	unsigned iconIndex = 0;
	
    CFMutableArrayRef newIconState = cf_array_create_mutable_copy(NULL, 0, iconState);
	
	for (int pagenum = 0;pagenum < cf_array_get_count(iconState);pagenum++) {
        CFArrayRef page = (CFArrayRef)cf_array_get_value_at_index(iconState, pagenum);
		iconIndex = 0;
		
		for (int iconnum=0;iconnum<cf_array_get_count(page);iconnum++) {
            CFDictionaryRef icon = (CFDictionaryRef)cf_array_get_value_at_index(page, iconnum);
			if (icon == parentIcon) {
				CFMutableArrayRef mutablePage = cf_array_create_mutable_copy(NULL, 0, page);
				CFMutableDictionaryRef mutableIcon = cf_dictionary_create_mutable_copy(NULL, 0, icon);
				CFMutableArrayRef mutableList = cf_array_create_mutable_copy(NULL, 0, (CFArrayRef)cf_dictionary_get_value(mutableIcon, cf_str("iconLists")));
				
                CFTypeRef childIconValues[1];
                childIconValues[0] = childIcon;
                CFArrayRef childIconArray = cf_array_create(NULL, childIconValues, 1, lCFTypeArrayCallBacks);
                cf_array_append_value(mutableList, childIconArray);
                cf_release(childIconArray);
				
                cf_dictionary_set_value(mutableIcon, cf_str("iconLists"), mutableList);
				cf_release(mutableList);
				
                cf_array_insert_value_at_index(mutablePage, iconIndex+1,mutableIcon);
                cf_array_remove_value_at_index(mutablePage, iconIndex);
                cf_release(mutableIcon);
				
                cf_array_insert_value_at_index(newIconState, pageIndex+1,mutablePage);
                cf_array_remove_value_at_index(newIconState, pageIndex);
                cf_release(mutablePage);
			} else if (icon == childIcon) {
				CFMutableArrayRef mutablePage = cf_array_create_mutable_copy(NULL, 0, page);
                cf_array_remove_value_at_index(mutablePage, iconIndex);
                
                cf_array_insert_value_at_index(newIconState, pageIndex+1,mutablePage);
                cf_array_remove_value_at_index(newIconState, pageIndex);
                
                cf_release(mutablePage);
				
                CFIndex childIconIndex = 0;
                for (int i=0;i<cf_array_get_count(folders);i++){
                    if (cf_equal(cf_array_get_value_at_index(folders,i),icon)){
                        childIconIndex = i;
                        break;
                    }
                }
                cf_array_remove_value_at_index(folders, childIconIndex);
#ifdef TARGET_OS_MAC
				[_parentPopupButton removeItemAtIndex:childIconIndex];
				[_childPopupButton removeItemAtIndex:childIconIndex];
#else
				getFolderNames();
#endif
				
				iconIndex--;
			}
			
			iconIndex++;
		}
		
		pageIndex++;
	}
    
    CFTypeRef keys[2];
    keys[0] = cf_str("command");
    keys[1] = cf_str("iconState");
    
    CFTypeRef values[2];
    values[0] = cf_str("setIconState");
    values[1] = newIconState;
    
    CFDictionaryRef message = cf_dictionary_create(NULL, keys, values, 2, lCFTypeDictionaryKeyCallBacks, lCFTypeDictionaryValueCallBacks);
	sendMessage(message);
    cf_release(message);
    
#if TARGET_OS_MAC
	[_progressIndicator stopAnimation:self];
	_parentPopupButton.enabled = YES;
	_childPopupButton.enabled = YES;
	_performButton.enabled = YES;
	_refreshButton.enabled = YES;
#else
	backgroundPanel->SetControlsEnabled(true);
#endif
    
#if TARGET_OS_MAC
	[[NSAlert alertWithMessageText:NSLocalizedString(@"Success!", @"") defaultButton:NSLocalizedString(@"OK", @"") alternateButton:nil otherButton:nil informativeTextWithFormat:NSLocalizedString(@"The folder “%@” has successfully been moved into the folder “%@”.", @""), childName, parentName] beginSheetModalForWindow:_window modalDelegate:nil didEndSelector:nil contextInfo:NULL];
#else
	System::Windows::Forms::MessageBox::Show(L"The folder has successfully been moved into the folder.",L"Success!",System::Windows::Forms::MessageBoxButtons::OK);
#endif
	
    iconState = cf_array_create_mutable_copy(NULL, 0, newIconState);
	cf_release(newIconState);
}

- (IBAction)performRefresh:(NSButton *)button {
	cf_release(iconState);
    
	[self getFolderNames];
}

@end
