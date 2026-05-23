/*
Copyright electrolysis 2015.
Distributed under the Boost Software License, Version 1.0.
(See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
*/

module ejector_linux;

import ejector_base;

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

version (Ejector_Posix) struct Ejector
{
    version (linux)
    {
        private string drive = "/dev/cdrom";
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
    }

    auto closed()
    {
        version (linux)
            return send(Command.CDROMCLOSETRAY);
    }
}
