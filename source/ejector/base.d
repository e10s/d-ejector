/*
Copyright electrolysis 2026.
Distributed under the Boost Software License, Version 1.0.
(See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
*/

module ejector.base;

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

// SCSI Command Descriptor Blocks


package struct GetConfigurationCDB
{
    ubyte operationCode = 0x46;
    ubyte rt;
    ubyte[2] startingFeatureNumber;
    ubyte[3] reserved3;
    ubyte[2] allocationLength;
    ubyte control;
}

static assert(GetConfigurationCDB.sizeof == 10);

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

package bool parseEjectableClosable(OpenCloseMode mode)(RemovableMediumFeatureResponse response)
{

    // ftp://ftp.seagate.com/sff/INF-8090.PDF, p.638
    // Test the Eject bit
    static if (mode == OpenCloseMode.open)
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
