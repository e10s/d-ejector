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

    void logError(T...)(lazy string message, uint errorNumber, lazy T additionalMessages, string caller = __FUNCTION__)
    {
        debug (VerboseEjector)
        {
            import std.conv : text;
            import std.string : chomp;

            char[512] buffer;
            FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, null, errorNumber,
                MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
                buffer.ptr, buffer.length, null);

            logGeneric!T(message ~ ": " ~ buffer.ptr.text.chomp, additionalMessages, caller);
        }
    }

    IoctlResult ioctlWrapper(Command, IoctlInput = void, IoctlOutput = void)(string driveLetter, Command command,
        IoctlInput* ioctlInputPointer, IoctlOutput* ioctlOutputPointer)
    {
        auto handle = createDriveHandle(driveLetter);
        scope (exit)
            handle != INVALID_HANDLE_VALUE && CloseHandle(handle);

        if (handle == INVALID_HANDLE_VALUE)
        {
            immutable errorNumber = GetLastError;
            logError("open failed, " ~ driveLetter, errorNumber);
            return IoctlResult(false, IoctlErrorStage.open, errorNumber);
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
        immutable status = DeviceIoControl(handle, command,
            ioctlInputPointer, ioctlInputSize, ioctlOutputPointer, ioctlOutputSize, null, null);
        if (!status)
        {
            immutable errorNumber = GetLastError;
            logError("ioctl failed, " ~ driveLetter, errorNumber);
            return IoctlResult(false, IoctlErrorStage.ioctl, errorNumber);
        }

        logGeneric("ioctl succeeded, " ~ driveLetter);

        return IoctlResult(true, IoctlErrorStage.none, 0);
    }

    IoctlResult ioctlWrapper(Command)(string driveLetter, Command command)
    {
        return ioctlWrapper(driveLetter, command, null, null);
    }

    import std.traits : isSomeString, isSomeChar;

    auto isCDDrive(T)(T driveLetter)
    if (isSomeString!T || isSomeChar!T)
    {
        import std.conv : to;
        import std.utf : toUTF16z;
        import core.sys.windows.winbase : DRIVE_CDROM, GetDriveType;

        return GetDriveType(toUTF16z(driveLetter.to!string ~ `:\`)) == DRIVE_CDROM;
    }

    // Select the first optical drive in alphabetical order.
    @property auto defaultDrive()
    {
        import std.algorithm : find;
        import std.ascii : uppercase;
        import std.utf : byChar;

        auto driveLetters = uppercase.byChar.find!isCDDrive;
        if (driveLetters.empty)
        {
            return "";
        }
        else
        {
            import std.conv : to;

            return driveLetters.front.to!string;
        }
    }

    auto createDriveHandle(string driveLetter)
    {
        import std.utf : toUTF16z;

        immutable drivePath = `\\.\` ~
            (driveLetter == "" ? defaultDrive : driveLetter) ~ ":";

        auto handle = CreateFile(drivePath.toUTF16z, GENERIC_READ | GENERIC_WRITE,
            FILE_SHARE_READ | FILE_SHARE_WRITE, null, OPEN_EXISTING, 0, null);

        return handle;
    }

    auto getConfiguration(string driveLetter, ref RemovableMediumFeatureResponse response)
    {
        GET_CONFIGURATION_IOCTL_INPUT ioctlInput = {
            Feature: FEATURE_NUMBER.FeatureRemovableMedium,
            RequestType: SCSI_GET_CONFIGURATION_REQUEST_TYPE_ONE
        };

        return ioctlWrapper(driveLetter, IOCTL_CDROM_GET_CONFIGURATION, &ioctlInput, &response);
    }
}

version (Windows) package
{
    auto statusImpl(string driveLetter)
    {
        enum ioctlIOSize = USHORT(SCSI_PASS_THROUGH_DIRECT.sizeof);

        auto mechanismStatusHeader = MechanismStatusHeader();
        SCSI_PASS_THROUGH_DIRECT ioctlIO = {
            Length: ioctlIOSize, // PathId, TargetId and Lun are "don't-care" params:
                // https://msdn.microsoft.com/en-us/library/windows/hardware/ff560521%28v=vs.85%29.aspx
            CdbLength: MechanismStatusCDB.sizeof,
            DataIn: SCSI_IOCTL_DATA_IN,
            DataTransferLength: MechanismStatusHeader.sizeof,
            TimeOutValue: 5,
            DataBuffer: &mechanismStatusHeader
        };

        import core.lifetime : emplace;

        emplace!MechanismStatusCDB(ioctlIO.Cdb[], mechanismStatusCDB);

        immutable ioctlResult = ioctlWrapper(driveLetter, IOCTL_SCSI_PASS_THROUGH_DIRECT, &ioctlIO, &ioctlIO);

        if (ioctlResult.ok && ioctlIO.ScsiStatus == 0)
        {
            return parseStatus(mechanismStatusHeader);
        }
        else
        {
            return TrayStatus.ERROR;
        }
    }

    auto ejectableImpl(string driveLetter)
    {
        return ejectableClosableCommon!getConfiguration(driveLetter, OpenCloseMode.open);
    }

    auto closableImpl(string driveLetter)
    {
        return ejectableClosableCommon!getConfiguration(driveLetter, OpenCloseMode.close);
    }

    auto openImpl(string driveLetter)
    {
        return ioctlWrapper(driveLetter, IOCTL_STORAGE_EJECT_MEDIA).ok;
    }

    auto closeImpl(string driveLetter)
    {
        return ioctlWrapper(driveLetter, IOCTL_STORAGE_LOAD_MEDIA).ok;
    }
}
