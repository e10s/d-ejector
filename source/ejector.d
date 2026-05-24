/*
Copyright electrolysis 2026.
Distributed under the Boost Software License, Version 1.0.
(See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
*/

module ejector;

public import ejector_base;
import ejector_win;

///
struct Ejector
{
    version (Windows)
    {
        private string drive = "";
        ///
        this(string driveLetter)
        {
            // "a" to "z" or "A" to "Z"
            import std.uni : isAlpha, toUpper;

            if (driveLetter.length == 1 && driveLetter[0].isAlpha)
            {
                drive = driveLetter.toUpper;
            }
        }
        ///
        this(char driveLetter)
        {
            this(cast(string)[driveLetter]);
        }
    }
    else version (linux)
    {
        private string drive = "/dev/cdrom";
    }
    else version (FreeBSD)
    {
        private string drive = "/dev/cd0";
    }
    ///
    @property auto status()
    {
        return statusImpl(drive);
    }
    ///
    @property auto ejectable()
    {
        return ejectableImpl(drive);
    }
    ///
    @property auto closable()
    {
        return closableImpl(drive);
    }
    ///
    auto open()
    {
        return openImpl(drive);
    }
    ///
    auto closed()
    {
        return closeImpl(drive);
    }
}
