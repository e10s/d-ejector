/*
Copyright electrolysis 2015.
Distributed under the Boost Software License, Version 1.0.
(See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
*/

module ejector;

enum TrayStatus
{
    ERROR,
    OPEN,
    CLOSED
}

version (linux)
{
    version = Ejector_Posix;
}

version (linux) private
{
    import linux;

    enum Command
    {
        // scsi/sg.h
        SG_IO = .SG_IO,

        // linux/cdrom.h
        CDROMEJECT = .CDROMEJECT,
        CDROMCLOSETRAY = .CDROMCLOSETRAY,
        CDROM_DRIVE_STATUS = .CDROM_DRIVE_STATUS,
        CDROM_GET_CAPABILITY = .CDROM_GET_CAPABILITY, // Other members might be added
    }

    // linux/cdrom.h
    enum Capability
    {
        CDC_CLOSE_TRAY = .CDC_CLOSE_TRAY,
        CDC_OPEN_TRAY = .CDC_OPEN_TRAY
    }
}

version (FreeBSD)
{
    version = Ejector_Posix;
    pragma(lib, "cam");
}

version (FreeBSD) private
{
    /*
        Generated from ccb.c

        enum CCB_SIZE = ??;
        enum CCB_CDB_LEN_OFFSET = ??;
        enum CCB_CDB_BYTES_OFFSET = ??;
    */
    mixin(import("ccb.mixin"));

    // cam/cam_ccb.h
    // https://github.com/freebsd/freebsd/blob/master/sys/cam/cam_ccb.h
    enum ccb_flags
    {
        CAM_DIR_IN = 0x00000040
    }

    union ccb;
    struct ccb_scsiio;

    extern (C) int csio_build(ccb_scsiio*, ubyte*, uint, uint, int, int,
        const(char)*, ...);

    // camlib.h
    // https://github.com/freebsd/freebsd/blob/master/lib/libcam/camlib.h
    enum CAM_ERRBUF_SIZE = 2048;
    struct cam_device;

    extern (C) __gshared ubyte[CAM_ERRBUF_SIZE] cam_errbuf;
    extern (C) cam_device* cam_open_device(const(char)*, int);
    extern (C) void cam_close_device(cam_device*);
    extern (C) int cam_send_ccb(cam_device*, ccb*);

    // sys/ioccom.h
    // https://github.com/freebsd/freebsd/blob/master/sys/sys/ioccom.h
    enum IOCPARM_SHIFT = 13;
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

version (Ejector_Posix) struct Ejector
{
    version (linux)
    {
        private string drive = "/dev/cdrom";
    }

    version (FreeBSD)
    {
        private string drive = "/dev/cd0";
    }

    private void logError(string msg, int errNo)
    {
        debug (VerboseEjector)
        {
            import core.stdc.string : strerror;
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
        scope (exit)
            fd != -1 && close(fd);

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

    version (FreeBSD) private auto camCommander(in ubyte[] cmd, ref ubyte[] buf)
    {
        import core.sys.posix.fcntl : O_RDWR;
        import std.string : toStringz;

        auto cam_dev = cam_open_device(drive.toStringz, O_RDWR);
        if (!cam_dev)
        {
            import std.stdio : stderr, writeln;

            stderr.writeln(cast(string) cam_errbuf);
            return false;
        }

        ubyte[CCB_SIZE] ccbLike; // substitute for union ccb
        csio_build(cast(ccb_scsiio*) ccbLike.ptr, buf.ptr,
            cast(uint) buf.length, ccb_flags.CAM_DIR_IN,
            1, 5000, "".toStringz);
        ccbLike[CCB_CDB_LEN_OFFSET] = cast(ubyte) cmd.length;
        ccbLike[CCB_CDB_BYTES_OFFSET .. CCB_CDB_BYTES_OFFSET + cmd.length] =
            cmd[];

        immutable csc = cam_send_ccb(cam_dev, cast(ccb*) ccbLike.ptr);
        if (csc == -1)
        {
            import std.stdio : stderr, writeln;

            stderr.writeln(cast(string) cam_errbuf);
            cam_close_device(cam_dev);
            return false;
        }

        cam_close_device(cam_dev);

        return true;
    }

    @property auto status()
    {
        version (linux)
        {
            int sta = -1;
            immutable r = send(Command.CDROM_DRIVE_STATUS, sta);
            if (r && sta != CDS_NO_INFO)
            {
                return sta == CDS_TRAY_OPEN ?
                    TrayStatus.OPEN : TrayStatus.CLOSED;
            }
            else
            {
                return TrayStatus.ERROR;
            }
        }
        version (FreeBSD)
        {
            enum MECHANISM_STATUS_CMD_LEN = 12;
            enum MECHANISM_STATUS_RESPONSE_BUF_LEN = 8;

            auto buf = new ubyte[MECHANISM_STATUS_RESPONSE_BUF_LEN];
            static immutable ubyte[MECHANISM_STATUS_CMD_LEN] mechanism_status_cmd =
                [0xBD, 0, 0, 0, 0, 0, 0, 0,
                    0, MECHANISM_STATUS_RESPONSE_BUF_LEN, 0, 0];

            immutable r = camCommander(mechanism_status_cmd[], buf);

            if (r)
            {
                debug (VerboseEjector)
                {
                    import std.stdio : stderr, writeln;

                    stderr.writeln("status succeeded");
                }
                return buf[1] & 0b00010000 ?
                    TrayStatus.OPEN : TrayStatus.CLOSED;
            }
            else
            {
                debug (VerboseEjector)
                {
                    import std.stdio : stderr, writeln;

                    stderr.writeln("status failed");
                }
                return TrayStatus.ERROR;
            }
        }
    }

    @property private auto opDispatch(string s)() if (s == "ejectableImpl" || s == "closableImpl")
    {
        enum GET_CONFIGURATION_CMD_LEN = 12;
        enum GET_CONFIGURATION_RESPONSE_BUF_LEN = 16;

        auto buf = new ubyte[GET_CONFIGURATION_RESPONSE_BUF_LEN];
        static immutable ubyte[GET_CONFIGURATION_CMD_LEN] get_configuration_cmd =
            [0x46, 0x02, 0, 0x03, 0, 0, 0,
                0, GET_CONFIGURATION_RESPONSE_BUF_LEN, 0, 0, 0];

        version (linux)
        {
            sg_io_hdr hdr = {
                interface_id: SG_INTERFACE_ID_ORIG,
                dxfer_direction: SG_DXFER_FROM_DEV,
                cmd_len: GET_CONFIGURATION_CMD_LEN,
                dxfer_len: GET_CONFIGURATION_RESPONSE_BUF_LEN,
                dxferp: buf.ptr,
                cmdp: cast(ubyte*) get_configuration_cmd.ptr,
                sbp: null,
                timeout: 5000
            };

            int sta;
            immutable r = send(Command.SG_IO, sta, &hdr);
        }
        version (FreeBSD)
        {
            immutable r = camCommander(get_configuration_cmd[], buf);
        }

        debug (VerboseEjector)
        {
            if (r)
            {
                import std.stdio : stderr, writeln;

                stderr.writeln(s, " succeeded");
            }
            else
            {
                import std.stdio : stderr, writeln;
                import std.conv : text;

                stderr.writeln(s, " failed");
            }
        }

        if (!r)
        {
            // We might have to execute MODE SENSE (10)
            return false;
        }

        // ftp://ftp.seagate.com/sff/INF-8090.PDF, p.638
        // Test the Eject bit
        static if (s == "ejectableImpl")
        {
            immutable eject = buf[12] & 0b00001000;
            return !!eject;
        }
        else
        {
            // Test the Version field and the Load bit
            immutable version_ = (buf[10] >> 2) & 0b00001111;
            if (version_ > 0)
            {
                immutable load = buf[12] & 0b00010000;
                return !!load;
            }
            // [[ Doubtful ]]
            // Guess from the Loading Mechanism Type field
            // Drives other than ones with caddy/slot type loading mechanism will be closable(?)
            // https://github.com/torvalds/linux/blob/master/drivers/scsi/sr.c
        else
            {
                // The Loading Mechanism Type field
                immutable mech = buf[12] >> 5;
                // Maybe closable
                return mech != 0;
            }
        }
    }

    @property auto ejectable()
    {
        return this.ejectableImpl;
    }

    @property auto closable()
    {
        return this.closableImpl;
    }

    auto open()
    {
        version (linux)
            return send(Command.CDROMEJECT);
        version (FreeBSD)
            return send(Command.CDIOCEJECT);
    }

    auto closed()
    {
        version (linux)
            return send(Command.CDROMCLOSETRAY);
        version (FreeBSD)
            return send(Command.CDIOCCLOSE);
    }
}
