cd C:\Users\shpie\dev\emsdk
emsdk.bat install latest
emsdk.bat activate latest
emsdk_env.bat
cd C:\Users\shpie\dev\godot
scons platform=web target=template_release
