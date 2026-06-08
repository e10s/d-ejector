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
        package immutable cdDrivePrefix = "sr";

        auto statusImpl(string drivePathName)
        in (drivePathName.length > 0)
        {
            int status = -1;
            immutable ioctlResult = ioctlWrapper(drivePathName, CDROM_DRIVE_STATUS, status);
            if (ioctlResult.ok && status != CDS_NO_INFO)
            {
                return status == CDS_TRAY_OPEN ?
                    TrayStatus.OPEN : TrayStatus.CLOSED;
            }
            else
            {
                return TrayStatus.ERROR;
            }
        }

        auto ejectableImpl(string drivePathName)
        in (drivePathName.length > 0)
        {
            return ejectableClosableCommon!getConfiguration(drivePathName, OpenCloseMode.open);
        }

        auto closableImpl(string drivePathName)
        in (drivePathName.length > 0)
        {
            return ejectableClosableCommon!getConfiguration(drivePathName, OpenCloseMode.close);
        }

        private auto getConfiguration(string drivePathName, ref RemovableMediumFeatureResponse response)
        in (drivePathName.length > 0)
        {
            sg_io_hdr header = {
                interface_id: SG_INTERFACE_ID_ORIG,
                dxfer_direction: SG_DXFER_FROM_DEV,
                cmd_len: GetConfigurationCDB.sizeof,
                dxfer_len: RemovableMediumFeatureResponse.sizeof,
                dxferp: &response,
                cmdp: cast(ubyte*)&getConfigurationCDB,
                sbp: null,
                timeout: 5000
            };

            int status;
            return ioctlWrapper(drivePathName, SG_IO, status, &header);
        }

        auto openImpl(string drivePathName)
        in (drivePathName.length > 0)
        {
            return ioctlWrapper(drivePathName, CDROMEJECT).ok;
        }

        auto closeImpl(string drivePathName)
        in (drivePathName.length > 0)
        {
            return ioctlWrapper(drivePathName, CDROMCLOSETRAY).ok;
        }
    }
}
