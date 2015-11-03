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

#define GET_CONFIGURETION_CMD_LEN 12
#define GET_CONFIGURATION_RESPONSE_BUF_LEN 16

#define ERR_STR_BUF_LEN 512

int _cam_commander(const char* path, const unsigned char* cmd, const int cmd_len, unsigned char* buf, int buf_len, int* status, char* err_str_buf, const int err_str_buf_len){
	char dev_name[DEV_IDLEN + 1];
	int unit;

 	int cgd = cam_get_device(path, dev_name, DEV_IDLEN, &unit);
	if(cgd == -1){
		strcpy(err_str_buf, cam_errbuf);
		fputs(err_str_buf, stderr);
		return -1;
	}

	struct cam_device* cam_dev = cam_open_spec_device(dev_name, unit, O_RDWR, NULL);
	if(!cam_dev){
		strcpy(err_str_buf, cam_errbuf);
		fputs(err_str_buf, stderr);
		return -2;
	}

	union ccb ccb;
	
	cam_fill_csio(&ccb.csio, 1, NULL, CAM_DIR_IN, MSG_SIMPLE_Q_TAG, buf, buf_len, 0, cmd_len, 5000);
    memcpy(ccb.csio.cdb_io.cdb_bytes, cmd, cmd_len);

	int csc = cam_send_ccb(cam_dev, &ccb);
	if(csc == -1){
		strcpy(err_str_buf, cam_errbuf);
		fputs(err_str_buf, stderr);
		cam_close_device(cam_dev);
		return -3;
	}

	cam_close_device(cam_dev);

	return 0;
}

int get_tray_status(const char* path, int* status){
	enum TrayStatus{
		ERROR, OPEN, CLOSED
	};

	*status = ERROR;

	unsigned char mechanism_status_cmd [MECHANISM_STATUS_CMD_LEN] =
    	{0xBD, 0, 0, 0, 0, 0, 0, 0, 0, MECHANISM_STATUS_RESPONSE_BUF_LEN, 0, 0};
	unsigned char mechanism_status_response_buf[MECHANISM_STATUS_RESPONSE_BUF_LEN];
	char err_str_buf[ERR_STR_BUF_LEN];

	int cc = _cam_commander(path, mechanism_status_cmd, MECHANISM_STATUS_CMD_LEN,
		mechanism_status_response_buf, MECHANISM_STATUS_RESPONSE_BUF_LEN, status,
		err_str_buf, ERR_STR_BUF_LEN);
	
	if(cc < -1){
		return cc;
	}

	*status = mechanism_status_response_buf[1] & 0b00010000 ? OPEN : CLOSED;

	return 0;
}

int get_tray_ejectability(const char* path, int* status){
	enum Ejectability{
		ERROR, EJECTABLE, NOT_EJECTABLE
	};

	*status = ERROR;

	unsigned char get_configuration_cmd [GET_CONFIGURETION_CMD_LEN] =
    	{0x46, 0x02, 0, 0x03, 0, 0, 0, 0, GET_CONFIGURATION_RESPONSE_BUF_LEN, 0, 0, 0};
	unsigned char get_configuration_response_buf[GET_CONFIGURATION_RESPONSE_BUF_LEN];
	char err_str_buf[ERR_STR_BUF_LEN];

	int cc = _cam_commander(path, get_configuration_cmd, GET_CONFIGURETION_CMD_LEN,
		get_configuration_response_buf, GET_CONFIGURATION_RESPONSE_BUF_LEN, status,
		err_str_buf, ERR_STR_BUF_LEN);
	
	if(cc < -1){
		return cc;
	}

	*status = get_configuration_response_buf[12] & 0b00001000 ? EJECTABLE : NOT_EJECTABLE;

	return 0;
}
