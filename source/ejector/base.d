/*
Copyright electrolysis 2026.
Distributed under the Boost Software License, Version 1.0.
(See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
*/

module ejector.base;

package enum IoctlErrorStage
{
    none,
    open,
    ioctl
}

import std.typecons : Tuple;

package alias IoctlResult = Tuple!(bool, "ok", IoctlErrorStage, "stage", int, "errorNumber");

package void logGeneric(T...)(lazy string message, lazy T additionalMessages, string caller = __FUNCTION__)
{
    debug (VerboseEjector)
    {
        import std.stdio : stderr, writeln;

        stderr.writeln("<" ~ caller ~ ">");
        stderr.writeln("=> ", message);
        foreach (m; additionalMessages)
        {
            stderr.writeln("  => ", m);
        }
    }
}

enum TrayStatus
{
    ERROR,
    OPEN,
    CLOSED
}

package enum OpenCloseMode
{
    open,
    close
}

// MMC-6 Command Descriptor Blocks

package struct GetConfigurationCDB
{
    immutable ubyte operationCode = 0x46;
    ubyte rt;
    ubyte[2] startingFeatureNumber;
    ubyte[3] reserved3;
    ubyte[2] allocationLength;
    ubyte control;
}

static assert(GetConfigurationCDB.sizeof == 10);

package struct MechanismStatusCDB
{
    immutable ubyte operationCode = 0xBD;
    ubyte[7] reserved7;
    ubyte[2] allocationLength;
    ubyte reserved;
    ubyte control;
}

static assert(MechanismStatusCDB.sizeof == 12);
immutable MechanismStatusCDB mechanismStatusCDB = {allocationLength: [0, MechanismStatusHeader.sizeof]};

// MMC-6 Command Response Data Structures

import std.bitmanip : bitfields;

private mixin template FeatureHeader()
{
    ubyte[4] dataLength;
    ubyte[2] reserved2;
    ubyte[2] currentProfile;
}

private mixin template FeatureDescriptorHead()
{
    ubyte[2] featureCode;
    mixin(bitfields!(
            ubyte, "current", 1,
            ubyte, "persistent", 1,
            ubyte, "version_", 4,
            ubyte, "reserved0", 2
    ));
    ubyte additionalLength;
}

private mixin template RemovableMediumFeatureDescriptorData()
{
    mixin(bitfields!(
            ubyte, "lock", 1,
            ubyte, "dbml", 1, // If version_ >= 2
            ubyte, "pvntJmpr", 1,
            ubyte, "eject", 1,
            ubyte, "load", 1, // If version_ >= 1
            ubyte, "loadingMechanismType", 3
    ));
    ubyte[3] reserved3;
}

package struct RemovableMediumFeatureResponse
{
    mixin FeatureHeader;
    mixin FeatureDescriptorHead;
    mixin RemovableMediumFeatureDescriptorData;
}

static assert(RemovableMediumFeatureResponse.sizeof == 16);

package struct MechanismStatusHeader
{
    mixin(bitfields!(
            ubyte, "currentSlotLow5", 5,
            ubyte, "changerState", 2,
            ubyte, "fault", 1,
    ));
    mixin(bitfields!(
            ubyte, "currentSlotHigh3", 3,
            ubyte, "reserved0", 1,
            ubyte, "doorOpen", 1,
            ubyte, "mechanismState", 3,
    ));
    ubyte[3] currentLBA;
    ubyte numberOfSlotsAvailable;
    ubyte[2] lengthOfSlotTables;
}

static assert(MechanismStatusHeader.sizeof == 8);

// Goodies

package bool ejectableClosableCommon(alias getConfigurationFunction)(string driveName, OpenCloseMode mode)
{
    auto response = RemovableMediumFeatureResponse();
    immutable ioctlResult = getConfigurationFunction(driveName, response);

    debug (VerboseEjector)
    {
        import std.stdio : stderr, writeln;

        if (ioctlResult.ok)
        {
            stderr.writeln("get configuration succeeded, ", driveName);
            stderr.writeln(response);
        }
        else
        {
            stderr.writeln("get configuration failed, ", driveName);
        }
    }

    if (!ioctlResult.ok)
    {
        // We might have to execute MODE SENSE (10)
        return false;
    }

    return parseEjectableClosable(response, mode);
}

private bool parseEjectableClosable(RemovableMediumFeatureResponse response, OpenCloseMode mode)
{

    // ftp://ftp.seagate.com/sff/INF-8090.PDF, p.638
    // Test the Eject bit
    if (mode == OpenCloseMode.open)
    {
        return !!response.eject;
    }
    else
    {
        // Test the Version field and the Load bit
        if (response.version_ > 0)
        {
            return !!response.load;
        }

        // [[ Doubtful ]]
        // Guess from the Loading Mechanism Type field
        // Drives other than ones with caddy/slot type loading mechanism will be closable(?)
        // https://github.com/torvalds/linux/blob/master/drivers/scsi/sr.c

        // Maybe closable
        return response.loadingMechanismType != 0;
    }
}

package TrayStatus parseStatus(MechanismStatusHeader mechanismStatusHeader)
{
    // ftp://ftp.seagate.com/sff/INF-8090.PDF, p.742
    return mechanismStatusHeader.doorOpen ? TrayStatus.OPEN : TrayStatus.CLOSED;
}
