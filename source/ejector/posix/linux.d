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
        auto statusImpl(string drive)
        {
            int sta = -1;
            immutable r = ioctlWrapper(drive, CDROM_DRIVE_STATUS, sta);
            if (r.ok && sta != CDS_NO_INFO)
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
            return ejectableClosableImpl!(OpenCloseMode.open)(drive);
        }

        auto closableImpl(string drive)
        {
            return ejectableClosableImpl!(OpenCloseMode.close)(drive);
        }

        private auto getConfiguration(string drive, ref RemovableMediumFeatureDescriptor buf)
        {
            sg_io_hdr hdr = {
                interface_id: SG_INTERFACE_ID_ORIG,
                dxfer_direction: SG_DXFER_FROM_DEV,
                cmd_len: GET_CONFIGURATION_CMD_LEN,
                dxfer_len: GET_CONFIGURATION_RESPONSE_BUF_LEN,
                dxferp: &buf,
                cmdp: cast(ubyte*) get_configuration_cmd.ptr,
                sbp: null,
                timeout: 5000
            };

            int sta;
            return ioctlWrapper(drive, SG_IO, sta, &hdr);
        }

        private auto ejectableClosableImpl(OpenCloseMode mode)(string drive)
        {
            return ejectableClosableCommon!(getConfiguration, mode)(drive);
        }

        auto openImpl(string drive)
        {
            return ioctlWrapper(drive, CDROMEJECT).ok;
        }

        auto closeImpl(string drive)
        {
            return ioctlWrapper(drive, CDROMCLOSETRAY).ok;
        }
    }
}
