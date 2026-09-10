# flutter_local_notifications 用 Gson 反序列化「已排定的通知」缓存。
# release 构建开启 R8 压缩后会抹掉泛型签名，导致：
#   java.lang.IllegalStateException: TypeToken must be created with a type argument
# 进而 cancel() / zonedSchedule() 全部失败。这里保留相关签名与类。
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes InnerClasses

-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class com.google.gson.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
