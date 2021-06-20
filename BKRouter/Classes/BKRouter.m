//
//  BKRouter.m
//  BKRouter_Example
//
//  Created by i2p on 2021/6/20.
//  Copyright © 2021 xwzx100200@163.com. All rights reserved.
//

#import "BKRouter.h"
#import <pthread/pthread.h>

#define InitLock(lock) pthread_mutex_init(&lock, NULL)
#define TryLock(lock) pthread_mutex_trylock(&lock)
#define Lock(lock) pthread_mutex_lock(&lock)
#define Unlock(lock) pthread_mutex_unlock(&lock)

NSString *const kBKRouterWildcardCharater = @"~";
NSString *const kBKRouterParameterURL = @"kBKRouterParameterURL";
NSString *const kBKRouterParameterUserInfo = @"kBKRouterParameterUserInfo";


typedef NS_ENUM(NSUInteger, BKRouterCodeType) {
    BKRouterCodeDefault = 0,
    
    BKRouterCodeScheme = 10,
    BKRouterCodeSchemeNothing,
    BKRouterCodeSchemeIllegality,
    
    BKRouterCodeModule = 20,
    BKRouterCodeModuleNothing,
    
    BKRouterCodeMethod = 30,
    BKRouterCodeMethodNothing,
    
    BKRouterCodeParam = 40,
    BKRouterCodeParamIllegality,
    
    BKRouterCodeInvocation = 50
};

@interface BKRouter () {
    NSMutableDictionary *_muRouter; //由路由信息组成的树结构
    pthread_mutex_t _lock;  //线程锁
}

@property (nonatomic, strong) NSMutableSet *schemes; // 支持的协议

@property (nonatomic, strong) NSMutableDictionary *customSchemesHandlers; // 支持的协议&实现

@property (nonatomic, strong) NSMutableArray *aURLProtocols;

@end


@implementation BKRouter

/**
 路由调用统一方法
 
 @param url BKRouter://模块名/方法名？参数1=xxx&参数2=xxx
 @param param 扩展参数，注意⚠️如果param中的key与rul重复，以param为准。
 @param resolve 成功回调
 @param reject 失败回调
 */
+ (void)openURL:(nonnull NSString*)url
          param:(nullable NSDictionary*)param
        resolve:(nullable BKRouterResolveBlock)resolve
         reject:(nullable BKRouterRejectBlock)reject {
    [[BKRouter sharedInstance] openURL:url param:param resolve:resolve reject:reject];
}

/// 路由订阅方法
/// @param url BKRouter://模块名/方法名
/// @param scheduler 调度处理回调
+ (void)subscribeURL:(nonnull NSString *)url
         onScheduler:(nonnull BKRouterHandlerBlock)scheduler {
    [[BKRouter sharedInstance] subscribeURL:url onScheduler:scheduler];
}


/// 路由调度方法
/// @param url BKRouter://模块名/方法名
/// @param message 调度通知数据
+ (void)dispatchURL:(nonnull NSString *)url
        withMessage:(nullable NSDictionary *)message {
    [[BKRouter sharedInstance] dispatchURL:url withMessage:message];
}

+ (void)addSupportScheme:(nonnull NSString*)scheme {
    if (scheme) {
        [[BKRouter sharedInstance] addSupportAppSchemes:@[scheme]];
    }
}

+ (void)addSupportSchemes:(nonnull NSArray*)schemes {
    if (schemes) {
        [[BKRouter sharedInstance] addSupportAppSchemes:schemes];
    }
}

+ (BOOL)registerClass:(Class)protocolClass {
    if (![protocolClass conformsToProtocol:@protocol(BKRouterURLProtocol)]){
         return NO;
    }
    if (![BKRouter sharedInstance].aURLProtocols) {
        [BKRouter sharedInstance].aURLProtocols = [[NSMutableArray alloc] initWithCapacity:5];
    }
    if (![[BKRouter sharedInstance].aURLProtocols containsObject:NSStringFromClass([protocolClass class])]) {
        [[BKRouter sharedInstance].aURLProtocols addObject:NSStringFromClass([protocolClass class])];
    }
    return YES;
}

+ (void)unregisterClass:(Class)protocolClass {
    [[BKRouter sharedInstance].aURLProtocols removeObject:NSStringFromClass([protocolClass class])];
}


+ (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    static BKRouter *instance = nil;
    dispatch_once(&onceToken,^{
        instance = [[super allocWithZone:NULL] init];
    });
    return instance;
}

+ (id)allocWithZone:(struct _NSZone *)zone {
    return [self sharedInstance];
}

- (instancetype)init {
    if (self = [super init]) {
        _muRouter = [NSMutableDictionary dictionary];
        
        InitLock(_lock);
    }
    return self;
}

#pragma mark - Private
- (void)openURL:(NSString*)url
          param:(NSDictionary*)param
        resolve:(BKRouterResolveBlock)resolve
         reject:(BKRouterRejectBlock)reject {
    BKRouterCodeType code = BKRouterCodeDefault;
    do {
        NSURL *schemeURL = [NSURL URLWithString:url];
        
        NSString *scheme = schemeURL.scheme;
        code = [self checkScheme:scheme];
        if (BKRouterCodeDefault != code) {
            break;
        }
        
        NSString *module = [self fetchRouterImpClass:schemeURL];
        code = [self checkModule:&module host:schemeURL.host];
        if (BKRouterCodeDefault != code) {
            break;
        }
        
        NSString *method = schemeURL.path;
        code = [self checkMethod:&method];
        if (BKRouterCodeDefault != code) {
            break;
        }
        
        NSString *paramter = schemeURL.query;
        NSMutableDictionary *mParam = [NSMutableDictionary dictionaryWithCapacity:1];
        code = [self handleParam:paramter dictParam:param toParamDict:mParam];
        if (BKRouterCodeDefault != code) {
            break;
        }
        
        NSString *methodHandle = [NSString stringWithFormat:@"routerHandle_%@_%@:resolve:reject:", module, method];
        SEL selector = NSSelectorFromString(methodHandle);
        
        Class cls = NSClassFromString(module);
        if ([cls respondsToSelector:selector]) {
            NSMethodSignature *singnature = [cls methodSignatureForSelector:selector];
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:singnature];
            invocation.target = cls;
            invocation.selector = selector;
            [invocation setArgument:&mParam atIndex:2];
            [invocation setArgument:&resolve atIndex:3];
            [invocation setArgument:&reject atIndex:4];
            [invocation retainArguments];
            [invocation invoke];
        } else {
            if (reject) {
                NSError *error = [self getErrorByCode:BKRouterCodeInvocation];
                reject(error);
            }
        }
        
    } while (false);
    
    if (BKRouterCodeDefault != code) {
        if (reject) {
            NSError *error = [self getErrorByCode:code];
            reject(error);
            //NSAssert(NO, @"BKRouter open eror.");
            return;
        }
    }
}

// 路由订阅
- (void)subscribeURL:(NSString *)url onScheduler:(BKRouterHandlerBlock)scheduler {
    Lock(_lock);
    NSMutableDictionary *subRouters = [self addURLPattern:url];
    if (scheduler && subRouters) {
        //将回调保存到字典树的末尾节点上
        subRouters[@"_"] = [scheduler copy];
    }
    Unlock(_lock);
}

// 路由调度
- (void)dispatchURL:(NSString *)url withMessage:(NSDictionary *)message {
    url = [url stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSMutableDictionary *parameters = [self extractParametersWithURL:url];
    [parameters enumerateKeysAndObjectsUsingBlock:^(id key, NSString *obj, BOOL *stop) {
        if ([obj isKindOfClass:[NSString class]]) {
            parameters[key] = [obj stringByRemovingPercentEncoding];
        }
    }];
    if (parameters) {
        BKRouterHandlerBlock handler;
        if (parameters[@"block_"]) {
            handler = parameters[@"block_"];
        }
        
        //如果为空，说明没有注册协议
        if (!handler) {
            parameters = nil;
            return;
        }
        
        if (message) {
            parameters[kBKRouterParameterUserInfo] = message;
        }
        if (handler) {
            //去掉参数中的block对象
            if (parameters[@"block_"]) {
                [parameters removeObjectForKey:@"block_"];
            }
            handler(parameters);
        }
        parameters = nil;
    }
}

/**
 检查路由协议的合法性

 @param scheme 路由协议名
 @return 错误码
 */
- (BKRouterCodeType)checkScheme:(NSString*)scheme {
    if (!scheme) {
        return BKRouterCodeSchemeNothing;
    }
    NSSet *schemeList = [[BKRouter sharedInstance] supportSchemeList];
    if (schemeList && ![schemeList containsObject:scheme]) {
        return BKRouterCodeSchemeIllegality;
    }
    return BKRouterCodeDefault;
}


/**
 检查模块的合法性

 @param module 模块名称
 @return 错误码
 */
- (BKRouterCodeType)checkModule:(NSString **)module host:(NSString *)host {
    //优先注册 、 其次使用host、再次使用默认 BKRouterHandler  (如此改造 不会变化原有逻辑)
    NSString *mod = *module;
    if (![NSClassFromString(mod) class]) {
        if ([NSClassFromString(host) class]) {
            *module = host;
        }else{
            *module = @"BKRouterHandler";
        }
    }
    return BKRouterCodeDefault;
}


/**
 检查方法合法性

 @param method 方法名
 @return 错误码
 */
- (BKRouterCodeType)checkMethod:(NSString **)method {
    NSString *m = *method;
    if (!m || m.length == 0) {
        return BKRouterCodeMethodNothing;
    }
    if ([m hasPrefix:@"/"]) {
        NSString *temp = [m substringFromIndex:1];
        *method = [temp stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    }else{
        *method = [m stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    }
    return BKRouterCodeDefault;
}


/**
 参数处理

 @param param 参数
 @return 错误码
 */
- (BKRouterCodeType)handleParam:(NSString*)sParam
                       dictParam:(NSDictionary*)param
                     toParamDict:(NSMutableDictionary*)mParam {
    if (sParam) {
        NSDictionary *dic = [self dictionaryFromQuery:sParam];
        if (!dic) {
            return BKRouterCodeParamIllegality;
        }
        [mParam addEntriesFromDictionary:dic];
    }
    
    if (param) {
        [mParam addEntriesFromDictionary:param];
    }
    
    return BKRouterCodeDefault;
}


- (NSMutableDictionary*)dictionaryFromQuery:(NSString*)query {
    NSCharacterSet* delimiterSet = [NSCharacterSet characterSetWithCharactersInString:@"&;"];
    NSMutableDictionary* pairs = [NSMutableDictionary dictionary];
    NSScanner* scanner = [NSScanner scannerWithString:query];
    
    while (![scanner isAtEnd]) {
        NSString* pairString = nil;
        [scanner scanUpToCharactersFromSet:delimiterSet intoString:&pairString];
        [scanner scanCharactersFromSet:delimiterSet intoString:NULL];
        NSArray* kvPair = [self getKeyValueArrFirstEqual:pairString];
        if (kvPair.count == 2) {
            NSString* key = [[kvPair objectAtIndex:0] stringByRemovingPercentEncoding];
            NSString* value = [[kvPair objectAtIndex:1] stringByRemovingPercentEncoding];
            if (key && value) {
                [pairs setObject:value forKey:key];
            }
        }
    }
    return pairs;
}

- (NSArray*)getKeyValueArrFirstEqual:(NSString*)string {
    if (!string) {
        return nil;
    }
    NSRange rang = [string rangeOfString:@"="];
    if (rang.location == NSNotFound) {
        return nil;
    }
    NSString * key = [string substringWithRange:NSMakeRange(0, rang.location)];
    if (string.length-rang.location-rang.length<=0) {
        return nil;
    }
    NSString * value = [string substringWithRange:NSMakeRange(rang.location+rang.length, string.length-rang.location-rang.length)];
    if (!key || !value) {
        return nil;
    }
    return @[key,value];
}


// 根据路由创建对应字典
- (NSMutableDictionary *)addURLPattern:(NSString *)URLPattern {
    //拆分路由信息
    NSArray *pathComponents = [self pathComponnentsWithURL:URLPattern];
    NSMutableDictionary *subRouters = _muRouter;
    
    //构造一个字典树结构
    for (NSString *pathComponent in pathComponents) {
        if (![subRouters objectForKey:pathComponent]) {
            subRouters[pathComponent] = [[NSMutableDictionary alloc] init];
        }
        subRouters = subRouters[pathComponent];
    }
    return subRouters;
}

// 拆分路由信息
- (NSArray *)pathComponnentsWithURL:(NSString *)URL {
    NSMutableArray *pathComponents = [NSMutableArray array];
    
    //先分析协议名称
    if ([URL rangeOfString:@"://"].location != NSNotFound) {
        NSArray *pathSegments = [URL componentsSeparatedByString:@"://"];
        
        NSString *protocol = pathSegments[0];
        //如果协议为空，用一个通配符占位
        if (protocol.length == 0) {
            [pathComponents addObject:kBKRouterWildcardCharater];
        } else {
            [pathComponents addObject:pathSegments[0]];
        }
        
        URL = pathSegments.lastObject;
        //如果只使用了协议，用一个通配符占位
        if (!URL.length) {
            [pathComponents addObject:kBKRouterWildcardCharater];
        }
    }
    
    //再分解路由
    NSArray *components = [[NSURL URLWithString:URL] pathComponents]; //不使用[URL pathComponents]
    for (NSString *component in components) {
        
        //过滤掉使用'//'开头的路由
        if ([component isEqualToString:@"/"]) {
            continue;
        }
        [pathComponents addObject:component];
    }
    
    //最后返回分级后的数组对象
    return [pathComponents copy];
}

// 提取参数
- (NSMutableDictionary *)extractParametersWithURL:(NSString *)URL {
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    NSMutableArray* pathComponents = [NSMutableArray arrayWithArray:[self pathComponnentsWithURL:URL]];
    NSMutableDictionary *router = _muRouter;
    
    //转换成路径格式
    NSString *components = [pathComponents componentsJoinedByString:@"."];
    
    //根据KVC找到保存回调的节点字典
    NSMutableDictionary *subRoute = [router valueForKeyPath:components];
    if (subRoute[@"_"]) {
        parameters[@"block_"] = [subRoute[@"_"] copy];
    } else {
        NSLog(@"未找到协议");
    }
    parameters[kBKRouterParameterURL] = URL;
    return parameters;
}

/**
 组装NSError
 
 @param code 错误吗
 @return 返回实例
 */
- (NSError *)getErrorByCode:(NSInteger)code {
    NSString *messge = nil;
    switch (code) {
        case BKRouterCodeDefault:
            messge = @"success.";
            break;
            
        case BKRouterCodeSchemeNothing:
            messge = @"scheme can't be nil.";
            break;
            
        case BKRouterCodeSchemeIllegality:
            messge = @"scheme isn't In White List.";
            break;
            
        case BKRouterCodeModuleNothing:
            messge = @"module can't be nil.";
            break;
            
        case BKRouterCodeMethodNothing:
            messge = @"method can't be nil.";
            break;
            
        case BKRouterCodeParamIllegality:
            messge = @"param is illegality.";
            break;
            
        case BKRouterCodeInvocation:
            messge = @"invocation error.";
            break;
            
        default:
            messge = @"unknow error.";
            break;
    }
    return [NSError errorWithDomain:NSURLErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey:messge}];
}

/// 获取支持的协议列表
- (NSSet *)supportSchemeList {
    
    if (self.schemes && self.schemes.count > 0) {
        return [self.schemes copy];
    }else{
        return nil;
    }
}

/// 添加支持的协议
/// @param schemes 协议列表
- (void)addSupportAppSchemes:(NSArray*)schemes {
    [self.schemes addObjectsFromArray:schemes];
}

/// 获取自定义路由实现类名
- (NSString *)fetchRouterImpClass:(NSURL *)url {
    NSString *classname = nil;
    if ([BKRouter sharedInstance].aURLProtocols.count>0) {
        for (NSString  *claStr in [BKRouter sharedInstance].aURLProtocols) {
            Class cla = NSClassFromString(claStr);
            if ([cla respondsToSelector:@selector(changeRouterImpClass:)]) {
                NSString *new_class_name = [cla performSelector:@selector(changeRouterImpClass:) withObject:url];
                if (new_class_name && new_class_name.length>0) {
                    classname = new_class_name;
                }
            }
        }
#if DEBUG
        if (classname) {
             NSLog(@"自定义规则URL：%@ Class：%@",url,classname);
        }
#endif
    }
    return classname;
}

@end



@implementation BKRouterHandler

@end

