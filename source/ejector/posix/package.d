module ejector.posix;
import ejector.base;

version (linux)
{
    version = Ejector_Posix;
    import ejector.posix.linux, linux;

    mixin LinuxImpl;
}
version (FreeBSD)
{
    version = Ejector_Posix;
    import ejector.posix.freebsd;

    mixin FreeBSDImpl;
}

version (Ejector_Posix) private
{

    enum Mode
    {
        open,
        close
    }

    enum IoctlErrorStage
    {
        none,
        open,
        ioctl
    }

    import std.typecons : Tuple;

    alias IoctlResult = Tuple!(bool, "ok", IoctlErrorStage, "stage", int, "errorNo");

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

    IoctlResult ioctlWrapper(Command, T)(string drive, Command cmd, ref int sta, T third)
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
            immutable err = errno;
            logError("open failed, " ~ drive, err);
            return IoctlResult(false, IoctlErrorStage.open, err);
        }

        sta = ioctl(fd, cmd, third);
        if (sta == -1)
        {
            immutable err = errno;
            logError("ioctl failed, " ~ drive, err);
            return IoctlResult(false, IoctlErrorStage.ioctl, err);
        }

        logError("ioctl succeeded, " ~ drive, 0);

        return IoctlResult(true, IoctlErrorStage.none, 0);
    }

    IoctlResult ioctlWrapper(Command)(string drive, Command cmd, ref int sta)
    {
        return ioctlWrapper(drive, cmd, sta, 0);
    }

    IoctlResult ioctlWrapper(Command)(string drive, Command cmd)
    {
        int sta;
        return ioctlWrapper(drive, cmd, sta);
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

            if (r.ok)
            {
                stderr.writeln(mode, " succeeded");
            }
            else
            {
                stderr.writeln(mode, " failed");
            }
        }

        if (!r.ok)
        {
            // We might have to execute MODE SENSE (10)
            return false;
        }

        return parseEjectableClosable!mode(buf);
    }
}
