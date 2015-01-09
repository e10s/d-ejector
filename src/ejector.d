/*
Copyright electrolysis 2015.
Distributed under the Boost Software License, Version 1.0.
(See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
*/

module ejector;

version(linux)
struct Ejector{
	private enum Command{ /* linux/cdrom.h */
		CDROMEJECT = 0x5309,
		CDROMCLOSETRAY = 0x5319,
		CDROM_DRIVE_STATUS = 0x5326,
		// Other members might be added
	}
/*
	private enum Status{
		CDS_NO_INFO ,
		CDS_NO_DISC,
		CDS_TRAY_OPEN,
		CDS_DRIVE_NOT_READY,
		CDS_DISC_OK
	}
*/
	private string drive = "/dev/cdrom";
	
	private void logError(string msg, int errNo){
		debug(Ejector){
			import core.stdc.string: strerror;
			import std.conv : text;
			import std.stdio : stderr, writeln;

			stderr.writeln(msg, ": ", errNo.strerror.text);
		}
	}
	private auto send(Command cmd){
		import core.sys.posix.fcntl : O_NONBLOCK, O_RDONLY, fcntl_open = open;
		import core.sys.posix.sys.ioctl : ioctl;
		import core.sys.posix.unistd : close;
		import std.string : toStringz;
		debug(Ejector) import core.stdc.errno : errno;

		auto fd = fcntl_open(drive.toStringz, O_NONBLOCK | O_RDONLY);

		if(fd == -1){
			logError("fcntl_open failed, " ~ drive, errno);
			return false;
		}

		if(ioctl(fd, cmd) == -1){
			logError("ioctl failed, " ~ drive, errno);
			return false;
		}

		logError("ioctl succeeded, " ~ drive, 0);

		close(fd);
		return true;
	}
	@property auto ejectable(){
		return send(Command.CDROM_DRIVE_STATUS);  // not perfect?
	}
	auto open(){
		return send(Command.CDROMEJECT);
	}
	auto closed(){
		return send(Command.CDROMCLOSETRAY);
	}
}


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

	private void logError(string msg, uint errNo){
		debug(Ejector){
			import std.conv : text;
			import std.stdio : stderr, writeln;
			import win32.mmsystem : mciGetErrorStringA;

			char[512] buf;
			mciGetErrorStringA(errNo, buf.ptr, buf.length);
			stderr.writeln(msg, ": ", buf.ptr.text);
		}
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

		logError(`mciSendString("` ~ msg ~ `") ` ~ (r == 0 ? "succeeded" : "failed"), r);

		return !r;
	}
	@property auto ejectable(){
		return send("capability cdaudio" ~ drive ~ " can eject");
	}
	auto open(){
		return send("set cdaudio" ~ drive ~ " door open");
	}
	auto closed(){
		return send("set cdaudio" ~ drive ~ " door closed");
	}
}
