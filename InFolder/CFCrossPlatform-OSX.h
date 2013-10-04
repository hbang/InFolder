//
//  CrossPlatformWrapper-OSX.h
//  SemiRestore
//
//  Created by CoolStar on 6/5/13.
//  Copyright (c) 2013 CoolStar Organization. All rights reserved.
//

#ifndef CrossPlatform_OSX_h
#define CrossPlatform_OSX_h

#pragma mark CFType
#define cf_equal CFEqual
#define cf_release CFRelease

#pragma mark CFString
#define cf_str CFSTR
#define cf_string_compare CFStringCompare
#define cf_string_get_int_value CFStringGetIntValue

#pragma mark CFPropertyList
#define cf_property_list_create_data CFPropertyListCreateData
#define cf_property_list_create_with_data CFPropertyListCreateWithData

#pragma mark CFData
#define cf_data_create_with_bytes_no_copy CFDataCreateWithBytesNoCopy
#define cf_data_get_length CFDataGetLength
#define cf_data_get_byte_ptr CFDataGetBytePtr

#pragma mark CFArray
#define cf_array_create CFArrayCreate
#define cf_array_create_copy CFArrayCreateCopy
#define cf_array_create_mutable CFArrayCreateMutable
#define cf_array_create_mutable_copy CFArrayCreateMutableCopy
#define cf_array_get_count CFArrayGetCount
#define cf_array_get_value_at_index CFArrayGetValueAtIndex
#define cf_array_append_value CFArrayAppendValue
#define cf_array_insert_value_at_index CFArrayInsertValueAtIndex
#define cf_array_remove_value_at_index CFArrayRemoveValueAtIndex

#pragma mark CFDictionary
#define cf_dictionary_create CFDictionaryCreate
#define cf_dictionary_create_mutable_copy CFDictionaryCreateMutableCopy
#define cf_dictionary_get_value CFDictionaryGetValue
#define cf_dictionary_set_value CFDictionarySetValue

#pragma mark constants
#define lCFTypeArrayCallBacks kCFTypeArrayCallBacks
#define lCFTypeDictionaryKeyCallBacks kCFTypeDictionaryKeyCallBacks
#define lCFTypeDictionaryValueCallBacks kCFTypeDictionaryValueCallBacks

#endif
