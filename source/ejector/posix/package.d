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
    void logError(T...)(lazy string message, int errorNumber,
            lazy T additionalMessages, string caller = __FUNCTION__)
    {
        debug (VerboseEjector)
        {
            import core.stdc.string : strerror;
            import std.conv : text;

            logGeneric!T(message ~ ": " ~ errorNumber.strerror.text, additionalMessages, caller);
        }
    }

    IoctlResult ioctlWrapper(Command, T)(string drivePathName, Command command,
            ref int status, T third)
    in (drivePathName.length > 0)
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
            import result : inspectErr;

            return IoctlResult.err(IoctlError(IoctlErrorStage.open, errno))
                .inspectErr!(e => logError("open failed, " ~ drivePathName, e.errorNumber));
        }

        status = ioctl(fileDescriptor, command, third);
        if (status == -1)
        {
            import result : inspectErr;

            return IoctlResult.err(IoctlError(IoctlErrorStage.ioctl, errno))
                .inspectErr!(e => logError("ioctl failed, " ~ drivePathName, e.errorNumber));
        }

        import result : inspect;

        return IoctlResult.ok(status).inspect!(_ => logGeneric("ioctl succeeded, " ~ drivePathName));
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
        rt: 0x02, startingFeatureNumber: [0, 0x03], allocationLength: [
            0, RemovableMediumFeatureResponse.sizeof
        ],
    };

    GetDriveResult getDefaultDrive()
    {
        import std.file : exists;
        import std.path : buildPath;

        immutable devPath = "/dev";
        immutable devCdromPath = buildPath(devPath, "cdrom");

        if (devCdromPath.exists)
        {
            return GetDriveResult.ok(devCdromPath);
        }

        import std.concurrency : Generator;

        auto r = new Generator!size_t({
            import std.file : FileException;

            try
            {
                import std.file : dirEntries, SpanMode;

                foreach (entry; dirEntries(devPath, SpanMode.shallow))
                {
                    try
                    {
                        import std.algorithm : startsWith;
                        import std.path : baseName;

                        if (entry.isDir || entry.isFile)
                        {
                            // entry is NOT a special file!
                            continue;
                        }

                        if (entry.baseName.startsWith(cdDrivePrefix))
                        {
                            immutable deviceNumber = entry.baseName[cdDrivePrefix.length .. $];

                            import std.algorithm : all;
                            import std.ascii : isDigit;
                            import std.utf : byChar;

                            if (deviceNumber != "" && deviceNumber.byChar.all!isDigit)
                            {
                                import std.concurrency : yield;
                                import std.conv : to;

                                yield(deviceNumber.to!size_t);
                            }
                        }
                    }
                    catch (FileException fe)
                    {
                        continue;
                    }
                }
            }
            catch (FileException fe)
            {
            }
        });

        if (r.empty)
        {
            return GetDriveResult.err("Not found");
        }

        import std.algorithm : minElement;
        import std.conv : to;

        return GetDriveResult.ok(buildPath(devPath, cdDrivePrefix ~ r.minElement.to!string));
    }
}

version (Ejector_Posix) package(ejector)
{
    GetDriveResult getTargetDrive(string drivePathName)
    out (r)
    {
        import result : isErr, isOkAnd;

        assert(r.isOkAnd!(t => t.length > 0) || r.isErr);
    }
    do
    {
        import result : mapErr, inspect, inspectErr;

        immutable getDriveResult = drivePathName == "" ? getDefaultDrive() : GetDriveResult.ok(
                drivePathName);

        return getDriveResult.mapErr!(
                _ => "No optical drive /dev/cdrom or /dev/" ~ cdDrivePrefix ~ "* found")
            .inspect!(t => logGeneric("Target drive: <" ~ t ~ ">"))
            .inspectErr!(e => logGeneric(e));
    }
}
