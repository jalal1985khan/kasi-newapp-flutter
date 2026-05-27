# ProGuard rules for Twilio Programmable Video and WebRTC to prevent release-mode crashes

# Twilio Programmable Video Keep Rules
-keep class tvi.webrtc.** { *; }
-keep class com.twilio.video.** { *; }
-keep class com.twilio.common.** { *; }
-keepattributes InnerClasses

# Flutter WebRTC Keep Rules
-keep class com.cloudwebrtc.webrtc.** { *; }
-keep class org.webrtc.** { *; }
