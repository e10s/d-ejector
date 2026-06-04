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
    void logError(T...)(lazy string message, int errorNumber, lazy T additionalMessages, string caller = __FUNCTION__)
    {
        debug (VerboseEjector)
        {
            import core.stdc.string : strerror;
            import std.conv : text;

            logGeneric!T(message ~ ": " ~ errorNumber.strerror.text, additionalMessages, caller);
        }
    }

    IoctlResult ioctlWrapper(Command, T)(string drivePathName, Command command, ref int status, T third)
    {
        import core.stdc.errno : errno;
        import core.sys.posix.fcntl : O_NONBLOCK, O_RDONLY, open;
        import core.sys.posix.sys.ioctl : ioctl;
        import core.sys.posix.unistd : close;
        import std.string : toStringz;

        immutable fileDescriptor = open(drivePathName.toStringz, O_NONBLOCK | O_RDONLY);
        scope (exit)
            fileDescriptor != -1 && close(fileDescriptor);

        if (fileDescriptor == -1)
        {
            immutable errorNumber = errno;
            logError("open failed, " ~ drivePathName, errorNumber);
            return IoctlResult(false, IoctlErrorStage.open, errorNumber);
        }

        status = ioctl(fileDescriptor, command, third);
        if (status == -1)
        {
            immutable errorNumber = errno;
            logError("ioctl failed, " ~ drivePathName, errorNumber);
            return IoctlResult(false, IoctlErrorStage.ioctl, errorNumber);
        }

        logGeneric("ioctl succeeded, " ~ drivePathName);

        return IoctlResult(true, IoctlErrorStage.none, 0);
    }

    IoctlResult ioctlWrapper(Command)(string drivePathName, Command command, ref int status)
    {
        return ioctlWrapper(drivePathName, command, status, 0);
    }

    IoctlResult ioctlWrapper(Command)(string drivePathName, Command command)
    {
        int status;
        return ioctlWrapper(drivePathName, command, status);
    }

    static immutable GetConfigurationCDB getConfigurationCDB = {
        rt: 0x02,
        startingFeatureNumber: [0, 0x03],
        allocationLength: [0, RemovableMediumFeatureResponse.sizeof],
    };

}
