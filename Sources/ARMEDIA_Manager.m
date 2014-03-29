/**
 * @file   ARMEDIA_Manager.m
 * @author malick.sylla.ext@parrot.fr
 * @brief
 *
 */

#import <UIKit/UIKit.h>
#import <libARMedia/ARMedia.h>
#import <libARMedia/ARMEDIA_Manager.h>
#import "ALAssetRepresentation+VideoAtoms.h"
#import "ARMEDIA_Description.h"

#define ARMEDIA_MANAGER_DATABASE_FILENAME                       @"ARMediaDB.ar"

// PVAT Keys
NSString *const kARMediaManagerPVATRunDateKey                   = @"runDate";
NSString *const kARMediaManagerPVATMediaDateKey                 = @"mediaDate";
NSString *const kARMediaManagerPVATDeviceKey                    = @"device";

// Archive keys
NSString *const kARMediaManagerArchiverKey                      = @"kARMediaManagerArchiverKey";
NSString *const kARMediaManagerKey                              = @"kARMediaManagerKey";

// Notification keys
NSString *const kARMediaManagerNotificationInitialized          = @"kARMediaManagerNotificationInitialized";
NSString *const kARMediaManagerNotificationUpdating             = @"kARMediaManagerNotificationUpdating";
NSString *const kARMediaManagerNotificationUpdated              = @"kARMediaManagerNotificationUpdated";
NSString *const kARMediaManagerNotificationMediaAdded           = @"kARMediaManagerNotificationMediaAdded";

// This block is always executed. If failure, an NSError is passed.
typedef void (^ARMediaManagerTranferingBlock)(NSString *assetURLString);

@interface ARMediaManager ()
@property (nonatomic, assign) BOOL cancelRefresh;
@property (nonatomic, assign) BOOL isUpdate;
@property (nonatomic, assign) BOOL isInit;
@property (nonatomic, assign) NSUInteger mediaAssetsCount;
@property (nonatomic, strong) NSMutableDictionary *privateProjectsDictionary;
@property (nonatomic, strong) NSMutableDictionary *groupMediaDictionary;
@property (nonatomic, strong) NSDictionary *projectsDictionary;

- (BOOL)saveMedia:(NSString *)mediaPath transferingBlock:(ARMediaManagerTranferingBlock)_transferingBlock;
- (void)addAssetToLibrary:(ALAsset *)asset albumName:(NSString *)albumName;
@end

@implementation ARMediaManager

/*************************************/
/*      ARMediaManager (public)     */
/*************************************/

+ (ARMediaManager *)sharedInstance
{
    static ARMediaManager *_sharedARMediaManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedARMediaManager = [[ARMediaManager alloc] init];
        
        /**
         *  custom init
         */
        _sharedARMediaManager.isInit = NO;
        _sharedARMediaManager.isUpdate = NO;
        _sharedARMediaManager.groupMediaDictionary = [NSMutableDictionary dictionary];

    });
    
    return _sharedARMediaManager;
}

- (eARMEDIA_MANAGER_ERROR)initWithProjectIDs:(NSArray *)projectIDs;
{
    NSUInteger returnVal = ARMEDIA_MANAGER_ALREADY_INITIALIZED;
    if(!_isInit)
    {
        // Get productlist from the saved file with NSCoding
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documentsDirectory = [paths objectAtIndex:0];
        NSString *path = [documentsDirectory stringByAppendingPathComponent:ARMEDIA_MANAGER_DATABASE_FILENAME];
        NSData *data = [[NSData alloc] initWithContentsOfFile:path];
        int valueKARMediaManagerKey = [[[NSUserDefaults standardUserDefaults] valueForKey:kARMediaManagerKey] intValue];
        
        if(valueKARMediaManagerKey > 0)
        {
            // If data is not empty, unarchiving
            if (data != nil)
            {
                NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
                _privateProjectsDictionary  = [unarchiver decodeObjectForKey:kARMediaManagerArchiverKey];
                [unarchiver finishDecoding];
            }
        }
        else
        {
            _privateProjectsDictionary = [NSMutableDictionary dictionary];
            [[NSUserDefaults standardUserDefaults] setValue:[NSString stringWithFormat:@"%d",0]  forKey:kARMediaManagerKey];
        }
        
        for (NSString *projectID in projectIDs)
        {
            if([_privateProjectsDictionary valueForKey:projectID] == nil)
            {
                [_privateProjectsDictionary setObject:[NSMutableDictionary dictionary] forKey:projectID];
            }
        }
        _isInit = YES;
        [[NSNotificationCenter defaultCenter] postNotificationName:kARMediaManagerNotificationInitialized object:nil];
        
        returnVal = ARMEDIA_MANAGER_OK;
    }
    return returnVal;
}

- (NSDictionary *)getProjectDictionary:(NSString *)project
{
    NSMutableDictionary *retDictionary = nil;
    if (project == nil)
    {
        NSMutableDictionary *mutableReturnedDictionary = [NSMutableDictionary dictionary];
        for (NSDictionary *dictionary in _projectsDictionary)
            [mutableReturnedDictionary setObject:[_projectsDictionary objectForKey:dictionary] forKey:dictionary];
        retDictionary = mutableReturnedDictionary;
    }
    else
    {
        retDictionary = [_projectsDictionary objectForKey:project];
    }
    
    return retDictionary;
}


- (eARMEDIA_MANAGER_ERROR)update
{
    if(!_isInit)
        return ARMEDIA_MANAGER_NOT_INITIALIZED;
    
    // Get All assets from camera roll
    NSLog(@"Get All assets from camera roll");
    void (^assetGroupEnumerator)(ALAssetsGroup *, BOOL *) =  ^(ALAssetsGroup *group, BOOL *stop)
    {
        if (group != nil)
        {
            [_groupMediaDictionary setValue:[group valueForProperty:ALAssetsGroupPropertyURL] forKey:[group valueForProperty:ALAssetsGroupPropertyName]];
            if([(NSNumber *)[group valueForProperty:ALAssetsGroupPropertyType] intValue] == ALAssetsGroupSavedPhotos)
            {
                // Get count of assets
                _mediaAssetsCount = [group numberOfAssets];
                
                NSLog(@"mediaAssetCount : %d",[group numberOfAssets]);
                if(_mediaAssetsCount > 0)
                {
                    [self retrieveAssetsWithGroup:group];
                }
                else
                {
                    _projectsDictionary = [_privateProjectsDictionary copy];
                    [[NSNotificationCenter defaultCenter] postNotificationName:kARMediaManagerNotificationUpdated object:nil];
                    
                    _isUpdate = YES;
                }
            }
        }
    };
    
    void (^failureBlock)(NSError *) = ^(NSError *error)
    {
        NSLog(@"Failure : %@", error);
        _projectsDictionary = [_privateProjectsDictionary copy];
        [[NSNotificationCenter defaultCenter] postNotificationName:kARMediaManagerNotificationUpdated object:nil];
        
        _isUpdate = YES;
    };
    
    ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
    _isUpdate = NO;
    [library enumerateGroupsWithTypes:ALAssetsGroupAll
                           usingBlock:assetGroupEnumerator
                         failureBlock:failureBlock];
    
    return ARMEDIA_MANAGER_OK;
}

- (BOOL)addMedia:(NSString *)mediaPath
{
    BOOL returnVal = NO;
    if (mediaPath == nil || !_isUpdate)
        return returnVal;
    
    void (^transferingBlock)(NSString *) = ^(NSString *assetURLString)
    {
        if(assetURLString != nil)
        {
            [self saveMediaOnArchive];
            _projectsDictionary = [_privateProjectsDictionary copy];
            [[NSNotificationCenter defaultCenter] postNotificationName:kARMediaManagerNotificationMediaAdded object:assetURLString];
            
        }
        _isUpdate = YES;
    };
    
    if (_isUpdate)
    {
        _isUpdate = NO;
        returnVal = [self saveMedia:mediaPath transferingBlock:transferingBlock];
    }
    return returnVal;
}

- (BOOL)isUpdated
{
    return _isUpdate;
}
/*************************************/
/*      ARMediaManager (private)    */
/*************************************/

-(void)saveMediaOnArchive
{
    // Save on file with NSCoding
    NSString *documentsDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString *archivePath = [documentsDirectory stringByAppendingPathComponent:ARMEDIA_MANAGER_DATABASE_FILENAME];
    NSMutableData *data = [NSMutableData data];
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
    [archiver encodeObject:_privateProjectsDictionary forKey:kARMediaManagerArchiverKey];
    [archiver finishEncoding];
    [data writeToFile:archivePath atomically:YES];
}

- (void)addAssetToLibrary:(ALAsset *)asset albumName:(NSString *)albumName
{
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
    if([_groupMediaDictionary valueForKey:albumName] == nil)
    {
        [library addAssetsGroupAlbumWithName:albumName resultBlock:^(ALAssetsGroup *group)
         {
             [_groupMediaDictionary setValue:[group valueForProperty:ALAssetsGroupPropertyURL] forKey:albumName];
             [group addAsset:asset];
             dispatch_semaphore_signal(sema);
             
         }
                                failureBlock:^(NSError *error)
         {
             NSLog(@"Failure : %@", error);
             dispatch_semaphore_signal(sema);
         }];
    }
    else
    {
        [library groupForURL:[_groupMediaDictionary valueForKey:albumName] resultBlock:^(ALAssetsGroup *group)
         {
             if(group != nil)
             {
                 [group addAsset:asset];
             }
             dispatch_semaphore_signal(sema);
         }
                failureBlock:^(NSError *error)
         {
             NSLog(@"Failure : %@", error);
             dispatch_semaphore_signal(sema);
         }];
    }
    
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
}

- (void)retrieveAssetsWithGroup:(ALAssetsGroup *)group
{
    // RETRIEVING ALL ASSETS IN CAMERA ROLL
    ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
    __block NSMutableDictionary *tempProjectDictionaries = [NSMutableDictionary dictionary];
    
    for(NSMutableDictionary *tmpProject in _privateProjectsDictionary)
    {
        [tempProjectDictionaries setObject:[NSMutableDictionary dictionary] forKey:tmpProject];
    }
    
    void (^assetEnumerator)(ALAsset *, NSUInteger, BOOL *) = ^(ALAsset *asset, NSUInteger index, BOOL *stop)
    {
        if(asset != nil)
        {
            NSString *stringAsset = nil;
            ALAssetRepresentation *representation = [asset defaultRepresentation];
            ARMediaDescription *object = [[ARMediaDescription alloc] init];
            
            if ([[[NSUserDefaults standardUserDefaults] valueForKey:kARMediaManagerKey] intValue] > index)
            {
                stringAsset = [[representation url] absoluteString];
                for (NSString *projectID in _privateProjectsDictionary)
                {
                    NSMutableDictionary *projectDictionary = [_privateProjectsDictionary valueForKey:projectID];
                    ARMediaDescription *object = [projectDictionary objectForKey:stringAsset];
                    if (object != nil)
                    {
                        [[tempProjectDictionaries objectForKey:projectID] setValue:[projectDictionary objectForKey:stringAsset] forKey:stringAsset];
                        [self addAssetToLibrary:asset albumName:object.device];
                    }
                    // NO ELSE - We add only existing media from Camera roll
                }
            }
            else
            {
                if([asset valueForProperty:ALAssetPropertyType] == ALAssetTypeVideo)
                {
                    NSDictionary *atomValue = [representation atomExist:[NSString stringWithUTF8String:ARMEDIA_VIDEOATOMS_PVAT]];
                    if(atomValue != nil)
                    {
                        stringAsset = [[representation url] absoluteString];
                        object.runDate = [atomValue valueForKey:kARMediaManagerPVATRunDateKey];
                        object.mediaDate = [atomValue valueForKey:kARMediaManagerPVATMediaDateKey];
                        object.device = [atomValue valueForKey:kARMediaManagerPVATDeviceKey];
                        [[tempProjectDictionaries valueForKey:object.device] setValue:object forKey:stringAsset];
                        [self addAssetToLibrary:asset albumName:object.device];
                    }
                    // NO ELSE - Ignoring this video - ardt value format not recognized
                }
                else if([asset valueForProperty:ALAssetPropertyType] == ALAssetTypePhoto)
                {
                    NSDictionary *metadata = [representation metadata];
                    if(metadata != nil)
                    {
                        NSDictionary *tiffDictionary = [metadata valueForKey:(NSString *)kCGImagePropertyTIFFDictionary];
                        
                        if(tiffDictionary != nil)
                        {
                            NSString *tiffDescription = [tiffDictionary valueForKey:(NSString *)kCGImagePropertyTIFFImageDescription];
                            stringAsset = [[representation url] absoluteString];
                            NSError *jSONerror = nil;
                            
                            NSData * data = [tiffDescription dataUsingEncoding:NSASCIIStringEncoding];
                            if (data != nil)
                            {
                                NSDictionary *jSONDataDic =[NSJSONSerialization  JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&jSONerror];
                                if((jSONDataDic != nil) && [[_privateProjectsDictionary allKeys] containsObject:[jSONDataDic valueForKey:kARMediaManagerPVATDeviceKey]] && (jSONerror == nil))
                                {
                                    object.runDate = [jSONDataDic valueForKey:kARMediaManagerPVATRunDateKey];
                                    object.mediaDate = [jSONDataDic valueForKey:kARMediaManagerPVATMediaDateKey];
                                    object.device = [jSONDataDic valueForKey:kARMediaManagerPVATDeviceKey];
                                    [[tempProjectDictionaries valueForKey:object.device] setValue:object forKey:stringAsset];
                                    [self addAssetToLibrary:asset albumName:object.device];
                                }
                            }
                        }
                    }
                }
                // NO ELSE, ALAssetPropertyType == ALAssetTypeUnknown => We don't process this type
            }
            
            [[NSNotificationCenter defaultCenter] postNotificationName:kARMediaManagerNotificationUpdating object:[NSString stringWithFormat:@"%0.f",(((double)index+1)/(double)_mediaAssetsCount)*100]];
        }
        else
        {
            [[NSUserDefaults standardUserDefaults] setValue:[NSString stringWithFormat:@"%d",index]  forKey:kARMediaManagerKey];
            [_privateProjectsDictionary setDictionary:tempProjectDictionaries];
            [self saveMediaOnArchive];
            _projectsDictionary = [_privateProjectsDictionary copy];
            [[NSNotificationCenter defaultCenter] postNotificationName:kARMediaManagerNotificationUpdated object:nil];
            _isUpdate = YES;
        }
        *stop = _cancelRefresh;
    };
    [group enumerateAssetsUsingBlock:assetEnumerator];
}

- (BOOL)saveMedia:(NSString *)mediaPath transferingBlock:(ARMediaManagerTranferingBlock)_transferingBlock
{
    __block BOOL added = NO;
    __block  NSString *stringAsset = nil;
    __block ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    
    ARMediaDescription *object = [[ARMediaDescription alloc]init];
    if ([mediaPath.pathExtension isEqualToString:[NSString stringWithUTF8String:ARMEDIA_MP4_EXTENSION]])
    {
        [library writeVideoAtPathToSavedPhotosAlbum:[NSURL URLWithString:mediaPath]  completionBlock:^(NSURL *assetURL, NSError *error)
         {
             if(error != nil || assetURL == nil)
             {
                 NSLog(@"Failure : %@", error);
                 _transferingBlock(nil);
                 added = NO;
             }
             else
             {
                 [library assetForURL:assetURL
                          resultBlock:^(ALAsset *asset) {
                              
                              ALAssetRepresentation *representation = [asset defaultRepresentation];
                              
                              NSDictionary *atomValue = [representation atomExist:[NSString stringWithUTF8String:ARMEDIA_VIDEOATOMS_PVAT]];
                              
                              if(atomValue != nil)
                              {
                                  stringAsset = [[representation url] absoluteString];
                                  object.runDate = [atomValue valueForKey:kARMediaManagerPVATRunDateKey];
                                  object.mediaDate = [atomValue valueForKey:kARMediaManagerPVATMediaDateKey];
                                  object.device = [atomValue valueForKey:kARMediaManagerPVATDeviceKey];
                                  [[_privateProjectsDictionary valueForKey:object.device] setValue:object forKey:stringAsset];
                                  [self addAssetToLibrary:asset albumName:object.device];
                              }
                              // NO ELSE - Ignoring this video - ardt value format not recognized
                              dispatch_semaphore_signal(sema);
                          }
                  
                         failureBlock:^(NSError* error) {
                             NSLog(@"failed to retrieve image asset:\nError: %@ ", [error localizedDescription]);
                             dispatch_semaphore_signal(sema);
                         }];
                 
                 dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
                 _transferingBlock([assetURL absoluteString]);
                 added = YES;
             }
         }];
        
    }
    else if ([mediaPath.pathExtension isEqualToString:[NSString stringWithUTF8String:ARMEDIA_JPG_EXTENSION]])
    {
        NSArray *pathComponents = [mediaPath pathComponents];
        NSData *data = [NSData dataWithContentsOfFile:mediaPath];
        [library writeImageDataToSavedPhotosAlbum:data metadata:nil completionBlock:^(NSURL *assetURL, NSError *error)
         {
             if(error != nil || assetURL == nil)
             {
                 NSLog(@"Failure : %@", error);
                 _transferingBlock(nil);
                 added = NO;
             }
             else
             {
                 [library assetForURL:assetURL
                          resultBlock:^(ALAsset *asset) {
                              ALAssetRepresentation *representation = [asset defaultRepresentation];
                              
                              NSDictionary *metadata = [representation metadata];
                              if(metadata != nil)
                              {
                                  NSDictionary *tiffDictionary = [metadata valueForKey:(NSString *)kCGImagePropertyTIFFDictionary];
                                  if(tiffDictionary != nil)
                                  {
                                      NSString *tiffDescription = [tiffDictionary valueForKey:(NSString *)kCGImagePropertyTIFFImageDescription];
                                      stringAsset = [[representation url] absoluteString];
                                      
                                      NSError *jSONerror = nil;
                                      NSData *data = [tiffDescription dataUsingEncoding:NSASCIIStringEncoding];
                                      if (data != nil)
                                      {
                                          NSDictionary *jSONDataDic =[NSJSONSerialization  JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&jSONerror];
                                          
                                          if((jSONDataDic != nil) && [[_privateProjectsDictionary allKeys] containsObject:[jSONDataDic valueForKey:kARMediaManagerPVATDeviceKey]] && (jSONerror == nil))
                                          {
                                              object.runDate = [jSONDataDic valueForKey:kARMediaManagerPVATRunDateKey];
                                              object.mediaDate = [jSONDataDic valueForKey:kARMediaManagerPVATMediaDateKey];
                                              object.device = [jSONDataDic valueForKey:kARMediaManagerPVATDeviceKey];
                                              [[_privateProjectsDictionary valueForKey:object.device] setValue:object forKey:stringAsset];
                                              [self addAssetToLibrary:asset albumName:object.device];
                                          }
                                      }
                                  }
                              }
                              dispatch_semaphore_signal(sema);
                          }
                  
                         failureBlock:^(NSError* error) {
                             NSLog(@"failed to retrieve image asset:\nError: %@ ", [error localizedDescription]);
                             dispatch_semaphore_signal(sema);
                         }];
                 
                 dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
                 _transferingBlock([assetURL absoluteString]);
                 added = YES;
             }
         }];
    }
    return added;
}

@end