//
//  BKRouter.h
//  BKRouter_Example
//
//  Created by i2p on 2021/6/20.
//  Copyright © 2021 xwzx100200@163.com. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 成功回调

 @param result 回调结果
 */
typedef void (^BKRouterResolveBlock)(id result);

/**
 失败回调

 @param error 错误信息
 */
typedef void (^BKRouterRejectBlock)(NSError *error);

/**
 订阅回调

@param parameters 回调数据
*/
typedef void(^BKRouterHandlerBlock)(NSDictionary *parameters);


//订阅路由Key
extern NSString *const kBKRouterParameterURL;

//订阅回调数据Key
extern NSString *const kBKRouterParameterUserInfo;


// 自定义路由协议
@protocol BKRouterURLProtocol <NSObject>

+ (NSString *)changeRouterImpClass:(NSURL *)url;

@end


@interface BKRouter : NSObject

/// 路由调用统一方法
/// @param url WLRouter://模块名/方法名？参数1=xxx&参数2=xxx
/// @param param 扩展参数，注意⚠️如果param中的key与url重复，以param为准。
/// @param resolve 成功回调
/// @param reject 失败回调
+ (void)openURL:(nonnull NSString *)url
          param:(nullable NSDictionary* )param
        resolve:(nullable BKRouterResolveBlock)resolve
         reject:(nullable BKRouterRejectBlock)reject;


/// 路由订阅方法
/// @param url WLRouter://模块名/订阅名
/// @param scheduler 调度处理回调
+ (void)subscribeURL:(nonnull NSString *)url
         onScheduler:(nonnull BKRouterHandlerBlock)scheduler;


/// 路由调度方法
/// @param url WLRouter://模块名/订阅名
/// @param message 调度通知数据
+ (void)dispatchURL:(nonnull NSString *)url
        withMessage:(nullable NSDictionary *)message;


/// 添加支持的协议
/// @param scheme 协议名
+ (void)addSupportScheme:(nonnull NSString*)scheme;

/// 添加支持的协议
/// @param schemes 协议名
+ (void)addSupportSchemes:(nonnull NSArray*)schemes;


/// 注册
/// @param protocolClass  WLURLProtocol
+ (BOOL)registerClass:(Class)protocolClass;


/// 取消注册
/// @param protocolClass WLRouter 的子类
+ (void)unregisterClass:(Class)protocolClass;

@end


@interface BKRouterHandler : NSObject

@end


/// 组件对外公开接口, interface接口名, parm接收参数, resolve成功回调, reject失败回调
#define BKROUTER_EXTERN_METHOD_HANDLER(interface,param,resolve,reject) BKROUTER_EXTERN_METHOD(BKRouterHandler,interface,param,resolve,reject)

/// 组件对外公开接口, module组件名, interface接口名, parm接收参数, resolve成功回调, reject失败回调
#define BKROUTER_EXTERN_METHOD(module,interface,param,resolve,reject) + (void)routerHandle_##module##_##interface:(NSDictionary*)param resolve:(BKRouterResolveBlock)resolve reject:(BKRouterRejectBlock)reject

NS_ASSUME_NONNULL_END



