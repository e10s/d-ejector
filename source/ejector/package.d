/*
Copyright electrolysis 2026.
Distributed under the Boost Software License, Version 1.0.
(See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
*/

module ejector;

public import ejector.base;

version (Windows)
{
    import ejector.windows;
}
else version (linux)
{
    version = Ejector_Posix;
    import ejector.posix;
}
else version (FreeBSD)
{
    version = Ejector_Posix;
    import ejector.posix;
}
///
struct Ejector
{
    private immutable string drive = "";
    version (Windows)
    {
        ///
        this(string driveLetter)
        {
            // "a" to "z" or "A" to "Z"
            import std.uni : isAlpha, toUpper;

            if ((driveLetter.length == 1 && driveLetter[0].isAlpha) ||
                (driveLetter.length == 2 && driveLetter[0].isAlpha && driveLetter[1] == ':'))
            {
                drive = driveLetter.toUpper.idup;
            }
        }
        ///
        this(char driveLetter)
        {
            this(cast(string)[driveLetter]);
        }
    }
    version (Ejector_Posix)
    {
        ///
        this(string drivePathName)
        {
            import std.path : absolutePath, buildNormalizedPath;

            immutable normalizedPath = buildNormalizedPath(absolutePath(drivePathName)).idup;
            if (normalizedPath.length)
            {
                drive = normalizedPath;
            }
        }
    }

    ///
    @property auto status()
    {
        immutable targetDrive = getTargetDrive(drive);
        if (!targetDrive.ok)
        {
            return TrayStatus.ERROR;
        }

        return statusImpl(targetDrive.name);
    }
    ///
    @property auto ejectable()
    {
        immutable targetDrive = getTargetDrive(drive);
        if (!targetDrive.ok)
        {
            return false;
        }
        return ejectableImpl(targetDrive.name);
    }
    ///
    @property auto closable()
    {
        immutable targetDrive = getTargetDrive(drive);
        if (!targetDrive.ok)
        {
            return false;
        }
        return closableImpl(targetDrive.name);
    }
    ///
    auto open()
    {
        immutable targetDrive = getTargetDrive(drive);
        if (!targetDrive.ok)
        {
            return false;
        }
        return openImpl(targetDrive.name);
    }
    ///
    auto close()
    {
        immutable targetDrive = getTargetDrive(drive);
        if (!targetDrive.ok)
        {
            return false;
        }
        return closeImpl(targetDrive.name);
    }
}
