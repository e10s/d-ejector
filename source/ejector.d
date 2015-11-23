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

version(linux) private
{
    enum Command
    {
        // scsi/sg.h
        SG_IO = 0x2285,

        // linux/cdrom.h
        CDROMEJECT = 0x5309,
        CDROMCLOSETRAY = 0x5319,
        CDROM_DRIVE_STATUS = 0x5326,
        CDROM_GET_CAPABILITY = 0x5331,
        // Other members might be added
    }

    // linux/cdrom.h
    enum Status
    {
        CDS_NO_INFO,
        CDS_NO_DISC,
        CDS_TRAY_OPEN,
        CDS_DRIVE_NOT_READY,
        CDS_DISC_OK
    }

    enum Capability
    {
        CDC_CLOSE_TRAY = 0x1,
        CDC_OPEN_TRAY = 0x2
    }

    // scsi/sg.h
    struct sg_io_hdr
    {
        int interface_id;
        int dxfer_direction;
        ubyte cmd_len;
        ubyte mx_sb_len;
        ushort iovec_count;
        uint dxfer_len;
        void* dxferp;
        ubyte* cmdp;
        void* sbp;
        uint timeout;
        uint flags;
        int pack_id;
        void* usr_ptr;
        ubyte status;
        ubyte masked_status;
        ubyte msg_status;
        ubyte sb_len_wr;
        ushort host_status;
        ushort driver_status;
        int resid;
        uint duration;
        uint info;
    }

    enum SG_INTERFACE_ID_ORIG = 'S';
    enum SG_DXFER_FROM_DEV = -3;
}


version(FreeBSD)
{
    version = Ejector_Posix;
    pragma(lib, "cam");
}

version(FreeBSD) private
{
    // cam_commander.c
    extern(C) int get_tray_status(const char*, int*, char*, const int);
    extern(C) int get_tray_capability(const char*, int*, char*, const int);

    // camlib.h
    // https://github.com/freebsd/freebsd/blob/master/lib/libcam/camlib.h
    enum CAM_ERRBUF_SIZE = 2048;

    // sys/ioccom.h
    // https://github.com/freebsd/freebsd/blob/master/sys/sys/ioccom.h
    enum IOCPARM_SHIFT= 13;
    enum IOCPARM_MASK = (1 << IOCPARM_SHIFT) - 1;
    enum IOC_VOID = 0x20000000;
    enum _IOC(uint inout_, uint group, uint num, uint len) =
        uint(inout_ | ((len & IOCPARM_MASK) << 16) | (group << 8) | num);
    enum _IO(uint g, uint n) = _IOC!(IOC_VOID, g, n, 0);

    // sys/cdio.h
    // https://github.com/freebsd/freebsd/blob/master/sys/sys/cdio.h
    enum Command
    {
        CDIOCEJECT = _IO!('c', 24),
        CDIOCCLOSE = _IO!('c', 28),
    }

    // sys/cdio.h
    enum Capability
    {
        CDDOEJECT = 0x1,
        CDDOCLOSE = 0x2
    }
}


version(Ejector_Posix)
struct Ejector
{
    version(linux)
    {
        private string drive = "/dev/cdrom";
    }

    version(FreeBSD)
    {
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
    private auto send(T)(Command cmd, ref int sta, T third)
    {
        import core.stdc.errno : errno;
        import core.sys.posix.fcntl : O_NONBLOCK, O_RDONLY, open;
        import core.sys.posix.sys.ioctl : ioctl;
        import core.sys.posix.unistd : close;
        import std.string : toStringz;

        immutable fd = open(drive.toStringz, O_NONBLOCK | O_RDONLY);
        scope(exit) fd != -1 && close(fd);

        if (fd == -1)
        {
            logError("open failed, " ~ drive, errno);
            return false;
        }

        sta = ioctl(fd, cmd, third);
        if (sta == -1)
        {
            logError("ioctl failed, " ~ drive, errno);
            return false;
        }

        logError("ioctl succeeded, " ~ drive, 0);

        return true;
    }
    private auto send(Command cmd, ref int sta)
    {
        return send(cmd, sta, 0);
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
            immutable r = send(Command.CDROM_DRIVE_STATUS, sta);
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
            immutable r = get_tray_status(drive.toStringz, &sta, buf.ptr,
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
            enum GET_CONFIGURATION_CMD_LEN = 12;
            enum GET_CONFIGURATION_RESPONSE_BUF_LEN = 16;

            auto buf = new ubyte[GET_CONFIGURATION_RESPONSE_BUF_LEN];
            static immutable ubyte[GET_CONFIGURATION_CMD_LEN]
                get_configuration_cmd =
                [0x46, 0x02, 0, 0x03, 0, 0, 0, 0, 16, 0, 0, 0];

            auto hdr = sg_io_hdr();
            with (hdr)
            {
                interface_id = SG_INTERFACE_ID_ORIG;
                dxfer_direction = SG_DXFER_FROM_DEV;
                cmd_len = GET_CONFIGURATION_CMD_LEN;
                dxfer_len = GET_CONFIGURATION_RESPONSE_BUF_LEN;
                dxferp = buf.ptr;
                cmdp = cast(ubyte*)get_configuration_cmd.ptr;
                sbp = null;
                timeout = 5000;
            }

            int sta;
            immutable r = send(Command.SG_IO, sta, &hdr);

            int cap;

            if (r)
            {
                // ftp://ftp.seagate.com/sff/INF-8090.PDF, p.638
                // Test the Eject bit
                immutable eject = buf[12] & 0b00001000;
                if (eject)
                {
                    cap |= Capability.CDC_OPEN_TRAY;
                }

                // The Loading Mechanism Type field
                immutable mech = buf[12] >> 5;

                // Test the Version field and the Load bit
                immutable version_ = (buf[10] >> 2) & 0b00001111;
                immutable load = buf[12] & 0b00010000;
                if (version_ > 0 && load)
                {
                    cap |= Capability.CDC_CLOSE_TRAY;
                }
                // [[ Doubtful ]]
                // Guess from the Loading Mechanism Type field
                // Drives other than ones with caddy/slot type loading mechanism will be closable(?)
                // https://github.com/torvalds/linux/blob/master/drivers/scsi/sr.c
                else if (mech != 0)
                {
                    // Maybe closable
                    cap |= Capability.CDC_CLOSE_TRAY;
                }
            }
            /*
            else
            {
                // We might have to execute MODE SENSE (10)
            }
            */

            return r && (cap & Capability.CDC_OPEN_TRAY);
        }
        version(FreeBSD)
        {
            import std.string : toStringz;
            int sta;
            auto buf = new char[CAM_ERRBUF_SIZE];
            buf[] = '\0';
            immutable r = get_tray_capability(drive.toStringz, &sta, buf.ptr,
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



version(Windows) private
{
    auto toStrZ(string s)
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

    struct GET_CONFIGURATION_HEADER(T)
    {
        UCHAR[4] DataLength;
        UCHAR[2] Reserved;
        UCHAR[2] CurrentProfile;
        T Data;  // Modified for convenience
    }

    struct FEATURE_HEADER
    {
        UCHAR[2] FeatureCode;
        import std.bitmanip : bitfields;
        mixin(bitfields!(
            UCHAR, "Current", 1,
            UCHAR, "Persistent", 1,
            UCHAR, "Version" , 4,
            UCHAR, "Reserved0", 2
        ));
        UCHAR AdditionalLength;
    }

    struct FEATURE_DATA_REMOVABLE_MEDIUM
    {
        FEATURE_HEADER Header;
        import std.bitmanip : bitfields;
        mixin(bitfields!(
            UCHAR, "Lockable", 1,
            UCHAR, "DBML", 1,  // If Version >= 2
            UCHAR, "DefaultToPrevent", 1,
            UCHAR, "Eject", 1,
            UCHAR, "Load", 1,  // If Version >= 1
            UCHAR, "LoadingMechanism", 3
        ));
        UCHAR[3] Reserved3;
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
        immutable drivePath = `\\.\` ~
            (drive == "" ? defaultDrive : drive) ~ ":";

        auto h = CreateFile(drivePath.toStrZ, GENERIC_READ | GENERIC_WRITE,
            FILE_SHARE_READ | FILE_SHARE_WRITE, null, OPEN_EXISTING, 0, null);

        immutable err = GetLastError;
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

        enum sptdSize = USHORT(SCSI_PASS_THROUGH_DIRECT.sizeof);
        enum padding = ubyte(255);
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
        immutable dic = DeviceIoControl(h, IOCTL_SCSI_PASS_THROUGH_DIRECT,
            &sptd, sptdSize, &sptd, sptdSize, &ret, null);

        immutable err = GetLastError;
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
    @property auto opDispatch(string s)()
        if (s == "ejectable" || s == "closable")
    {
        auto h = createDriveHandle();
        scope(exit) h != INVALID_HANDLE_VALUE && CloseHandle(h);

        if (h == INVALID_HANDLE_VALUE)
        {
            return false;
        }

        alias GCH = GET_CONFIGURATION_HEADER!FEATURE_DATA_REMOVABLE_MEDIUM;
        enum gciiSize = DWORD(GET_CONFIGURATION_IOCTL_INPUT.sizeof);
        enum gchSize = DWORD(GCH.sizeof);

        auto gcii = GET_CONFIGURATION_IOCTL_INPUT();
        gcii.Feature = FEATURE_NUMBER.FeatureRemovableMedium;
        gcii.RequestType = SCSI_GET_CONFIGURATION_REQUEST_TYPE_ONE;
        auto gch = GCH();

        DWORD ret;
        immutable dic = DeviceIoControl(h, IOCTL_CDROM_GET_CONFIGURATION,
            &gcii, gciiSize, &gch, gchSize, &ret, null);
        immutable err = GetLastError;
        logError("DeviceIoControl() " ~
            (err == 0 ? "succeeded" : "failed"), err);

        if (!dic)
        {
            // If dic fails, we might have to execute MODE SENSE (10)
            return false;
        }

        debug(VerboseEjector)
        {
            import std.stdio : stderr, writeln;
            stderr.writeln(gch);
        }

        static if (s == "ejectable")
        {
            // ftp://ftp.seagate.com/sff/INF-8090.PDF, p.638
            // Test the Eject bit
            return !!gch.Data.Eject;
        }
        else
        {
            // Test the Version field and the Load bit
            if (gch.Data.Header.Version > 0)
            {
                return !!gch.Data.Load;
            }
            // [[ Doubtful ]]
            // Drives other than ones with caddy/slot type loading mechanism will be closable(?)
            // https://github.com/torvalds/linux/blob/master/drivers/scsi/sr.c
            else
            {
                // Maybe closable
                return gch.Data.LoadingMechanism != 0;
            }
        }
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
        immutable dic = DeviceIoControl(h, cmd, null, 0, null, 0, &ret, null);
        immutable err = GetLastError;

        logError("DeviceIoControl() " ~
            (err == 0 ? "succeeded" : "failed"), err);

        return !!dic;
    }
}
