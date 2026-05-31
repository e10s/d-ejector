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

    // scsi.h
    enum SCSIOP_MECHANISM_STATUS = UCHAR(0xBD);
    enum CDB12GENERIC_LENGTH = 12;

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

    // Select the first optical drive in alphabetical order.
    @property auto defaultDrive()
    {
        import std.algorithm : find, map;
        import std.ascii : uppercase;
        import std.utf : toUTF16z;
        import core.sys.windows.winbase : DRIVE_CDROM, GetDriveType;

        auto drives = uppercase.map!(a => (cast(char) a))
            .find!(a => GetDriveType(toUTF16z(a ~ `:\`)) == DRIVE_CDROM);
        if (drives.empty)
        {
            return "";
        }
        else
        {
            import std.conv : text;

            return drives.front.text;
        }
    }

    auto createDriveHandle(string driveLetter)
    {
        import std.utf : toUTF16z;

        immutable drivePath = `\\.\` ~
            (driveLetter == "" ? defaultDrive : driveLetter) ~ ":";

        auto h = CreateFile(drivePath.toUTF16z, GENERIC_READ | GENERIC_WRITE,
            FILE_SHARE_READ | FILE_SHARE_WRITE, null, OPEN_EXISTING, 0, null);

        immutable err = GetLastError;
        logError(`CreateFile("` ~ drivePath ~ `") ` ~
                (err == 0 ? "succeeded" : "failed"), err);

        return h;
    }

    auto ejectableClosableImpl(OpenCloseMode mode)(string driveLetter)
    {
        auto h = createDriveHandle(driveLetter);
        scope (exit)
            h != INVALID_HANDLE_VALUE && CloseHandle(h);

        if (h == INVALID_HANDLE_VALUE)
        {
            return false;
        }

        enum gciiSize = DWORD(GET_CONFIGURATION_IOCTL_INPUT.sizeof);
        GET_CONFIGURATION_IOCTL_INPUT gcii = {
            Feature: FEATURE_NUMBER.FeatureRemovableMedium,
            RequestType: SCSI_GET_CONFIGURATION_REQUEST_TYPE_ONE
        };

        // Same as GET_CONFIGURATION_HEADER + FEATURE_DATA_REMOVABLE_MEDIUM
        enum responseSize = DWORD(RemovableMediumFeatureResponse.sizeof);
        auto response = RemovableMediumFeatureResponse();

        DWORD ret;
        immutable dic = DeviceIoControl(h, IOCTL_CDROM_GET_CONFIGURATION,
            &gcii, gciiSize, &response, responseSize, &ret, null);
        immutable err = GetLastError;
        logError("DeviceIoControl() " ~
                (err == 0 ? "succeeded" : "failed"), err);

        if (!dic)
        {
            // If dic fails, we might have to execute MODE SENSE (10)
            return false;
        }

        debug (VerboseEjector)
        {
            import std.stdio : stderr, writeln;

            stderr.writeln(response);
        }

        static if (mode == OpenCloseMode.open)
        {
            // ftp://ftp.seagate.com/sff/INF-8090.PDF, p.638
            // Test the Eject bit
            return !!response.eject;
        }
        else
        {
            // Test the Version field and the Load bit
            if (response.version_ > 0)
            {
                return !!response.load;
            }
            // [[ Doubtful ]]
            // Drives other than ones with caddy/slot type loading mechanism will be closable(?)
            // https://github.com/torvalds/linux/blob/master/drivers/scsi/sr.c
        else
            {
                // Maybe closable
                return response.loadingMechanismType != 0;
            }
        }
    }

    auto openCloseImpl(OpenCloseMode mode)(string driveLetter)
    {
        auto h = createDriveHandle(driveLetter);
        scope (exit)
            h != INVALID_HANDLE_VALUE && CloseHandle(h);

        if (h == INVALID_HANDLE_VALUE)
        {
            return false;
        }

        DWORD ret;
        enum cmd = mode == OpenCloseMode.open ?
    IOCTL_STORAGE_EJECT_MEDIA : IOCTL_STORAGE_LOAD_MEDIA;
        immutable dic = DeviceIoControl(h, cmd, null, 0, null, 0, &ret, null);
        immutable err = GetLastError;

        logError("DeviceIoControl() " ~
                (err == 0 ? "succeeded" : "failed"), err);

        return !!dic;
    }
}

version (Windows) package
{
    void logError(string msg, uint errNo)
    {
        debug (VerboseEjector)
        {
            import std.conv : text;
            import std.stdio : stderr, writeln;

            char[512] buf;
            FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM, null, errNo,
                MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
                buf.ptr, buf.length, null);
            stderr.writeln(msg, ": ", buf.ptr.text);
        }
    }

    auto statusImpl(string driveLetter)
    {
        import ejector.base;

        auto h = createDriveHandle(driveLetter);
        scope (exit)
            h != INVALID_HANDLE_VALUE && CloseHandle(h);

        if (h == INVALID_HANDLE_VALUE)
        {
            return TrayStatus.ERROR;
        }

        enum sptdSize = USHORT(SCSI_PASS_THROUGH_DIRECT.sizeof);
        enum padding = ubyte(255);
        ubyte[8] buf = padding; // Mechanism Status Header has 8 bytes

        SCSI_PASS_THROUGH_DIRECT sptd = {
            Length: sptdSize, // PathId, TargetId and Lun are "don't-care" params:
                // https://msdn.microsoft.com/en-us/library/windows/hardware/ff560521%28v=vs.85%29.aspx
            CdbLength: 12,
            DataIn: SCSI_IOCTL_DATA_IN,
            DataTransferLength: buf.length,
            TimeOutValue: 5,
            DataBuffer: buf.ptr
        };
        sptd.Cdb[0] = SCSIOP_MECHANISM_STATUS;
        sptd.Cdb[9] = buf.length;

        DWORD ret;
        immutable dic = DeviceIoControl(h, IOCTL_SCSI_PASS_THROUGH_DIRECT,
            &sptd, sptdSize, &sptd, sptdSize, &ret, null);

        immutable err = GetLastError;
        logError("DeviceIoControl() " ~
                (err == 0 ? "succeeded" : "failed"), err);

        debug (VerboseEjector)
        {
            import std.stdio : stderr, writeln;

            stderr.writeln(buf);
        }

        if (!dic || sptd.ScsiStatus != 0 || buf[1] == padding)
        {
            return TrayStatus.ERROR;
        }
        else
        {
            // ftp://ftp.seagate.com/sff/INF-8090.PDF, p.742
            return (buf[1] & 0b00010000) ? TrayStatus.OPEN : TrayStatus.CLOSED;
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
