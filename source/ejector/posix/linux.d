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
        @property auto defaultDrive()
        {
            import std.file : exists;
            import std.path : buildPath;

            immutable devPath = "/dev";
            immutable devCdromPath = buildPath(devPath, "cdrom");

            if (devCdromPath.exists)
            {
                return devCdromPath;
            }

            immutable cdDrivePrefix = "sr";

            import std.concurrency : Generator;

            auto r = new Generator!size_t({
                import std.file : FileException;

                immutable sysClassBlockPath = "/sys/class/block";

                try
                {
                    import std.file : dirEntries, SpanMode;

                    foreach (entry; dirEntries(sysClassBlockPath, SpanMode.shallow))
                    {
                        try
                        {
                            import std.algorithm : startsWith;
                            import std.path : baseName;

                            if (entry.isDir && entry.baseName.startsWith(cdDrivePrefix))
                            {
                                immutable k = entry.baseName[cdDrivePrefix.length .. $];

                                import std.algorithm : all;
                                import std.ascii : isDigit;
                                import std.utf : byChar;

                                if (k != "" && k.byChar.all!isDigit)
                                {
                                    import std.concurrency : yield;
                                    import std.conv : to;

                                    yield(k.to!size_t);
                                }
                            }
                        }
                        catch (FileException fe)
                        {
                            continue;
                        }
                    }
                }
                catch (FileException fe)
                {
                }
            });

            if (r.empty)
            {
                return "";
            }

            import std.algorithm : minElement;
            import std.conv : to;

            return buildPath(devPath, cdDrivePrefix ~ r.minElement.to!string);
        }

        auto getTargetDrive(string drivePathName)
        {
            if (drivePathName == "")
            {
                immutable defaultDrive_ = defaultDrive;
                if (defaultDrive_ == "")
                {
                    logGeneric("No optical drive /dev/cdrom or /dev/sr* found");
                    return GetTargetDriveResult(false, "");
                }
                else
                {
                    logGeneric("Target drive: <" ~ defaultDrive_ ~ ">");
                    return GetTargetDriveResult(true, defaultDrive_);
                }
            }

            logGeneric("Target drive: <" ~ drivePathName ~ ">");
            return GetTargetDriveResult(true, drivePathName);
        }

        auto statusImpl(string drivePathName)
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
        {
            return ejectableClosableCommon!getConfiguration(drivePathName, OpenCloseMode.open);
        }

        auto closableImpl(string drivePathName)
        {
            return ejectableClosableCommon!getConfiguration(drivePathName, OpenCloseMode.close);
        }

        private auto getConfiguration(string drivePathName, ref RemovableMediumFeatureResponse response)
        {
            sg_io_hdr header = {
                interface_id: SG_INTERFACE_ID_ORIG,
                dxfer_direction: SG_DXFER_FROM_DEV,
                cmd_len: GetConfigurationCDB.sizeof,
                dxfer_len: RemovableMediumFeatureResponse.sizeof,
                dxferp: &response,
                cmdp: cast(ubyte*)&getConfigurationCDB,
                sbp: null,
                timeout: 5000};

                int status;
                return ioctlWrapper(drivePathName, SG_IO, status, &header);
            }

            auto openImpl(string drivePathName)
            {
                return ioctlWrapper(drivePathName, CDROMEJECT).ok;
            }

            auto closeImpl(string drivePathName)
            {
                return ioctlWrapper(drivePathName, CDROMCLOSETRAY).ok;
            }
        }
    }
