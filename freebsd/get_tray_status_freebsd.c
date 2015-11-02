/*
Copyright electrolysis 2015.
Distributed under the Boost Software License, Version 1.0.
(See copy at http://www.boost.org/LICENSE_1_0.txt)
*/

#include <stdio.h>
#include <string.h>
#include <fcntl.h>

#include <camlib.h> // requires -lcam

#include <cam/scsi/scsi_message.h> // MSG_SIMPLE_Q_TAG

#define MECHANISM_STATUS_CMD_LEN 12
#define MECHANISM_STATUS_RESPONSE_BUF_LEN 8

int get_tray_status(const char* path, int* status){
	enum TrayStatus{
		ERROR, OPEN, CLOSED
	};

	*status = ERROR;

	char dev_name[DEV_IDLEN + 1];
	int unit;

 	int cgd = cam_get_device(path, dev_name, DEV_IDLEN, &unit);
	if(cgd == -1){
		fputs("cam_get_device: failed\n", stderr);
		fputs(cam_errbuf, stderr);
		fputs("\n", stderr);
		return -1;
	}

	struct cam_device* cam_dev = cam_open_spec_device(dev_name, unit, O_RDWR, NULL);
	if(!cam_dev){
		fputs("cam_open_spec_device: failed\n", stderr);
		fputs(cam_errbuf, stderr);
		fputs("\n", stderr);
		return -2;
	}

	union ccb ccb;
	unsigned char mechanism_status_response_buf[MECHANISM_STATUS_RESPONSE_BUF_LEN];
	unsigned char mechanism_status_cmd [MECHANISM_STATUS_CMD_LEN] =
    	{0xBD, 0, 0, 0, 0, 0, 0, 0, 0, MECHANISM_STATUS_RESPONSE_BUF_LEN, 0, 0};

	cam_fill_csio(&ccb.csio, 1, NULL, CAM_DIR_IN, MSG_SIMPLE_Q_TAG, mechanism_status_response_buf,
		MECHANISM_STATUS_RESPONSE_BUF_LEN, 0, MECHANISM_STATUS_CMD_LEN, 5000);
    memcpy(ccb.csio.cdb_io.cdb_bytes, mechanism_status_cmd, MECHANISM_STATUS_CMD_LEN);

	int csc = cam_send_ccb(cam_dev, &ccb);
	if(csc == -1){
		cam_close_device(cam_dev);

		fputs("cam_send_ccb: failed\n", stderr);
		fputs(cam_errbuf, stderr);
		fputs("\n", stderr);
		return -3;
	}
	*status = mechanism_status_response_buf[1] & 0b00010000 ? OPEN : CLOSED;

	cam_close_device(cam_dev);

	return 0;
}
