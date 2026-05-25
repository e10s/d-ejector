module ejector.posix;
import ejector.base;

version (linux)
{
    version = Ejector_Posix;
    import ejector.linux, linux;

    mixin LinuxImpl;
}
version (FreeBSD)
{
    version = Ejector_Posix;
    import ejector.freebsd;

    mixin FreeBSDImpl;
}

version (Ejector_Posix) package
{
    enum Mode
    {
        open,
        close
    }

    void logError(string msg, int errNo)
    {
        debug (VerboseEjector)
        {
            import core.stdc.string : strerror;
            import std.conv : text;
            import std.stdio : stderr, writeln;

            stderr.writeln(msg, ": ", errNo.strerror.text);
        }
    }

    auto send(Command, T)(string drive, Command cmd, ref int sta, T third)
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

    auto send(Command)(string drive, Command cmd, ref int sta)
    {
        return send(drive, cmd, sta, 0);
    }

    auto send(Command)(string drive, Command cmd)
    {
        int sta;
        return send(drive, cmd, sta);
    }

    enum GET_CONFIGURATION_CMD_LEN = 12;
    enum GET_CONFIGURATION_RESPONSE_BUF_LEN = 16;

    static immutable ubyte[GET_CONFIGURATION_CMD_LEN] get_configuration_cmd =
        [0x46, 0x02, 0, 0x03, 0, 0, 0,
            0, GET_CONFIGURATION_RESPONSE_BUF_LEN, 0, 0, 0];

    bool parseEjectableClosable(Mode mode)(in ubyte[] buf)
    {
        // ftp://ftp.seagate.com/sff/INF-8090.PDF, p.638
        // Test the Eject bit
        static if (mode == Mode.open)
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

            // The Loading Mechanism Type field
            immutable mech = buf[12] >> 5;
            // Maybe closable
            return mech != 0;
        }
    }

    bool ejectableClosableCommon(alias sendGetConfiguration, Mode mode)(string drive)
    {
        auto buf = new ubyte[GET_CONFIGURATION_RESPONSE_BUF_LEN];
        immutable r = sendGetConfiguration(drive, buf);

        debug (VerboseEjector)
        {
            import std.stdio : stderr, writeln;

            if (r)
            {
                stderr.writeln(mode, " succeeded");
            }
            else
            {
                stderr.writeln(mode, " failed");
            }
        }

        if (!r)
        {
            // We might have to execute MODE SENSE (10)
            return false;
        }

        return parseEjectableClosable!mode(buf);
    }
}
