#!/bin/bash
set -e

dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
pushd "$dir" > /dev/null

if [ ! -d ../godot ]; then
	echo "No Godot clone found. Run ./setup.sh <Godot branch or tag> <dev> first."
	exit 1
fi

target=""
dev="false"
if [ -f "../godot/custom.py" ]; then
	dev="true"
fi

cpus=2
if [ "$OSTYPE" = "msys" ]; then
	cpus=$NUMBER_OF_PROCESSORS
elif [[ "$OSTYPE" = "darwin"* ]]; then
	cpus=$(sysctl -n hw.logicalcpu)
else
	cpus=$(grep -c ^processor /proc/cpuinfo)
fi

echo "CPUS: $cpus"

pushd ../godot
if [ `uname` == 'Darwin' ] && [ $dev = "false" ]; then	
	scons $target arch=x86_64 compiledb=yes custom_modules="../spine_godot" opengl3=yes --jobs=$cpus
	scons $target arch=arm64 compiledb=yes custom_modules="../spine_godot" opengl3=yes --jobs=$cpus

	pushd bin
	cp -r ../misc/dist/macos_tools.app .
	mv macos_tools.app Godot.app
	mkdir -p Godot.app/Contents/MacOS
	lipo -create godot.macos.editor.arm64 godot.macos.editor.x86_64 -output Godot
	strip -S -x Godot
	cp Godot Godot.app/Contents/MacOS/Godot
	chmod +x Godot.app/Contents/MacOS/Godot
	popd
else
	if [ "$OSTYPE" = "msys" ]; then
		target="vsproj=yes livepp=$LIVEPP"
	fi
	if [ "$dev" = "true" ]; then
		target="$target dev_build=true"
	fi
	scons $target compiledb=yes custom_modules="../spine_godot" opengl3=yes --jobs=$cpus	
	cp compile_commands.json ../build
	if [ -f "bin/godot.linuxbsd.editor.x86_64" ]; then
		strip bin/godot.linuxbsd.editor.x86_64
		chmod a+x bin/godot.linuxbsd.editor.x86_64
	fi
fi
popd

popd > /dev/null