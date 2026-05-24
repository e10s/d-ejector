/*
Copyright electrolysis 2015.
Distributed under the Boost Software License, Version 1.0.
(See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
*/

module ejector.linux;

version (linux)
{
    package mixin template LinuxImpl()
    {
        enum Command
        {
            // scsi/sg.h
            SG_IO = .SG_IO,

            // linux/cdrom.h
            CDROMEJECT = .CDROMEJECT,
            CDROMCLOSETRAY = .CDROMCLOSETRAY,
            CDROM_DRIVE_STATUS = .CDROM_DRIVE_STATUS,
            CDROM_GET_CAPABILITY = .CDROM_GET_CAPABILITY, // Other members might be added
        }

        // linux/cdrom.h
        enum Capability
        {
            CDC_CLOSE_TRAY = .CDC_CLOSE_TRAY,
            CDC_OPEN_TRAY = .CDC_OPEN_TRAY
        }

        auto statusImpl(string drive)
        {
            int sta = -1;
            immutable r = send(drive, Command.CDROM_DRIVE_STATUS, sta);
            if (r && sta != CDS_NO_INFO)
            {
                return sta == CDS_TRAY_OPEN ?
                    TrayStatus.OPEN : TrayStatus.CLOSED;
            }
            else
            {
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

            sg_io_hdr hdr = {
                interface_id: SG_INTERFACE_ID_ORIG,
                dxfer_direction: SG_DXFER_FROM_DEV,
                cmd_len: GET_CONFIGURATION_CMD_LEN,
                dxfer_len: GET_CONFIGURATION_RESPONSE_BUF_LEN,
                dxferp: buf.ptr,
                cmdp: cast(ubyte*) get_configuration_cmd.ptr,
                sbp: null,
                timeout: 5000
            };

            int sta;
            immutable r = send(drive, Command.SG_IO, sta, &hdr);

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
            return send(drive, Command.CDROMEJECT);
        }

        auto closedImpl(string drive)
        {
            return send(drive, Command.CDROMCLOSETRAY);
        }
    }
}
