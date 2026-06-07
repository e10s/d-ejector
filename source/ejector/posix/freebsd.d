/*
Copyright electrolysis 2015.
Distributed under the Boost Software License, Version 1.0.
(See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
*/

module ejector.posix.freebsd;

import ejector.base;

version (FreeBSD)
{
    pragma(lib, "cam");
    package mixin template FreeBSDImpl()
    {

        /*
        Generated from ccb.c

        enum CCB_SIZE = ??;
        enum CCB_CDB_LEN_OFFSET = ??;
        enum CCB_CDB_BYTES_OFFSET = ??;
        */
        private mixin(import("ccb.mixin"));

        // cam/cam_ccb.h
        // https://github.com/freebsd/freebsd/blob/master/sys/cam/cam_ccb.h
        private enum ccb_flags
        {
            CAM_DIR_IN = 0x00000040
        }

        private union ccb;
        private struct ccb_scsiio;

        private extern (C) int csio_build(ccb_scsiio*, ubyte*, uint, uint, int, int,
            const(char)*, ...);

        // camlib.h
        // https://github.com/freebsd/freebsd/blob/master/lib/libcam/camlib.h
        private enum CAM_ERRBUF_SIZE = 2048;
        private struct cam_device;

        private extern (C) __gshared ubyte[CAM_ERRBUF_SIZE] cam_errbuf;
        private extern (C) cam_device* cam_open_device(const(char)*, int);
        private extern (C) void cam_close_device(cam_device*);
        private extern (C) int cam_send_ccb(cam_device*, ccb*);

        // sys/ioccom.h
        // https://github.com/freebsd/freebsd/blob/master/sys/sys/ioccom.h
        private enum IOCPARM_SHIFT = 13;
        private enum IOCPARM_MASK = (1 << IOCPARM_SHIFT) - 1;
        private enum IOC_VOID = 0x20000000;
        private enum _IOC(uint inout_, uint group, uint num, uint len) =
            uint(inout_ | ((len & IOCPARM_MASK) << 16) | (group << 8) | num);
        private enum _IO(uint g, uint n) = _IOC!(IOC_VOID, g, n, 0);

        // sys/cdio.h
        // https://github.com/freebsd/freebsd/blob/master/sys/sys/cdio.h
        private enum Command
        {
            CDIOCEJECT = _IO!('c', 24),
            CDIOCCLOSE = _IO!('c', 28),
        }

        private auto camCommander(CDB, Response)(string drivePathName, CDB cdb, ref Response response)
        {
            import core.stdc.errno : errno;
            import core.sys.posix.fcntl : O_RDWR;
            import std.string : toStringz;

            cam_errbuf[] = 0;
            auto camDevice = cam_open_device(drivePathName.toStringz, O_RDWR);
            scope (exit)
                camDevice && cam_close_device(camDevice);

            if (!camDevice)
            {
                logGeneric("cam_open_device failed, " ~ drivePathName, cast(string) cam_errbuf);
                return IoctlResult(false, IoctlErrorStage.open, 0);
            }

            ubyte[CCB_SIZE] ccbLike; // substitute for union ccb
            csio_build(cast(ccb_scsiio*) ccbLike.ptr, cast(ubyte*)&response,
                uint(Response.sizeof), ccb_flags.CAM_DIR_IN,
                1, 5000, "".toStringz);
            ccbLike[CCB_CDB_LEN_OFFSET] = ubyte(CDB.sizeof);
            import core.lifetime : emplace;

            emplace!CDB(ccbLike[CCB_CDB_BYTES_OFFSET .. CCB_CDB_BYTES_OFFSET + CDB.sizeof], cdb);

            cam_errbuf[] = 0;
            immutable status = cam_send_ccb(camDevice, cast(ccb*) ccbLike.ptr);
            if (status == -1)
            {
                immutable errorNumber = errno;
                logError("cam_send_ccb failed, " ~ drivePathName, errorNumber, cast(string) cam_errbuf);
                return IoctlResult(false, IoctlErrorStage.ioctl, errorNumber);
            }

            logGeneric("cam_send_ccb succeeded, " ~ drivePathName);

            return IoctlResult(true, IoctlErrorStage.none, 0);
        }

        package immutable cdDrivePrefix = "cd";

        auto statusImpl(string drivePathName)
        {
            auto mechanismStatusHeader = MechanismStatusHeader();
            immutable ioctlResult = camCommander(drivePathName, mechanismStatusCDB, mechanismStatusHeader);

            if (ioctlResult.ok)
            {
                return parseStatus(mechanismStatusHeader);
            }
            else
            {
                return TrayStatus.ERROR;
            }
        }

        auto ejectableImpl(string drivePathName)
        {
            return ejectableClosableCommon!getConfiguration(drivePathName, OpenCloseMode.open);
        }

        auto closableImpl(string drivePathName)
        {
            return ejectableClosableCommon!getConfiguration(drivePathName, OpenCloseMode.close);
        }

        private auto getConfiguration(string drivePathName, ref RemovableMediumFeatureResponse response)
        {
            return camCommander(drivePathName, getConfigurationCDB, response);
        }

        auto openImpl(string drivePathName)
        {
            return ioctlWrapper(drivePathName, Command.CDIOCEJECT).ok;
        }

        auto closeImpl(string drivePathName)
        {
            return ioctlWrapper(drivePathName, Command.CDIOCCLOSE).ok;
        }
    }
}
