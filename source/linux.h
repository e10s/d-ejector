#include <scsi/sg.h>
#ifndef SG_INTERFACE_ID_ORIG
#define SG_INTERFACE_ID_ORIG 'S'
#endif

#undef __SIZEOF_INT128__ // Avoid "Error: __int128 not supported" in linux/types.h
#include <linux/cdrom.h>

