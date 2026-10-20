@echo off
echo Compilando para Windows (Godot Editor)...
set "PATH=C:\Users\omaez\AppData\Local\Programs\Python\Python312;C:\Users\omaez\AppData\Local\Programs\Python\Python312\Scripts;C:\Users\omaez\AppData\Local\Microsoft\WinGet\Packages\BrechtSanders.WinLibs.POSIX.UCRT_Microsoft.Winget.Source_8wekyb3d8bbwe\mingw64\bin;%PATH%"
"C:\Users\omaez\AppData\Local\Programs\Python\Python312\Scripts\scons.exe" platform=windows target=template_debug use_mingw=yes -j8
pause
