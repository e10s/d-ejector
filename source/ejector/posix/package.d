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

    static immutable GetConfigurationCmd rmfCmd = {
        rt: 0x02,
        startingFeatureNumber: [0, 0x03],
        allocationLength: [0, RemovableMediumFeatureResponse.sizeof],
    };

    bool ejectableClosableCommon(alias sendGetConfiguration, OpenCloseMode mode)(string drive)
    {
        auto buf = RemovableMediumFeatureResponse();
        immutable r = sendGetConfiguration(drive, buf);

        debug (VerboseEjector)
        {
            import std.stdio : stderr, writeln;

            if (r.ok)
            {
                stderr.writeln("get configuration succeeded, ", drive);
                stderr.writeln(buf);
            }
            else
            {
                stderr.writeln("get configuration failed, ", drive);
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
