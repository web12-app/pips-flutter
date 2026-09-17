#!/usr/bin/env python3
"""Rewrite video_thumbnail's android/build.gradle for modern Gradle/AGP.

The published plugin (0.5.x, Java-only, no external dependencies) still
calls jcenter() (removed in Gradle 9) and pins AGP 4.1.0 on its
buildscript classpath, which breaks the build under AGP 9.x:

  * Could not find method jcenter() ...
  * 'kotlin-android' plugin requires one of the Android Gradle plugins
    (NPE from the stale AGP 4.1.0 classpath)

A minimal AGP-compatible script (same shape as file_picker's, which builds
fine in this project) is written over the cached copy. Run in CI right
after `flutter pub get`.
"""
import glob
import os
import sys

dirs = sorted(glob.glob(os.path.expanduser("~/.pub-cache/hosted/pub.dev/video_thumbnail-*")))
if not dirs:
    print("video_thumbnail not in pub cache; nothing to patch")
    sys.exit(0)

path = os.path.join(dirs[-1], "android", "build.gradle")
content = """group 'xyz.justsoft.video_thumbnail'
version '1.0-SNAPSHOT'

buildscript {
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath 'com.android.tools.build:gradle:8.5.1'
    }
}

rootProject.allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

apply plugin: 'com.android.library'

android {
    compileSdk flutter.compileSdkVersion
    namespace 'xyz.justsoft.video_thumbnail'

    defaultConfig {
        minSdk flutter.minSdkVersion
        testInstrumentationRunner "androidx.test.runner.AndroidJUnitRunner"
    }
    lintOptions {
        disable 'InvalidPackage'
    }
}
"""
with open(path, "w") as f:
    f.write(content)
print("patched", path)
