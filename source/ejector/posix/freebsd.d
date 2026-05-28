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

        private auto camCommander(string drive, in ubyte[] cmd, ref ubyte[] buf)
        {
            import core.sys.posix.fcntl : O_RDWR;
            import std.string : toStringz;

            cam_errbuf[] = 0;
            auto cam_dev = cam_open_device(drive.toStringz, O_RDWR);
            if (!cam_dev)
            {
                import std.stdio : stderr, writeln;

                stderr.writeln(cast(string) cam_errbuf);
                return false;
            }

            ubyte[CCB_SIZE] ccbLike; // substitute for union ccb
            csio_build(cast(ccb_scsiio*) ccbLike.ptr, buf.ptr,
                cast(uint) buf.length, ccb_flags.CAM_DIR_IN,
                1, 5000, "".toStringz);
            ccbLike[CCB_CDB_LEN_OFFSET] = cast(ubyte) cmd.length;
            ccbLike[CCB_CDB_BYTES_OFFSET .. CCB_CDB_BYTES_OFFSET + cmd.length] =
                cmd[];

            cam_errbuf[] = 0;
            immutable csc = cam_send_ccb(cam_dev, cast(ccb*) ccbLike.ptr);
            if (csc == -1)
            {
                import std.stdio : stderr, writeln;

                stderr.writeln(cast(string) cam_errbuf);
                cam_close_device(cam_dev);
                return false;
            }

            cam_close_device(cam_dev);

            return true;
        }

        auto statusImpl(string drive)
        {
            enum MECHANISM_STATUS_CMD_LEN = 12;
            enum MECHANISM_STATUS_RESPONSE_BUF_LEN = 8;

            auto buf = new ubyte[MECHANISM_STATUS_RESPONSE_BUF_LEN];
            static immutable ubyte[MECHANISM_STATUS_CMD_LEN] mechanism_status_cmd =
                [0xBD, 0, 0, 0, 0, 0, 0, 0,
                    0, MECHANISM_STATUS_RESPONSE_BUF_LEN, 0, 0];

            immutable r = camCommander(drive, mechanism_status_cmd[], buf);

            if (r)
            {
                debug (VerboseEjector)
                {
                    import std.stdio : stderr, writeln;

                    stderr.writeln("status succeeded");
                }
                return buf[1] & 0b00010000 ?
                    TrayStatus.OPEN : TrayStatus.CLOSED;
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
            return ejectableClosableImpl!(Mode.open)(drive);
        }

        auto closableImpl(string drive)
        {
            return ejectableClosableImpl!(Mode.close)(drive);
        }

        private auto getConfiguration(string drive, ref ubyte[] buf)
        {
            return camCommander(drive, get_configuration_cmd[], buf);
        }

        private auto ejectableClosableImpl(Mode mode)(string drive)
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
