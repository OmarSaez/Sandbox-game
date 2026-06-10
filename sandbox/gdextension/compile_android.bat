@echo off
set ANDROID_HOME=C:\Users\omaez\AppData\Local\Android\Sdk
set ANDROID_NDK_ROOT=C:\Users\omaez\AppData\Local\Android\Sdk\ndk\23.2.8568313
python -m SCons platform=android target=template_release arch=arm64
python -m SCons platform=android target=template_release arch=arm32
python -m SCons platform=android target=template_debug arch=arm64
python -m SCons platform=android target=template_debug arch=arm32
