/*
Copyright electrolysis 2015.
Distributed under the Boost Software License, Version 1.0.
(See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
*/

module ejector;

version(Windows)
struct Ejector{
	private string drive = "";

	this(string driveLetter){  // "a" to "z" or "A" to "Z"
		import std.ascii : isAlpha;
		if(driveLetter.length == 1 && driveLetter[0].isAlpha){
			drive = "!" ~ driveLetter;
		}
	}
	this(char driveLetter){
		this(cast(string)[driveLetter]);
	}

	private auto send(string msg){
		import win32.mmsystem : mciSendString;

		version(Unicode){
			import std.utf : toUTF16z;
			auto m = msg.toUTF16z;
		}
		else{
			import std.string : toStringz;
			auto m = msg.toStringz;
		}

		auto r = mciSendString(m, null, 0, null);

		debug(Ejector){
			import std.stdio;
			import win32.mmsystem : mciGetErrorStringA;
			char[512] buf;
			mciGetErrorStringA(r, buf.ptr, buf.length);
			buf.writeln;
		}

		return r;
	}
	@property auto ejectable(){
		return !send("capability cdaudio" ~ drive ~ " can eject");
	}
	auto open(){
		return !!send("set cdaudio" ~ drive ~ " door open");
	}
	auto closed(){
		return !!send("set cdaudio" ~ drive ~ " door closed");
	}
}
