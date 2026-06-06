@echo off
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat"
"C:\Users\omaez\AppData\Roaming\Python\Python314\Scripts\scons.exe" platform=windows target=template_debug
