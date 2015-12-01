/*
Copyright electrolysis 2015.
Distributed under the Boost Software License, Version 1.0.
(See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
*/

#include <stdio.h>
#include <stddef.h>
#include <camlib.h>

int main()
{
    printf("enum CCB_SIZE = %lu;\n", sizeof(union ccb));

    // ccb.csio.cdb_len
    printf("enum CCB_CDB_LEN_OFFSET = %lu;\n", offsetof(union ccb, csio) +
        offsetof(struct ccb_scsiio, cdb_len));

    // ccb.csio.cdb_io.cdb_bytes
    printf("enum CCB_CDB_BYTES_OFFSET = %lu;\n", offsetof(union ccb, csio) +
        offsetof(struct ccb_scsiio, cdb_io) + offsetof(cdb_t, cdb_bytes));

    return 0;
}
