@echo off
set ANDROID_HOME=C:\Users\omaez\AppData\Local\Android\Sdk

echo Compilando para Android ARM64 (Release)...
"C:\Users\omaez\AppData\Roaming\Python\Python314\Scripts\scons.exe" platform=android target=template_release arch=arm64 ndk_version=30.0.14904198

echo.
echo Compilando para Android ARM32 (Release)...
"C:\Users\omaez\AppData\Roaming\Python\Python314\Scripts\scons.exe" platform=android target=template_release arch=arm32 ndk_version=30.0.14904198

echo.
echo Compilando para Android ARM64 (Debug)...
"C:\Users\omaez\AppData\Roaming\Python\Python314\Scripts\scons.exe" platform=android target=template_debug arch=arm64 ndk_version=30.0.14904198

echo.
echo Compilando para Android ARM32 (Debug)...
"C:\Users\omaez\AppData\Roaming\Python\Python314\Scripts\scons.exe" platform=android target=template_debug arch=arm32 ndk_version=30.0.14904198

echo Proceso completado.
