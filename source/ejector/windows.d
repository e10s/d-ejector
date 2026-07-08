/*
Copyright electrolysis 2015.
Distributed under the Boost Software License, Version 1.0.
(See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
*/

module ejector.windows;
import ejector.base;

version (Windows) private
{
    import core.sys.windows.winioctl;
    import core.sys.windows.winbase;
    import core.sys.windows.windef;

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

    // ntddmmc.h
    enum FEATURE_NUMBER
    {
        FeatureRemovableMedium = 0x0003
    }

    /*
    struct GET_CONFIGURATION_HEADER
    {
        UCHAR[4] DataLength;
        UCHAR[2] Reserved;
        UCHAR[2] CurrentProfile;
        UCHAR[0] Data;
    }

    struct FEATURE_HEADER
    {
        UCHAR[2] FeatureCode;
        import std.bitmanip : bitfields;

        mixin(bitfields!(
                UCHAR, "Current", 1,
                UCHAR, "Persistent", 1,
                UCHAR, "Version", 4,
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
                UCHAR, "DBML", 1, // If Version >= 2
                UCHAR, "DefaultToPrevent", 1,
                UCHAR, "Eject", 1,
                UCHAR, "Load", 1, // If Version >= 1
                UCHAR, "LoadingMechanism", 3
        ));
        UCHAR[3] Reserved3;
    }
    */

    enum SCSI_GET_CONFIGURATION_REQUEST_TYPE_ONE = 0x2;

    struct GET_CONFIGURATION_IOCTL_INPUT
    {
        FEATURE_NUMBER Feature;
        ULONG RequestType;
        PVOID[2] Reserved;
    }

    // ntddcdrm.h
    alias IOCTL_CDROM_BASE = FILE_DEVICE_CD_ROM;
    enum IOCTL_CDROM_GET_CONFIGURATION = CTL_CODE_T!(IOCTL_CDROM_BASE, 0x0016,
                METHOD_BUFFERED, FILE_READ_ACCESS);
}

version (Windows) private
{
    import result : Result;

    string errorNumberToString(uint errorNumber)
    {
        import std.conv : to;
        import std.string : chomp;

        char[512] buffer;
        FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, null, errorNumber,
                MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT), buffer.ptr, buffer.length, null);

        return buffer.ptr.to!string.chomp;
    }

    void logError(T...)(lazy string message, uint errorNumber,
            lazy T additionalMessages, string caller = __FUNCTION__)
    {
        debug (VerboseEjector)
        {
            logGeneric!T(message ~ ": " ~ errorNumberToString(errorNumber),
                    additionalMessages, caller);
        }
    }

    IoctlResult ioctlWrapper(Command, IoctlInput = void, IoctlOutput = void)(string driveLetter,
            Command command, IoctlInput* ioctlInputPointer, IoctlOutput* ioctlOutputPointer)
    in (isValidDriveLetter(driveLetter))
    {
        auto impl(HANDLE handle)
        {
            scope (exit)
            {
                CloseHandle(handle);
            }

            DWORD ioctlInputSize;
            DWORD ioctlOutputSize;
            if (ioctlInputPointer !is null)
            {
                ioctlInputSize = IoctlInput.sizeof;
            }
            if (ioctlOutputPointer !is null)
            {
                ioctlOutputSize = IoctlOutput.sizeof;
            }

            immutable status = DeviceIoControl(handle, command, ioctlInputPointer,
                    ioctlInputSize, ioctlOutputPointer, ioctlOutputSize, null, null);
            if (!status)
            {
                import result : inspectErr;

                return IoctlResult.err(IoctlError(IoctlErrorStage.ioctl, GetLastError()))
                    .inspectErr!(e => logError("ioctl failed, " ~ driveLetter, e.errorNumber));
            }

            return IoctlResult.ok(status);
        }

        import result : andThen, inspect, mapErr;

        return createDriveHandle(driveLetter).mapErr!(e => IoctlError(IoctlErrorStage.open, e))
            .andThen!(t => impl(cast(HANDLE) t))
            .inspect!(_ => logGeneric("ioctl succeeded, " ~ driveLetter));
    }

    IoctlResult ioctlWrapper(Command)(string driveLetter, Command command)
    {
        return ioctlWrapper(driveLetter, command, null, null);
    }

    auto isValidDriveLetter(string driveLetter)
    {
        import std.uni : isAlpha;

        return driveLetter.length == 1 && driveLetter[0].isAlpha;
    }

    import std.traits : isSomeString, isSomeChar;

    auto isCDDrive(T)(T driveLetter) if (isSomeString!T || isSomeChar!T)
    {
        import std.conv : to;
        import std.utf : toUTF16z;
        import core.sys.windows.winbase : DRIVE_CDROM, GetDriveType;

        return GetDriveType(toUTF16z(driveLetter.to!string ~ `:\`)) == DRIVE_CDROM;
    }

    // Select the first optical drive in alphabetical order.
    GetDriveResult getDefaultDrive()
    {
        import std.algorithm : find;
        import std.ascii : uppercase;
        import std.utf : byChar;

        auto driveLetters = uppercase.byChar.find!isCDDrive;
        if (driveLetters.empty)
        {
            return GetDriveResult.err("Not found");
        }
        else
        {
            import std.conv : to;

            return GetDriveResult.ok(driveLetters.front.to!string);
        }
    }

    Result!(HANDLE, DWORD) createDriveHandle(string driveLetter)
    in (isValidDriveLetter(driveLetter))
    {
        import std.utf : toUTF16z;

        immutable drivePath = `\\.\` ~ driveLetter ~ ":";

        auto handle = CreateFile(drivePath.toUTF16z, GENERIC_READ | GENERIC_WRITE,
                FILE_SHARE_READ | FILE_SHARE_WRITE, null, OPEN_EXISTING, 0, null);

        if (handle == INVALID_HANDLE_VALUE)
        {
            import result : inspectErr;

            return Result!(HANDLE, DWORD).err(GetLastError())
                .inspectErr!(e => logError("open failed, " ~ drivePath, e));
        }

        return Result!(HANDLE, DWORD).ok(handle);
    }

    IoctlResult getConfiguration(string driveLetter, ref RemovableMediumFeatureResponse response)
    in (isValidDriveLetter(driveLetter))
    {
        GET_CONFIGURATION_IOCTL_INPUT ioctlInput = {
            Feature: FEATURE_NUMBER.FeatureRemovableMedium, RequestType: SCSI_GET_CONFIGURATION_REQUEST_TYPE_ONE
        };

        return ioctlWrapper(driveLetter, IOCTL_CDROM_GET_CONFIGURATION, &ioctlInput, &response);
    }
}

version (Windows) package
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

        return getDriveResult.mapErr!(_ => "No optical drive [A-Z] found")
            .inspect!(t => logGeneric("Target drive: <" ~ t ~ ">"))
            .inspectErr!(e => logGeneric(e));
    }

    GetStatusResult statusImpl(string driveLetter)
    in (isValidDriveLetter(driveLetter))
    {
        enum ioctlIOSize = USHORT(SCSI_PASS_THROUGH_DIRECT.sizeof);

        auto mechanismStatusHeader = MechanismStatusHeader();
        SCSI_PASS_THROUGH_DIRECT ioctlIO = {
            Length: ioctlIOSize, // PathId, TargetId and Lun are "don't-care" params:
                // https://msdn.microsoft.com/en-us/library/windows/hardware/ff560521%28v=vs.85%29.aspx
            CdbLength: MechanismStatusCDB.sizeof, DataIn: SCSI_IOCTL_DATA_IN, DataTransferLength: MechanismStatusHeader
                .sizeof, TimeOutValue: 5, DataBuffer: &mechanismStatusHeader
        };

        import core.lifetime : emplace;

        emplace!MechanismStatusCDB(ioctlIO.Cdb[], mechanismStatusCDB);

        import result : mapErr, andThen;
        import std.conv : to;
        import std.format : format;

        return ioctlWrapper(driveLetter, IOCTL_SCSI_PASS_THROUGH_DIRECT, &ioctlIO, &ioctlIO).mapErr!(
                e => e.to!string) // FIXME: Good format
        .andThen!(_ => ioctlIO.ScsiStatus == 0
                    ? GetStatusResult.ok(parseStatus(mechanismStatusHeader)) : GetStatusResult.err(
                        format("Failed to get tray status from Mechanism Status Header. ScsiStatus: %s",
                        ioctlIO.ScsiStatus)));
    }

    auto ejectableImpl(string driveLetter)
    in (isValidDriveLetter(driveLetter))
    {
        return ejectableClosableCommon!getConfiguration(driveLetter, OpenCloseMode.open);
    }

    auto closableImpl(string driveLetter)
    in (isValidDriveLetter(driveLetter))
    {
        return ejectableClosableCommon!getConfiguration(driveLetter, OpenCloseMode.close);
    }

    auto openImpl(string driveLetter)
    in (isValidDriveLetter(driveLetter))
    {
        import result : isOk;

        return ioctlWrapper(driveLetter, IOCTL_STORAGE_EJECT_MEDIA).isOk;
    }

    auto closeImpl(string driveLetter)
    in (isValidDriveLetter(driveLetter))
    {
        import result : isOk;

        return ioctlWrapper(driveLetter, IOCTL_STORAGE_LOAD_MEDIA).isOk;
    }
}
