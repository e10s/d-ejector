/*
Copyright electrolysis 2015.
Distributed under the Boost Software License, Version 1.0.
(See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
*/

module ejector.posix.linux;

version (linux) package(ejector.posix) mixin template LinuxImpl()
{
    package(ejector.posix)
    {
        immutable cdDrivePrefix = "sr";

        auto getConfiguration(string drivePathName, ref RemovableMediumFeatureResponse response)
        in (drivePathName.length > 0)
        {
            sg_io_hdr header = {
                interface_id: SG_INTERFACE_ID_ORIG, dxfer_direction: SG_DXFER_FROM_DEV, cmd_len: GetConfigurationCDB.sizeof, dxfer_len: RemovableMediumFeatureResponse.sizeof, dxferp: &response,
                cmdp: cast(ubyte*)&getConfigurationCDB, sbp: null, timeout: 5000
            };

            int status;
            return ioctlWrapper(drivePathName, SG_IO, status, &header);
        }
    }

    package(ejector)
    {
        GetStatusResult statusImpl(string drivePathName)
        in (drivePathName.length > 0)
        {
            import result : mapErr, andThen;
            import std.conv : to;

            int status = -1;
            return ioctlWrapper(drivePathName, CDROM_DRIVE_STATUS, status).mapErr!(
                    e => e.to!string) // FIXME: Good format
            .andThen!(t => t != CDS_NO_INFO ? GetStatusResult.ok(t == CDS_TRAY_OPEN ? TrayStatus.OPEN
                        : TrayStatus.CLOSED) : GetStatusResult.err(
                        "Failed to get tray status. CDS_NO_INFO is returned."));
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

        auto openImpl(string drivePathName)
        in (drivePathName.length > 0)
        {
            import result : isOk;

            return ioctlWrapper(drivePathName, CDROMEJECT).isOk;
        }

        auto closeImpl(string drivePathName)
        in (drivePathName.length > 0)
        {
            import result : isOk;

            return ioctlWrapper(drivePathName, CDROMCLOSETRAY).isOk;
        }
    }
}
