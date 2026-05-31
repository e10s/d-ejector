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

        private auto camCommander(CDB, Response)(string drive, CDB cmd, ref Response buf)
        {
            import core.stdc.errno : errno;
            import core.sys.posix.fcntl : O_RDWR;
            import std.string : toStringz;

            cam_errbuf[] = 0;
            auto cam_dev = cam_open_device(drive.toStringz, O_RDWR);
            if (!cam_dev)
            {
                import std.stdio : stderr, writeln;

                immutable err = errno;

                stderr.writeln(cast(string) cam_errbuf);
                return IoctlResult(false, IoctlErrorStage.open, err);
            }

            ubyte[CCB_SIZE] ccbLike; // substitute for union ccb
            csio_build(cast(ccb_scsiio*) ccbLike.ptr, cast(ubyte*)&buf,
                uint(Response.sizeof), ccb_flags.CAM_DIR_IN,
                1, 5000, "".toStringz);
            ccbLike[CCB_CDB_LEN_OFFSET] = ubyte(CDB.sizeof);
            import core.lifetime : emplace;

            emplace!CDB(ccbLike[CCB_CDB_BYTES_OFFSET .. CCB_CDB_BYTES_OFFSET + CDB.sizeof], cmd);

            cam_errbuf[] = 0;
            immutable csc = cam_send_ccb(cam_dev, cast(ccb*) ccbLike.ptr);
            if (csc == -1)
            {
                import std.stdio : stderr, writeln;

                immutable err = errno;

                stderr.writeln(cast(string) cam_errbuf);
                cam_close_device(cam_dev);
                return IoctlResult(false, IoctlErrorStage.ioctl, err);
            }

            cam_close_device(cam_dev);

            return IoctlResult(true, IoctlErrorStage.none, 0);
        }

        auto statusImpl(string drive)
        {
            auto mechanismStatusHeader = MechanismStatusHeader();
            immutable r = camCommander(drive, msCDB, mechanismStatusHeader);

            if (r.ok)
            {
                debug (VerboseEjector)
                {
                    import std.stdio : stderr, writeln;

                    stderr.writeln("status succeeded");
                }
                return parseStatus(mechanismStatusHeader);
            }
            else
            {
                debug (VerboseEjector)
                {
                    import std.stdio : stderr, writeln;

                    stderr.writeln("status failed");
                }
                return TrayStatus.ERROR;
            }
        }

        auto ejectableImpl(string drive)
        {
            return ejectableClosableImpl!(OpenCloseMode.open)(drive);
        }

        auto closableImpl(string drive)
        {
            return ejectableClosableImpl!(OpenCloseMode.close)(drive);
        }

        private auto getConfiguration(string drive, ref RemovableMediumFeatureResponse buf)
        {
            return camCommander(drive, getConfigurationCDB, buf);
        }

        private auto ejectableClosableImpl(OpenCloseMode mode)(string drive)
        {
            return ejectableClosableCommon!(getConfiguration, mode)(drive);
        }

        auto openImpl(string drive)
        {
            return ioctlWrapper(drive, Command.CDIOCEJECT).ok;
        }

        auto closeImpl(string drive)
        {
            return ioctlWrapper(drive, Command.CDIOCCLOSE).ok;
        }
    }
}
