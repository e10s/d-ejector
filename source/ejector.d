/*
Copyright electrolysis 2015.
Distributed under the Boost Software License, Version 1.0.
(See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
*/

module ejector;

enum TrayStatus
{
    ERROR, OPEN, CLOSED
}

version(linux)
{
    version = Ejector_Posix;
}
version(FreeBSD)
{
    version = Ejector_Posix;
    pragma(lib, "cam");

    // cam_commander.c
    private extern(C) int get_tray_status(const char*, int*, char*, const int);
    private extern(C) int get_tray_capability(const char*, int*, char*, const int);
}

version(Ejector_Posix)
struct Ejector
{
    version(linux)
    {
        // linux/cdrom.h
        private enum Command
        {
            CDROMEJECT = 0x5309,
            CDROMCLOSETRAY = 0x5319,
            CDROM_DRIVE_STATUS = 0x5326,
            CDROM_GET_CAPABILITY = 0x5331, 
            // Other members might be added
        }

        // linux/cdrom.h
        private enum Status
        {
            CDS_NO_INFO,
            CDS_NO_DISC,
            CDS_TRAY_OPEN,
            CDS_DRIVE_NOT_READY,
            CDS_DISC_OK
        }

        private enum Capability
        {
            CDC_CLOSE_TRAY = 0x1,
            CDC_OPEN_TRAY = 0x2
        }

        private string drive = "/dev/cdrom";
    }

    version(FreeBSD)
    {
        // camlib.h
        // https://github.com/freebsd/freebsd/blob/master/lib/libcam/camlib.h
        private enum CAM_ERRBUF_SIZE = 2048;

        // sys/ioccom.h
        // https://github.com/freebsd/freebsd/blob/master/sys/sys/ioccom.h
        private enum IOCPARM_SHIFT= 13;
        private enum IOCPARM_MASK = (1 << IOCPARM_SHIFT) - 1;
        private enum IOC_VOID = 0x20000000;
        private enum _IOC(uint inout_, uint group, uint num, uint len) =
            uint(inout_ | ((len & IOCPARM_MASK) << 16) | (group << 8) | num);
        private enum _IO(uint g, uint n) = _IOC!(IOC_VOID, g, n, 0);

        // sys/cdio.h
        // https://github.com/freebsd/freebsd/blob/master/sys/sys/cdio.h
        private enum Command
        { 
            CDIOCEJECT = _IO!('c', 24),
            CDIOCCLOSE = _IO!('c', 28),
        }

        // sys/cdio.h
        private enum Capability
        {
            CDDOEJECT = 0x1,
            CDDOCLOSE = 0x2
        }

        private string drive = "/dev/cd0";
    }

    
    private void logError(string msg, int errNo)
    {
        debug(VerboseEjector)
        {
            import core.stdc.string: strerror;
            import std.conv : text;
            import std.stdio : stderr, writeln;

            stderr.writeln(msg, ": ", errNo.strerror.text);
        }
    }
    private auto send(Command cmd, ref int sta)
    {
        import core.stdc.errno : errno;
        import core.sys.posix.fcntl : O_NONBLOCK, O_RDONLY, open;
        import core.sys.posix.sys.ioctl : ioctl;
        import core.sys.posix.unistd : close;
        import std.string : toStringz;

        auto fd = open(drive.toStringz, O_NONBLOCK | O_RDONLY);
        scope(exit) fd != -1 && close(fd);

        if (fd == -1)
        {
            logError("open failed, " ~ drive, errno);
            return false;
        }

        sta = ioctl(fd, cmd);
        if (sta == -1)
        {
            logError("ioctl failed, " ~ drive, errno);
            return false;
        }

        logError("ioctl succeeded, " ~ drive, 0);

        return true;
    }
    private auto send(Command cmd)
    {
        int sta;
        return send(cmd, sta);
    }
    @property auto status()
    {
        version(linux)
        {
            int sta = -1;
            auto r = send(Command.CDROM_DRIVE_STATUS, sta);
            if (r && sta != Status.CDS_NO_INFO)
            {
                return sta == Status.CDS_TRAY_OPEN ?
                    TrayStatus.OPEN : TrayStatus.CLOSED;
            }
            else
            {
                return TrayStatus.ERROR;
            }
        }
        version(FreeBSD)
        {
            import std.string : toStringz;
            int sta;
            auto buf = new char[CAM_ERRBUF_SIZE];
            buf[] = '\0';
            auto r = get_tray_status(drive.toStringz, &sta, buf.ptr,
                CAM_ERRBUF_SIZE) == 0;
            if (r && sta != TrayStatus.ERROR)
            {
                debug(VerboseEjector)
                {
                    import std.stdio : stderr, writeln;
                    stderr.writeln("get_tray_status succeeded");
                }
                return sta == 1 ? TrayStatus.OPEN : TrayStatus.CLOSED;
            }
            else
            {
                debug(VerboseEjector)
                {
                    import std.conv : text;
                    import std.stdio : stderr, writeln;
                    stderr.writeln("get_tray_status failed,\n", buf.text);
                }
                return TrayStatus.ERROR;
            }
        }
    }
    @property auto ejectable()
    {
        version(linux)
        {
            int sta;
            auto r = send(Command.CDROM_GET_CAPABILITY, sta);
            return r && (sta & Capability.CDC_OPEN_TRAY);
        }
        version(FreeBSD)
        {
            import std.string : toStringz;
            int sta;
            auto buf = new char[CAM_ERRBUF_SIZE];
            buf[] = '\0';
            auto r = get_tray_capability(drive.toStringz, &sta, buf.ptr,
                CAM_ERRBUF_SIZE) == 0;
            debug(VerboseEjector)
            {
                import std.stdio : stderr, writeln;
                if (r)
                {
                    stderr.writeln("get_tray_capability succeeded");
                }
                else
                {
                    import std.conv : text;
                    stderr.writeln("get_tray_capability failed,\n", buf.text);
                }
            }
            return r && (sta & Capability.CDDOEJECT);
        }
    }
    auto open()
    {
        version(linux)
            return send(Command.CDROMEJECT);
        version(FreeBSD)
            return send(Command.CDIOCEJECT);
    }
    auto closed()
    {
        version(linux)
            return send(Command.CDROMCLOSETRAY);
        version(FreeBSD)
            return send(Command.CDIOCCLOSE);
    }
}


version(Windows)
private auto toStrZ(string s)
{
    version(Unicode)
    {
        import std.utf : toUTF16z;
        return s.toUTF16z;
    }
    else
    {
        import std.string : toStringz;
        return s.toStringz;
    }
}

version(Windows)
{
private:
    import windows.winioctl;
    import windows.winbase;
    import windows.windef;

    // ntddscsi.h
    struct SCSI_PASS_THROUGH_DIRECT
    {
        USHORT Length;
        UCHAR ScsiStatus;
        UCHAR PathId;
        UCHAR TargetId;
        UCHAR Lun;
        UCHAR CdbLength;
        UCHAR SenseInfoLength;
        UCHAR DataIn;
        ULONG DataTransferLength;
        ULONG TimeOutValue;
        PVOID DataBuffer;
        ULONG SenseInfoOffset;
        UCHAR[16] Cdb;
    }

    alias IOCTL_SCSI_BASE = FILE_DEVICE_CONTROLLER;
    enum IOCTL_SCSI_PASS_THROUGH_DIRECT = CTL_CODE_T!(IOCTL_SCSI_BASE, 0x0405,
        METHOD_BUFFERED, FILE_READ_ACCESS | FILE_WRITE_ACCESS);
    enum SCSI_IOCTL_DATA_IN = 1;


    // scsi.h
    enum SCSIOP_MECHANISM_STATUS = UCHAR(0xBD);
    enum CDB12GENERIC_LENGTH = 12;


    // ntddmmc.h
    enum FEATURE_NUMBER
    {
        FeatureRemovableMedium = 0x0003
    }

    enum SCSI_GET_CONFIGURATION_REQUEST_TYPE_ONE = 0x2;

    struct GET_CONFIGURATION_IOCTL_INPUT
    {
        FEATURE_NUMBER Feature;
        ULONG RequestType;
        PVOID[2] Reserved;
    }


    //ntddcdrm.h
    alias IOCTL_CDROM_BASE = FILE_DEVICE_CD_ROM;
    enum IOCTL_CDROM_GET_CONFIGURATION = CTL_CODE_T!(IOCTL_CDROM_BASE, 0x0016,
        METHOD_BUFFERED, FILE_READ_ACCESS);
}

version(Windows)
struct Ejector
{
    private string drive = "";

    this(string driveLetter)
    {
        // "a" to "z" or "A" to "Z"
        import std.uni : isAlpha, toUpper;

        if (driveLetter.length == 1 && driveLetter[0].isAlpha)
        {
            drive = driveLetter.toUpper;
        }
    }
    this(char driveLetter)
    {
        this(cast(string)[driveLetter]);
    }

    private @property auto defaultDrive()
    {
        import std.algorithm : find, map;
        import std.ascii : uppercase;
        import std.string : toStringz;
        import windows.winbase : DRIVE_CDROM, GetDriveType;

        auto drives = uppercase.map!(a => (cast(char)a))
            .find!(a => GetDriveType(toStrZ(a ~ `:\`)) == DRIVE_CDROM);
        if (drives.empty)
        {
            return "";
        }
        else
        {
            import std.conv : text;
            return drives.front.text;
        }
    }

    private void logError(string msg, uint errNo)
    {
        debug(VerboseEjector)
        {
            import std.conv : text;
            import std.stdio : stderr, writeln;

            char[512] buf;
            FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM, null, errNo,
                MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
                buf.ptr, buf.length, null);
            stderr.writeln(msg, ": ", buf.ptr.text);
        }
    }
    private auto createDriveHandle()
    {
        auto drivePath = `\\.\` ~ (drive == "" ? defaultDrive : drive) ~ ":";

        auto h = CreateFile(drivePath.toStrZ, GENERIC_READ | GENERIC_WRITE,
            FILE_SHARE_READ | FILE_SHARE_WRITE, null, OPEN_EXISTING, 0, null);

        auto err = GetLastError;
        logError(`CreateFile("` ~ drivePath ~ `") ` ~
            (err == 0 ? "succeeded" : "failed"), err);

        return h;
    }
    @property auto status()
    {
        auto h = createDriveHandle();
        scope(exit) h != INVALID_HANDLE_VALUE && CloseHandle(h);

        if (h == INVALID_HANDLE_VALUE)
        {
            return TrayStatus.ERROR;
        }

        auto sptdSize = USHORT(SCSI_PASS_THROUGH_DIRECT.sizeof);
        ubyte padding = 255;
        ubyte[8] buf = padding;  // Mechanism Status Header has 8 bytes

        auto sptd = SCSI_PASS_THROUGH_DIRECT();
        sptd.Length = sptdSize;
        // PathId, TargetId and Lun are "don't-care" params:
        // https://msdn.microsoft.com/en-us/library/windows/hardware/ff560521%28v=vs.85%29.aspx
        sptd.CdbLength = 12;
        sptd.DataIn = SCSI_IOCTL_DATA_IN;
        sptd.DataTransferLength = buf.length;
        sptd.TimeOutValue = 5;
        sptd.DataBuffer = buf.ptr;
        sptd.Cdb[0] = SCSIOP_MECHANISM_STATUS;
        sptd.Cdb[9] = buf.length;

        DWORD ret;
        auto dic = DeviceIoControl(h, IOCTL_SCSI_PASS_THROUGH_DIRECT,
            &sptd, sptdSize, &sptd, sptdSize, &ret, null);

        auto err = GetLastError;
        logError("DeviceIoControl() " ~
            (err == 0 ? "succeeded" : "failed"), err);

        debug(VerboseEjector)
        {
            import std.stdio : stderr, writeln;
            stderr.writeln(buf);
        }

        if (!dic || sptd.ScsiStatus != 0 || buf[1] == padding)
        {
            return TrayStatus.ERROR;
        }
        else
        {
            // ftp://ftp.seagate.com/sff/INF-8090.PDF, p.742
            return (buf[1] & 0b00010000) ? TrayStatus.OPEN : TrayStatus.CLOSED;
        }
    }
    @property auto ejectable()
    {
        auto h = createDriveHandle();
        scope(exit) h != INVALID_HANDLE_VALUE && CloseHandle(h);

        if (h == INVALID_HANDLE_VALUE)
        {
            return false;
        }

        auto gciiSize = USHORT(GET_CONFIGURATION_IOCTL_INPUT.sizeof);
        enum bufSize = 16;  // Response has 16 bytes (header + descriptor)
        ubyte[bufSize] buf;

        auto gcii = GET_CONFIGURATION_IOCTL_INPUT();
        gcii.Feature = FEATURE_NUMBER. FeatureRemovableMedium;
        gcii.RequestType = SCSI_GET_CONFIGURATION_REQUEST_TYPE_ONE;

        DWORD ret;
        auto dic = DeviceIoControl(h, IOCTL_CDROM_GET_CONFIGURATION,
            &gcii, gciiSize, buf.ptr, bufSize, &ret, null);
        auto err = GetLastError;
        logError("DeviceIoControl() " ~
            (err == 0 ? "succeeded" : "failed"), err);

        debug(VerboseEjector)
        {
            import std.stdio : stderr, writeln;
            stderr.writeln(buf);
        }

        // ftp://ftp.seagate.com/sff/INF-8090.PDF, p.638
        // Test the Eject bit
        auto eject = !!(buf[12] & 0b00001000);
        // If dic fails, we might have to execute MODE SENSE (10)
        return dic && eject;

        // The Loading Mechanism Type field
        // auto mech = buf[12] >> 5;

        // Test the Version field and the Load bit
        /*
        auto version_ = (buf[10] >> 2) & 0b00001111;
        auto load = !!(buf[12] & 0b00010000);
        if (version_ > 0 && load)
        {
            // Closable
        }
        */
        // [[ Doubtful ]]
        // Drives other than ones with caddy/slot type loading mechanism will be closable(?)
        // https://github.com/torvalds/linux/blob/master/drivers/scsi/sr.c
        /*
        else if (version_ != 0)
        {
            // Maybe closable
        }
        */
    }
    auto opDispatch(string s)() if (s == "open" || s == "closed")
    {
        auto h = createDriveHandle();
        scope(exit) h != INVALID_HANDLE_VALUE && CloseHandle(h);

        if (h == INVALID_HANDLE_VALUE)
        {
            return false;
        }

        DWORD ret;
        enum cmd = s == "open" ?
            IOCTL_STORAGE_EJECT_MEDIA : IOCTL_STORAGE_LOAD_MEDIA;
        auto dic = DeviceIoControl(h, cmd, null, 0, null, 0, &ret, null);
        auto err = GetLastError;
        import std.stdio;writeln(dic);
        logError("DeviceIoControl() " ~
            (err == 0 ? "succeeded" : "failed"), err);

        return !!dic;
    }
}
