//
//  CKAddressBook.m
//  ContactsKit
//
//  Created by Sergey Popov on 1/18/16.
//  Copyright (c) 2016 ttitt. All rights reserved.
//

#import "CKAddressBook.h"
#import "CKContact_Private.h"
#import <AddressBook/AddressBook.h>

NSString *const CKAddressBookErrorDomain = @"CKAddressBookErrorDomain";
NSString *const CKAddressBookDidChangeNotification = @"CKAddressBookDidChangeNotification";

@implementation CKAddressBook {
@private
#if TARGET_OS_IOS
    ABAddressBookRef _addressBookRef;
#elif TARGET_OS_MAC
    BOOL _accessIsNotRequested;
    ABAddressBook *_addressBook;
#endif
    dispatch_queue_t _addressBookQueue;
}

#pragma mark - Properties

- (CKAddressBookAccess)access
{
#if TARGET_OS_IOS
    ABAuthorizationStatus status = ABAddressBookGetAuthorizationStatus();
    switch (status)
    {
        case kABAuthorizationStatusDenied:
        case kABAuthorizationStatusRestricted:
            return CKAddressBookAccessDenied;
            
        case kABAuthorizationStatusAuthorized:
            return CKAddressBookAccessGranted;
            
        default:
            return CKAddressBookAccessUnknown;
    }
#elif TARGET_OS_MAC
    if (_accessIsNotRequested)
    {
        return CKAddressBookAccessUnknown;
    }
    else if (_addressBook)
    {
        return CKAddressBookAccessGranted;
    }
    else
    {
        return CKAddressBookAccessDenied;
    }
#endif
}

#pragma mark - Lifecycle

- (instancetype)init
{
    self = [super init];
    if (self)
    {
#if TARGET_OS_IOS
        _addressBookRef = ABAddressBookCreate();
#elif TARGET_OS_MAC
        _accessIsNotRequested = YES;
#endif
        // Set addressbook queue
        NSString *queueName = [NSString stringWithFormat:@"com.ttitt.contactskit.queue.%d", arc4random()];
        _addressBookQueue = dispatch_queue_create(queueName.UTF8String, DISPATCH_QUEUE_SERIAL);
        
        // Set default field masks
        _fieldsMask = CKContactFieldDefault;
    }
    return self;
}

- (void)dealloc
{
    [self stopObserveChanges];
    
#if TARGET_OS_IOS
    if (_addressBookRef)
    {
        CFRelease(_addressBookRef);
    }
#endif
    
#if !OS_OBJECT_USE_OBJC
    dispatch_release(_addressBookQueue);
#endif
}

#pragma mark - Public

- (void)requestAccessWithCompletion:(void (^)(NSError *error))callback
{
    NSParameterAssert(callback);

    [self willChangeValueForKey:NSStringFromSelector(@selector(access))];

#if TARGET_OS_IOS
    ABAddressBookRequestAccessWithCompletion(_addressBookRef, ^(bool granted, CFErrorRef errorRef) {
        
        NSError *error = nil;
        if (! granted || errorRef)
        {
            NSDictionary *userInfo = @{ NSLocalizedDescriptionKey : NSLocalizedString(@"Access denied", nil) };
            error = [NSError errorWithDomain:CKAddressBookErrorDomain code:1 userInfo:userInfo];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self didChangeValueForKey:NSStringFromSelector(@selector(access))];
            callback(error);
        });
    });
#elif TARGET_OS_MAC
    dispatch_async(_addressBookQueue, ^{
        
        _accessIsNotRequested = NO;
        
        if (! _addressBook)
        {
            _addressBook = [ABAddressBook addressBook];
        }
        
        NSError *error = nil;
        if (! _addressBook)
        {
            NSDictionary *userInfo = @{ NSLocalizedDescriptionKey : NSLocalizedString(@"Access denied", nil) };
            error = [NSError errorWithDomain:CKAddressBookErrorDomain code:1 userInfo:userInfo];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self didChangeValueForKey:NSStringFromSelector(@selector(access))];
            callback(error);
        });
    });
#endif
}

- (void)loadContacts
{
    CKContactField fieldMask = self.fieldsMask;
    CKContactField mergeMask = self.unifyLinkedContacts ? fieldMask : 0;
    NSArray *descriptors = [self.sortDescriptors copy];
    
    dispatch_async(_addressBookQueue, ^{
        
        id filter = nil;
        if ([self.delegate respondsToSelector:@selector(addressBook:shouldLoadContact:)])
        {
            filter = ^BOOL(CKContact *contact) {
                return [self.delegate addressBook:self shouldLoadContact:contact];
            };
        }
        
        NSError *error = nil;
        NSArray *contacts = [self ck_contactsWithFields:fieldMask merge:mergeMask sortDescriptors:descriptors filter:filter error:&error];
        
        if (! error)
        {
            if ([self.delegate respondsToSelector:@selector(addressBook:didLoadContacts:)])
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.delegate addressBook:self didLoadContacts:contacts];
                });
            }
        }
        else
        {
            if ([self.delegate respondsToSelector:@selector(addressBook:didFailLoad:)])
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.delegate addressBook:self didFailLoad:error];
                });
            }
        }
    });
}

- (void)contactsWithMask:(CKContactField)mask uinify:(BOOL)unify sortDescriptors:(NSArray *)descriptors
                  filter:(BOOL (^) (CKContact *contact))filter completion:(void (^) (NSArray *contacts, NSError *error))callback
{
    NSParameterAssert(callback);
    
    dispatch_async(_addressBookQueue, ^{
       
        CKContactField mergeMask = unify ? mask : 0;
        NSError *error = nil;
        NSArray *contacts = [self ck_contactsWithFields:mask merge:mergeMask sortDescriptors:descriptors filter:filter error:&error];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            callback(contacts, error);
        });
    });
}

- (void)contactWithIdentifier:(NSString *)identifier
{
    CKContactField fieldMask = self.fieldsMask;
    CKContactField mergeMask = self.unifyLinkedContacts ? fieldMask : 0;
    
    dispatch_async(_addressBookQueue, ^{
        
        NSError *error = nil;
        CKContact *contact = [self ck_contactWithIdentifier:identifier fields:fieldMask merge:mergeMask error:&error];
        
        if (! error)
        {
            if ([self.delegate respondsToSelector:@selector(addressBook:didLoadContact:)])
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.delegate addressBook:self didLoadContact:contact];
                });
            }
        }
        else
        {
            if ([self.delegate respondsToSelector:@selector(addressBook:didFailLoad:)])
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.delegate addressBook:self didFailLoad:error];
                });
            }
        }
    });
}

- (void)contactWithIdentifier:(NSString *)identifier mask:(CKContactField)mask uinify:(BOOL)unify completion:(void (^) (CKContact *contact, NSError *error))callback
{
    NSParameterAssert(identifier);
    NSParameterAssert(callback);

    dispatch_async(_addressBookQueue, ^{
        
        CKContactField mergeMask = unify ? mask : 0;
        
        NSError *error = nil;
        CKContact *contact = [self ck_contactWithIdentifier:identifier fields:mask merge:mergeMask error:&error];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            callback(contact, error);
        });
    });
}

- (void)addContact:(CKMutableContact *)contact completion:(void (^)(NSError *error))callback
{
    NSParameterAssert(callback);
    dispatch_async(_addressBookQueue, ^{
        NSError *error = nil;
        [self ck_addContact:contact error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            callback(error);
        });
    });
}

- (void)updateContact:(CKMutableContact *)contact completion:(void (^)(NSError *))callback
{
    NSParameterAssert(callback);
#warning Update
}

- (void)deleteContact:(CKMutableContact *)contact completion:(void (^)(NSError *error))callback
{
    NSParameterAssert(callback);
    dispatch_async(_addressBookQueue, ^{
        NSError *error = nil;
        [self ck_deleteContact:contact error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            callback(error);
        });
    });
}

- (void)startObserveChanges
{
    [self stopObserveChanges];
    
#if TARGET_OS_IOS
    ABAddressBookRegisterExternalChangeCallback(_addressBookRef, CKAddressBookExternalChangeCallback, (__bridge void *)(self));
#elif TARGET_OS_MAC
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(notificaitonDataBaseChanged:) name:kABDatabaseChangedNotification object:_addressBook];
    [nc addObserver:self selector:@selector(notificaitonDatabaseChangedExternally:) name:kABDatabaseChangedExternallyNotification object:_addressBook];
#endif
}

- (void)stopObserveChanges
{
#if TARGET_OS_IOS
    ABAddressBookUnregisterExternalChangeCallback(_addressBookRef, CKAddressBookExternalChangeCallback, (__bridge void *)(self));
#elif TARGET_OS_MAC
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc removeObserver:self name:kABDatabaseChangedNotification object:_addressBook];
    [nc removeObserver:self name:kABDatabaseChangedExternallyNotification object:_addressBook];
#endif
}

#pragma mark - Private

- (NSArray *)ck_contactsWithFields:(CKContactField)fields merge:(CKContactField)merge sortDescriptors:(NSArray *)descriptors
                            filter:(BOOL (^) (CKContact *contact))filter error:(NSError **)error
{
    // Gettings the array of people
#if TARGET_OS_IOS
    if (! _addressBookRef)
    {
        if (error)
        {
            NSDictionary *userInfo = @{ NSLocalizedDescriptionKey : NSLocalizedString(@"Access denied", nil) };
            *error = [NSError errorWithDomain:CKAddressBookErrorDomain code:1 userInfo:userInfo];
        }
        return nil;
    }
    
    CFArrayRef peopleArrayRef = ABAddressBookCopyArrayOfAllPeople(_addressBookRef);
    CFIndex contactCount = CFArrayGetCount(peopleArrayRef);
    NSMutableArray *contacts = [[NSMutableArray alloc] initWithCapacity:(NSUInteger)contactCount];
    NSMutableSet *linkedContactsIDs = [NSMutableSet set];

    for (CFIndex i = 0; i < contactCount; i++)
    {
        ABRecordRef recordRef = (ABRecordRef)CFArrayGetValueAtIndex(peopleArrayRef, i);
        
        // Checking already added contacts
        if ([linkedContactsIDs containsObject:@(ABRecordGetRecordID(recordRef))])
        {
            continue;
        }
        
        // Create the contact
        CKContact *contact = [[CKContact alloc] initWithRecordRef:recordRef fieldMask:fields];
        
        // Filter the contact if needed
        if (! filter || filter(contact))
        {
            [contacts addObject:contact];
        }

        CFArrayRef linkedPeopleArrayRef = ABPersonCopyArrayOfAllLinkedPeople(recordRef);
        CFIndex linkedCount = CFArrayGetCount(linkedPeopleArrayRef);
        // Merge linked contact info
        for (CFIndex j = 0; linkedCount > 1 && j < linkedCount; j++)
        {
            ABRecordRef linkedRecordRef = (ABRecordRef)CFArrayGetValueAtIndex(linkedPeopleArrayRef, j);
            // Don't merge the same contact
            if (linkedRecordRef == recordRef)
            {
                continue;
            }
            
            if (merge)
            {
                [contact mergeLinkedRecordRef:linkedRecordRef mergeMask:merge];
                [linkedContactsIDs addObject:@(ABRecordGetRecordID(recordRef))];
            }
        }
        CFRelease(linkedPeopleArrayRef);
    }
    CFRelease(peopleArrayRef);
#elif TARGET_OS_MAC
    
    if (! _addressBook)
    {
        if (error)
        {
            NSDictionary *userInfo = @{ NSLocalizedDescriptionKey : NSLocalizedString(@"Access denied", nil) };
            *error = [NSError errorWithDomain:CKAddressBookErrorDomain code:1 userInfo:userInfo];
        }
        return nil;
    }
    
    NSMutableArray *contacts = [[NSMutableArray alloc] init];
    NSMutableSet *linkedContactsIDs = [NSMutableSet set];
    for (ABPerson *record in [_addressBook people])
    {
        // Checking already added contacts
        if ([linkedContactsIDs containsObject:record.uniqueId])
        {
            continue;
        }
        
        ABRecordRef recordRef = (__bridge ABRecordRef)(record);
        CKContact *contact = [[CKContact alloc] initWithRecordRef:recordRef fieldMask:fields];
        
        // Filter the contact if needed
        if (! filter || filter(contact))
        {
            [contacts addObject:contact];
        }
        
        // Check the method by selector response, because it's only for OSX 10.8
        NSArray *linkedPeople;
        if ([record respondsToSelector:@selector(linkedPeople)])
        {
           linkedPeople = [record linkedPeople];
        }
        
        if (linkedPeople.count > 1)
        {
            for (ABPerson *linkedRecord in linkedPeople)
            {
                // Don't merge the same contact
                if ([linkedRecord isEqual:record])
                {
                    continue;
                }
                
                if (merge)
                {
                    ABRecordRef linkedRecordRef = (__bridge ABRecordRef)(linkedRecord);
                    [contact mergeLinkedRecordRef:linkedRecordRef mergeMask:merge];
                    [linkedContactsIDs addObject:linkedRecord.uniqueId];
                }
            }
        }
    }
#endif
    // Sort
    [contacts sortUsingDescriptors:descriptors];
    
    // Done
    return [[NSArray alloc] initWithArray:contacts];
}

- (CKContact *)ck_contactWithIdentifier:(NSString *)identifier fields:(CKContactField)fields merge:(CKContactField)merge error:(NSError **)error
{
    NSParameterAssert(identifier);
    
    CKContact *contact = nil;
    
#if TARGET_OS_IOS
    
    if (! _addressBookRef)
    {
        if (error)
        {
            NSDictionary *userInfo = @{ NSLocalizedDescriptionKey : NSLocalizedString(@"Access denied", nil) };
            *error = [NSError errorWithDomain:CKAddressBookErrorDomain code:1 userInfo:userInfo];
        }
        return nil;
    }
    
    ABRecordRef recordRef = ABAddressBookGetPersonWithRecordID(_addressBookRef, (int32_t)identifier.integerValue);
    if (recordRef != NULL)
    {
        contact = [[CKContact alloc] initWithRecordRef:recordRef fieldMask:fields];
        
        CFArrayRef linkedPeopleArrayRef = ABPersonCopyArrayOfAllLinkedPeople(recordRef);
        CFIndex linkedCount = CFArrayGetCount(linkedPeopleArrayRef);
        // Merge linked contact info
        for (CFIndex j = 0; linkedCount > 1 && j < linkedCount; j++)
        {
            ABRecordRef linkedRecordRef = (ABRecordRef)CFArrayGetValueAtIndex(linkedPeopleArrayRef, j);
            // Don't merge the same contact
            if (linkedRecordRef == recordRef)
            {
                continue;
            }
            
            if (merge)
            {
                [contact mergeLinkedRecordRef:linkedRecordRef mergeMask:merge];
            }
        }
        CFRelease(linkedPeopleArrayRef);
    }
#elif TARGET_OS_MAC
    
    if (! _addressBook)
    {
        if (error)
        {
            NSDictionary *userInfo = @{ NSLocalizedDescriptionKey : NSLocalizedString(@"Access denied", nil) };
            *error = [NSError errorWithDomain:CKAddressBookErrorDomain code:1 userInfo:userInfo];
        }
        return nil;
    }
    
    ABRecord *record = [_addressBook recordForUniqueId:identifier];
    if (record)
    {
        ABRecordRef recordRef = (__bridge ABRecordRef)(record);
        CKContact *contact = [[CKContact alloc] initWithRecordRef:recordRef fieldMask:fields];
        
        // Check the method by selector response, because it's only for OSX 10.8
        NSArray *linkedPeople;
        if ([record respondsToSelector:@selector(linkedPeople)])
        {
            linkedPeople = [(ABPerson *)record linkedPeople];
        }
        
        if (linkedPeople.count > 1)
        {
            for (ABPerson *linkedRecord in linkedPeople)
            {
                // Don't merge the same contact
                if ([linkedRecord isEqual:record])
                {
                    continue;
                }
                
                if (merge)
                {
                    ABRecordRef linkedRecordRef = (__bridge ABRecordRef)(linkedRecord);
                    [contact mergeLinkedRecordRef:linkedRecordRef mergeMask:merge];
                }
            }
        }
    }
#endif
    return contact;
}

- (BOOL)ck_addOrUpdateContact:(CKMutableContact *)contact error:(NSError **)error
{
    NSParameterAssert(contact);
    
    BOOL result = NO;
    ABRecordRef recordRef = NULL;
    
#if TARGET_OS_IOS
    if (! _addressBookRef)
    {
        if (error)
        {
            NSDictionary *userInfo = @{ NSLocalizedDescriptionKey : NSLocalizedString(@"Access denied", nil) };
            *error = [NSError errorWithDomain:CKAddressBookErrorDomain code:1 userInfo:userInfo];
        }
    }
    
#warning UPDATE
    if (/* DISABLES CODE */ (1))
    {
        recordRef = ABPersonCreate();
    }
    else
    {
        recordRef = ABAddressBookGetPersonWithRecordID(_addressBookRef, (int32_t)contact.identifier.integerValue);
        if (recordRef != NULL)
        {
            result = YES;
            CFRetain(recordRef);
        }
    }
    
    if (result)
    {
        result = [contact setRecordRef:recordRef error:error];
    }
    
#warning Skip adding contact
    if (result)
    {
        CFErrorRef errorRef = NULL;
        result = ABAddressBookAddRecord(_addressBookRef, recordRef, &errorRef);
        
        if (error && errorRef != NULL)
        {
            *error = (__bridge_transfer NSError *)(errorRef);
        }
        else if (errorRef != NULL)
        {
            CFRelease(errorRef);
        }
    }
    
    if (result)
    {
        CFErrorRef errorRef = NULL;
        result = ABAddressBookSave(_addressBookRef, &errorRef);
        
        if (error && errorRef != NULL)
        {
            *error = (__bridge_transfer NSError *)(errorRef);
        }
        else if (errorRef != NULL)
        {
            CFRelease(errorRef);
        }
    }
    
    if (result && recordRef)
    {
        contact.identifier = @(ABRecordGetRecordID(recordRef)).stringValue;
    }
    
    if (recordRef)
    {
        CFRelease(recordRef);
    }
#elif TARGET_OS_MAC
    if (! _addressBook)
    {
        if (error)
        {
            NSDictionary *userInfo = @{ NSLocalizedDescriptionKey : NSLocalizedString(@"Access denied", nil) };
            *error = [NSError errorWithDomain:CKAddressBookErrorDomain code:1 userInfo:userInfo];
        }
        return NO;
    }
    
    ABRecord *record = [[ABRecord alloc] initWithAddressBook:_addressBook];
    ABRecordRef recordRef = (__bridge ABRecordRef)(record);
    
    if (result)
    {
        result = [contact setRecordRef:recordRef error:error];
    }
    
    if (result)
    {
        result = [_addressBook hasUnsavedChanges];
        if (! result && error)
        {
            NSDictionary *userInfo = @{NSLocalizedDescriptionKey : NSLocalizedString(@"Address book hasn't changes", nil)};
            *error = [NSError errorWithDomain:CKAddressBookErrorDomain code:2 userInfo:userInfo];
        }
    }
    
    if (result)
    {
        result = [_addressBook saveAndReturnError:error];
    }
    
    if (result)
    {
        contact.identifier = record.uniqueId;
    }
#endif
    
    return result;
}

- (BOOL)ck_deleteContact:(CKMutableContact *)contact error:(NSError **)error
{
    NSParameterAssert(contact);
    
#warning Check existing ID for the contact
    
#if TARGET_OS_IOS
    
    if (! _addressBookRef)
    {
        if (error)
        {
            NSDictionary *userInfo = @{ NSLocalizedDescriptionKey : NSLocalizedString(@"Access denied", nil) };
            *error = [NSError errorWithDomain:CKAddressBookErrorDomain code:1 userInfo:userInfo];
        }
        return NO;
    }
    
    ABRecordRef recordRef = ABAddressBookGetPersonWithRecordID(_addressBookRef, (int32_t)contact.identifier.integerValue);
    
    BOOL result = NO;
    
    if (recordRef != NULL)
    {
        CFErrorRef errorRef = NULL;
        result = ABAddressBookRemoveRecord(_addressBookRef, recordRef, &errorRef);
        
        if (error && errorRef != NULL)
        {
            *error = (__bridge_transfer NSError *)(errorRef);
        }
        else if (errorRef != NULL)
        {
            CFRelease(errorRef);
        }
    }
    else
    {
        if (error)
        {
            NSDictionary *userInfo = @{ NSLocalizedDescriptionKey : NSLocalizedString(@"Contact not found", nil)};
            *error = [NSError errorWithDomain:CKAddressBookErrorDomain code:1 userInfo:userInfo];
        }
    }
    
    if (result)
    {
        CFErrorRef errorRef = NULL;
        result = ABAddressBookSave(_addressBookRef, &errorRef);
        
        if (error && errorRef != NULL)
        {
            *error = (__bridge_transfer NSError *)(errorRef);
        }
        else if (errorRef != NULL)
        {
            CFRelease(errorRef);
        }
    }
    
#elif TARGET_OS_MAC
    
    if (! _addressBook)
    {
        if (error)
        {
            NSDictionary *userInfo = @{ NSLocalizedDescriptionKey : NSLocalizedString(@"Access denied", nil) };
            *error = [NSError errorWithDomain:CKAddressBookErrorDomain code:1 userInfo:userInfo];
        }
        return NO;
    }
    
    BOOL result = NO;
    ABRecord *record = [_addressBook recordForUniqueId:contact.identifier];
    if (record)
    {
        result = [_addressBook removeRecord:record error:error];
        
        if (result)
        {
            result = [_addressBook hasUnsavedChanges];
            if (! result && error)
            {
                NSDictionary *userInfo = @{NSLocalizedDescriptionKey : NSLocalizedString(@"Address book hasn't changes", nil)};
                *error = [NSError errorWithDomain:CKAddressBookErrorDomain code:2 userInfo:userInfo];
            }
        }
        
        if (result)
        {
            result = [_addressBook saveAndReturnError:error];
        }
    }
    else
    {
        if (error)
        {
            NSDictionary *userInfo = @{ NSLocalizedDescriptionKey : NSLocalizedString(@"Contact not found", nil)};
            *error = [NSError errorWithDomain:CKAddressBookErrorDomain code:1 userInfo:userInfo];
        }
    }
    
#endif
    
    return result;
}

#if TARGET_OS_IOS

#pragma mark - Callbacks

static void CKAddressBookExternalChangeCallback(ABAddressBookRef addressBookRef, CFDictionaryRef __unused info, void *context)
{
    ABAddressBookRevert(addressBookRef);
    CKAddressBook *addressBook = (__bridge CKAddressBook *)(context);
    
    if ([addressBook.delegate respondsToSelector:@selector(addressBookDidChnage:)])
    {
        [addressBook.delegate addressBookDidChnage:addressBook];
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:CKAddressBookDidChangeNotification object:addressBook userInfo:nil];
}

#elif TARGET_OS_MAC

#pragma mark - Notifications

- (void)notificaitonDataBaseChanged:(NSNotification *)aNotification
{
//    Future using
//    NSArray *insertedRecords = [aNotification.userInfo objectForKey:kABInsertedRecords];
//    NSArray *deletedRecords = [aNotification.userInfo objectForKey:kABDeletedRecords];
//    NSArray *updatedRecords = [aNotification.userInfo objectForKey:kABUpdatedRecords];
}

- (void)notificaitonDatabaseChangedExternally:(NSNotification *)aNotification
{
//    Future using
//    NSArray *insertedRecords = [aNotification.userInfo objectForKey:kABInsertedRecords];
//    NSArray *deletedRecords = [aNotification.userInfo objectForKey:kABDeletedRecords];
//    NSArray *updatedRecords = [aNotification.userInfo objectForKey:kABUpdatedRecords];
    
    if ([self.delegate respondsToSelector:@selector(addressBookDidChnage:)])
    {
        [self.delegate addressBookDidChnage:self];
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:CKAddressBookDidChangeNotification object:self userInfo:nil];
}

#endif

@end
