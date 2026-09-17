# Pips release R8 rules.
#
# NewPipeExtractor (vendored flutter_youtube_downloader) bundles Rhino, whose
# Java-to-JSON converters reference desktop-only JDK classes (java.beans.*)
# that do not exist on Android. The references are never executed on device,
# so R8 only needs to be told not to fail on the missing classes.
-dontwarn java.beans.**
