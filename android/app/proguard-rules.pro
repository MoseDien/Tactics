# Keep Kotlinx Serialization serializers (rating/puzzle JSON is read at runtime).
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**
-keepclassmembers class **$$serializer { *; }
-keepclasseswithmembers class com.dienbell.tactics.** {
    kotlinx.serialization.KSerializer serializer(...);
}
