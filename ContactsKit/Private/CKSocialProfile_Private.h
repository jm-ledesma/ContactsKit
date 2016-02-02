//
//  CKSocialProfile_Private.h
//  ContactsKit
//
//  Created by Sergey Popov on 1/18/16.
//  Copyright (c) 2016 ttitt. All rights reserved.
//

#import "CKSocialProfile.h"
#import <AddressBook/AddressBook.h>

@interface CKSocialProfile ()

- (instancetype)initWithSocialDictionary:(NSDictionary *)dictionary;
- (BOOL)addPropertiesToMultiValue:(ABMutableMultiValueRef)mutableMultiValueRef;

@end

@interface CKMutableSocialProfile ()

@end
