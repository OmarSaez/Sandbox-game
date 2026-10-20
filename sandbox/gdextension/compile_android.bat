@echo off
set ANDROID_HOME=C:\Users\omaez\AppData\Local\Android\Sdk
set ANDROID_NDK_ROOT=C:\Users\omaez\AppData\Local\Android\Sdk\ndk\27.2.12479018
set "PATH=C:\Users\omaez\AppData\Local\Programs\Python\Python312;C:\Users\omaez\AppData\Local\Programs\Python\Python312\Scripts;%PATH%"
"C:\Users\omaez\AppData\Local\Programs\Python\Python312\Scripts\scons.exe" platform=android target=template_release arch=arm64 ndk_version=27.2.12479018 -j8
"C:\Users\omaez\AppData\Local\Programs\Python\Python312\Scripts\scons.exe" platform=android target=template_release arch=arm32 ndk_version=27.2.12479018 -j8
"C:\Users\omaez\AppData\Local\Programs\Python\Python312\Scripts\scons.exe" platform=android target=template_debug arch=arm64 ndk_version=27.2.12479018 -j8
"C:\Users\omaez\AppData\Local\Programs\Python\Python312\Scripts\scons.exe" platform=android target=template_debug arch=arm32 ndk_version=27.2.12479018 -j8
