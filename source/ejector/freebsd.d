/*
Copyright electrolysis 2015.
Distributed under the Boost Software License, Version 1.0.
(See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
*/

module ejector.freebsd;

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
        mixin(import("ccb.mixin"));

        // cam/cam_ccb.h
        // https://github.com/freebsd/freebsd/blob/master/sys/cam/cam_ccb.h
        enum ccb_flags
        {
            CAM_DIR_IN = 0x00000040
        }

        union ccb;
        struct ccb_scsiio;

        extern (C) int csio_build(ccb_scsiio*, ubyte*, uint, uint, int, int,
            const(char)*, ...);

        // camlib.h
        // https://github.com/freebsd/freebsd/blob/master/lib/libcam/camlib.h
        enum CAM_ERRBUF_SIZE = 2048;
        struct cam_device;

        extern (C) __gshared ubyte[CAM_ERRBUF_SIZE] cam_errbuf;
        extern (C) cam_device* cam_open_device(const(char)*, int);
        extern (C) void cam_close_device(cam_device*);
        extern (C) int cam_send_ccb(cam_device*, ccb*);

        // sys/ioccom.h
        // https://github.com/freebsd/freebsd/blob/master/sys/sys/ioccom.h
        enum IOCPARM_SHIFT = 13;
        enum IOCPARM_MASK = (1 << IOCPARM_SHIFT) - 1;
        enum IOC_VOID = 0x20000000;
        enum _IOC(uint inout_, uint group, uint num, uint len) =
            uint(inout_ | ((len & IOCPARM_MASK) << 16) | (group << 8) | num);
        enum _IO(uint g, uint n) = _IOC!(IOC_VOID, g, n, 0);

        // sys/cdio.h
        // https://github.com/freebsd/freebsd/blob/master/sys/sys/cdio.h
        enum Command
        {
            CDIOCEJECT = _IO!('c', 24),
            CDIOCCLOSE = _IO!('c', 28),
        }

        // sys/cdio.h
        enum Capability
        {
            CDDOEJECT = 0x1,
            CDDOCLOSE = 0x2
        }

        auto camCommander(string drive, in ubyte[] cmd, ref ubyte[] buf)
        {
            import core.sys.posix.fcntl : O_RDWR;
            import std.string : toStringz;

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

        auto ejectableClosableImpl(Mode mode)(string drive)
        {
            enum GET_CONFIGURATION_CMD_LEN = 12;
            enum GET_CONFIGURATION_RESPONSE_BUF_LEN = 16;

            auto buf = new ubyte[GET_CONFIGURATION_RESPONSE_BUF_LEN];
            static immutable ubyte[GET_CONFIGURATION_CMD_LEN] get_configuration_cmd =
                [0x46, 0x02, 0, 0x03, 0, 0, 0,
                    0, GET_CONFIGURATION_RESPONSE_BUF_LEN, 0, 0, 0];

            immutable r = camCommander(drive, get_configuration_cmd[], buf);

            debug (VerboseEjector)
            {
                if (r)
                {
                    import std.stdio : stderr, writeln;

                    stderr.writeln(mode, " succeeded");
                }
                else
                {
                    import std.stdio : stderr, writeln;
                    import std.conv : text;

                    stderr.writeln(mode, " failed");
                }
            }

            if (!r)
            {
                // We might have to execute MODE SENSE (10)
                return false;
            }

            // ftp://ftp.seagate.com/sff/INF-8090.PDF, p.638
            // Test the Eject bit
            static if (mode == Mode.open)
            {
                immutable eject = buf[12] & 0b00001000;
                return !!eject;
            }
            else
            {
                // Test the Version field and the Load bit
                immutable version_ = (buf[10] >> 2) & 0b00001111;
                if (version_ > 0)
                {
                    immutable load = buf[12] & 0b00010000;
                    return !!load;
                }
                // [[ Doubtful ]]
                // Guess from the Loading Mechanism Type field
                // Drives other than ones with caddy/slot type loading mechanism will be closable(?)
                // https://github.com/torvalds/linux/blob/master/drivers/scsi/sr.c
            else
                {
                    // The Loading Mechanism Type field
                    immutable mech = buf[12] >> 5;
                    // Maybe closable
                    return mech != 0;
                }
            }
        }

        auto openImpl(string drive)
        {
            return send(drive, Command.CDIOCEJECT);
        }

        auto closedImpl(string drive)
        {
            return send(drive, Command.CDIOCCLOSE);
        }
    }
}
