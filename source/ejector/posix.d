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
}
