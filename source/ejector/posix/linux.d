/*
Copyright electrolysis 2015.
Distributed under the Boost Software License, Version 1.0.
(See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
*/

module ejector.posix.linux;

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

        auto getConfiguration(string drive, ref ubyte[] buf)
        {
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
            return send(drive, Command.SG_IO, sta, &hdr);
        }

        auto ejectableClosableImpl(Mode mode)(string drive)
        {
            return ejectableClosableCommon!(getConfiguration, mode)(drive);
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
