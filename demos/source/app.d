/*
Copyright electrolysis 2015.
Distributed under the Boost Software License, Version 1.0.
(See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
*/

import ejector;

void testDrive(ref Ejector e)
{
    import std.stdio : writeln;

    writeln("Ejectable?: ", e.ejectable);
    writeln("Closable?: ", e.closable);

    immutable statusResult = e.status;

    import result : isErr, unwrap;

    if (statusResult.isErr)
    {
        writeln("Failed to get current status.");
        return;
    }

    immutable status = statusResult.unwrap;
    writeln("Current status: ", status);

    // Try to toggle the drive open/closed.
    if (status == TrayStatus.OPEN)
    {
        immutable result = e.close();
        writeln("Tried to close the drive... ", result);
    }
    else if (status == TrayStatus.CLOSED)
    {
        immutable result = e.open();
        writeln("Tried to open the drive... ", result);
    }

    immutable newStatusResult = e.status;

    if (newStatusResult.isErr)
    {
        writeln("Failed to get new status.");
        return;
    }

    writeln("New status: ", newStatusResult.unwrap);
}

void main()
{
    version (linux)
    {
        auto targets = [
            "/dev/sr0", "/dev/sr1", "/dev/null", "/../root", "/no/such/device",
            "what about this/../how about this?"
        ];
    }
    version (FreeBSD)
    {
        auto targets = [
            "/dev/cd0", "/dev/cd1", "/dev/null", "/../root", "/no/such/device",
            "what about this/../how about this?"
        ];
    }
    version (Windows)
    {
        auto targets = [
            "e", "F", "c:\\windows", "whats", "what about this/../how about this?"
        ];
    }

    // Assign a device and test it.
    auto ejectorSpecified = Ejector(targets[0]);
    testDrive(ejectorSpecified);

    // Try to automatically obtain the default drive and test it.
    auto ejectorDefault = Ejector();
    testDrive(ejectorDefault);

    // Search for ejectable drives and try to get their information.
    foreach (drive; targets[1 .. $])
    {
        import std.stdio : writeln;
        import std.typecons : tuple;

        writeln("Testing ", drive, "...");

        auto ejector = Ejector(drive);

        immutable info = tuple!("Ejectable", "Closable", "Status")(ejector.ejectable,
                ejector.closable, ejector.status);
        writeln(info);

    }
}
