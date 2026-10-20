@echo off
set ANDROID_HOME=C:\Users\omaez\AppData\Local\Android\Sdk
set "PATH=C:\Users\omaez\AppData\Local\Programs\Python\Python312;C:\Users\omaez\AppData\Local\Programs\Python\Python312\Scripts;%PATH%"

echo Compilando para Android ARM64 (Release)...
"C:\Users\omaez\AppData\Local\Programs\Python\Python312\Scripts\scons.exe" platform=android target=template_release arch=arm64 ndk_version=27.2.12479018 -j8

echo.
echo Compilando para Android ARM32 (Release)...
"C:\Users\omaez\AppData\Local\Programs\Python\Python312\Scripts\scons.exe" platform=android target=template_release arch=arm32 ndk_version=27.2.12479018 -j8

echo.
echo Compilando para Android ARM64 (Debug)...
"C:\Users\omaez\AppData\Local\Programs\Python\Python312\Scripts\scons.exe" platform=android target=template_debug arch=arm64 ndk_version=27.2.12479018 -j8

echo.
echo Compilando para Android ARM32 (Debug)...
"C:\Users\omaez\AppData\Local\Programs\Python\Python312\Scripts\scons.exe" platform=android target=template_debug arch=arm32 ndk_version=27.2.12479018 -j8

echo Proceso completado.
