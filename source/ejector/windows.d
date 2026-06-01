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

    void logError(T...)(string message, uint errorNumber, T additionalMessages)
    {
        debug (VerboseEjector)
        {
            import std.conv : text;
            import std.string : chomp;

            char[512] buffer;
            FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, null, errorNumber,
                MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
                buffer.ptr, buffer.length, null);

            logGeneric(message ~ ": " ~ buffer.ptr.text.chomp, additionalMessages);
        }
    }

    // Select the first optical drive in alphabetical order.
    @property auto defaultDrive()
    {
        import std.algorithm : find, map;
        import std.ascii : uppercase;
        import std.utf : toUTF16z;
        import core.sys.windows.winbase : DRIVE_CDROM, GetDriveType;

        auto driveLetters = uppercase.map!(a => (cast(char) a))
            .find!(a => GetDriveType(toUTF16z(a ~ `:\`)) == DRIVE_CDROM);
        if (driveLetters.empty)
        {
            return "";
        }
        else
        {
            import std.conv : text;

            return driveLetters.front.text;
        }
    }

    auto createDriveHandle(string driveLetter)
    {
        import std.utf : toUTF16z;

        immutable drivePath = `\\.\` ~
            (driveLetter == "" ? defaultDrive : driveLetter) ~ ":";

        auto handle = CreateFile(drivePath.toUTF16z, GENERIC_READ | GENERIC_WRITE,
            FILE_SHARE_READ | FILE_SHARE_WRITE, null, OPEN_EXISTING, 0, null);

        immutable errorNumber = GetLastError;
        logError(`CreateFile("` ~ drivePath ~ `") ` ~
                (errorNumber == 0 ? "succeeded" : "failed"), errorNumber);

        return handle;
    }

    auto ejectableClosableImpl(OpenCloseMode mode)(string driveLetter)
    {
        auto handle = createDriveHandle(driveLetter);
        scope (exit)
            handle != INVALID_HANDLE_VALUE && CloseHandle(handle);

        if (handle == INVALID_HANDLE_VALUE)
        {
            return false;
        }

        enum ioctlInputSize = DWORD(GET_CONFIGURATION_IOCTL_INPUT.sizeof);
        GET_CONFIGURATION_IOCTL_INPUT ioctlInput = {
            Feature: FEATURE_NUMBER.FeatureRemovableMedium,
            RequestType: SCSI_GET_CONFIGURATION_REQUEST_TYPE_ONE
        };

        // Same as GET_CONFIGURATION_HEADER + FEATURE_DATA_REMOVABLE_MEDIUM
        enum responseSize = DWORD(RemovableMediumFeatureResponse.sizeof);
        auto response = RemovableMediumFeatureResponse();

        DWORD bytesReturned;
        immutable status = DeviceIoControl(handle, IOCTL_CDROM_GET_CONFIGURATION,
            &ioctlInput, ioctlInputSize, &response, responseSize, &bytesReturned, null);
        immutable errorNumber = GetLastError;
        logError("DeviceIoControl() " ~
                (errorNumber == 0 ? "succeeded" : "failed"), errorNumber);

        if (!status)
        {
            // If DeviceIoControl fails, we might have to execute MODE SENSE (10)
            return false;
        }

        debug (VerboseEjector)
        {
            import std.stdio : stderr, writeln;

            stderr.writeln(response);
        }

        return parseEjectableClosable!mode(response);
    }

    auto openCloseImpl(OpenCloseMode mode)(string driveLetter)
    {
        auto handle = createDriveHandle(driveLetter);
        scope (exit)
            handle != INVALID_HANDLE_VALUE && CloseHandle(handle);

        if (handle == INVALID_HANDLE_VALUE)
        {
            return false;
        }

        DWORD bytesReturned;
        enum command = mode == OpenCloseMode.open ?
    IOCTL_STORAGE_EJECT_MEDIA : IOCTL_STORAGE_LOAD_MEDIA;
        immutable status = DeviceIoControl(handle, command, null, 0, null, 0, &bytesReturned, null);
        immutable errorNumber = GetLastError;

        logError("DeviceIoControl() " ~
                (errorNumber == 0 ? "succeeded" : "failed"), errorNumber);

        return !!status;
    }
}

version (Windows) package
{
    auto statusImpl(string driveLetter)
    {
        auto handle = createDriveHandle(driveLetter);
        scope (exit)
            handle != INVALID_HANDLE_VALUE && CloseHandle(handle);

        if (handle == INVALID_HANDLE_VALUE)
        {
            return TrayStatus.ERROR;
        }

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

        DWORD bytesReturned;
        immutable status = DeviceIoControl(handle, IOCTL_SCSI_PASS_THROUGH_DIRECT,
            &ioctlIO, ioctlIOSize, &ioctlIO, ioctlIOSize, &bytesReturned, null);

        immutable errorNumber = GetLastError;
        logError("DeviceIoControl() " ~
                (errorNumber == 0 ? "succeeded" : "failed"), errorNumber);

        debug (VerboseEjector)
        {
            import std.stdio : stderr, writeln;

            stderr.writeln(mechanismStatusHeader);
        }

        if (!status || ioctlIO.ScsiStatus != 0)
        {
            return TrayStatus.ERROR;
        }
        else
        {
            return parseStatus(mechanismStatusHeader);
        }
    }

    auto ejectableImpl(string driveLetter)
    {
        return ejectableClosableImpl!(OpenCloseMode.open)(driveLetter);
    }

    auto closableImpl(string driveLetter)
    {
        return ejectableClosableImpl!(OpenCloseMode.close)(driveLetter);
    }

    auto openImpl(string driveLetter)
    {
        return openCloseImpl!(OpenCloseMode.open)(driveLetter);
    }

    auto closeImpl(string driveLetter)
    {
        return openCloseImpl!(OpenCloseMode.close)(driveLetter);
    }
}
