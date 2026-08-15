/*
 * appsbl-verify-image - checks an uploaded file's RSA signature against
 * TP-Link/Mercusys's REAL public firmware-signing keys, using their own
 * verification code (vendor-rsa/rsaVerify.c and friends, from their own
 * GPL release for this exact firmware format - see
 * appsbl/CLEAN_ROOM_STATUS.md and appsbl/scripts/tplink-cloud-sign-
 * crosscheck/README.md for how this was reverse-engineered and
 * cross-checked). This is the vendor's OWN verification logic, compiled
 * as-is - not a reimplementation of it.
 *
 * Image format ("fw-type:Cloud", nm_fwup.c's handle_fw_cloud()):
 *   0x0000  u32 BE   declared total image size
 *   0x0014  ...      "fw-type:Cloud\n" (start of the RSA-signed region)
 *   0x0112  1 byte   algorithm marker: 2 selects RSA-2048/PSS/SHA-256,
 *                    anything else selects legacy RSA-1024/PKCS#1v1.5
 *   0x0130  0x80 or  RSA signature, stored byte-reversed
 *           0x100
 *
 * A valid signature here proves the file was genuinely signed by
 * TP-Link/Mercusys's real private key for this device family - nothing
 * else about the file's contents is interpreted or trusted. This tool
 * only answers "is this signature valid", it does not itself change
 * anything; see appsbl-verify-and-restore(8) for what a valid result is
 * used to unlock.
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "vendor-rsa/rsaVerify.h"
#include "vendor-rsa/md5_min.h"
#include "vendor_keys.h"

#define IMAGE_SIZE_LEN 0x04UL
#define IMAGE_SIZE_MD5 0x10UL
#define IMAGE_SIZE_PRODUCT 0x1000UL
#define IMAGE_SIZE_BASE (IMAGE_SIZE_LEN + IMAGE_SIZE_MD5 + IMAGE_SIZE_PRODUCT) /* 0x1014 */
#define IMAGE_SIZE_MIN (IMAGE_SIZE_BASE + 0x800UL) /* 0x1814 */

#define IMAGE_SIZE_FWTYPE (IMAGE_SIZE_LEN + IMAGE_SIZE_MD5) /* 0x14, signed region starts here */
#define IMAGE_SIZE_RSA_SIG (IMAGE_SIZE_FWTYPE + 0x11CUL) /* 0x130 */
#define IMAGE_SIZE_RSA_VER (IMAGE_SIZE_RSA_SIG - 0x20UL) /* 0x110 */
#define IMAGE_LEN_RSA_SIG 0x80UL
#define IMAGE_LEN_RSA2048_SIG 0x100UL

/* Mirrors nm_fwup.c's handle_fw_cloud() exactly: zero the signature slot
 * for hashing, verify, restore it. pss_mode selects RSA-2048/PSS
 * (internal SHA-256 over the whole signed region) vs legacy RSA-1024
 * (SHA-1 of an MD5 digest of the signed region, computed here since
 * rsaVerify.c expects the MD5 pre-hash as its input, not the raw data). */
static int handle_fw_cloud(unsigned char *buf, unsigned long buf_len, const char *pubkey_blob, int pss_mode)
{
	unsigned char sig_buf[IMAGE_LEN_RSA2048_SIG] = {0};
	unsigned char tmp_rsa_sig[IMAGE_LEN_RSA2048_SIG] = {0};
	unsigned long siglen = pss_mode ? IMAGE_LEN_RSA2048_SIG : IMAGE_LEN_RSA_SIG;
	int ret;

	memcpy(tmp_rsa_sig, buf + IMAGE_SIZE_RSA_SIG, siglen);
	memcpy(sig_buf, buf + IMAGE_SIZE_RSA_SIG, siglen);
	memset(buf + IMAGE_SIZE_RSA_SIG, 0, siglen);

	if (pss_mode) {
		ret = rsaVerifyPSSSignByBase64EncodePublicKeyBlob(
			(unsigned char *)pubkey_blob, (uint32_t)strlen(pubkey_blob),
			buf + IMAGE_SIZE_FWTYPE, (uint32_t)(buf_len - IMAGE_SIZE_FWTYPE),
			sig_buf, (uint32_t)siglen);
	} else {
		unsigned char md5_dig[IMAGE_SIZE_MD5] = {0};

		md5(buf + IMAGE_SIZE_FWTYPE, buf_len - IMAGE_SIZE_FWTYPE, md5_dig);
		ret = rsaVerifySignByBase64EncodePublicKeyBlob(
			(unsigned char *)pubkey_blob, (unsigned long)strlen(pubkey_blob),
			md5_dig, IMAGE_SIZE_MD5, sig_buf, IMAGE_LEN_RSA_SIG);
	}

	memcpy(buf + IMAGE_SIZE_RSA_SIG, tmp_rsa_sig, siglen);
	return ret;
}

int main(int argc, char **argv)
{
	FILE *f;
	long len;
	unsigned char *buf;
	uint32_t declared_size;
	int pss_mode;
	int ret;

	if (argc != 2) {
		fprintf(stderr, "usage: %s <image.bin>\n", argv[0]);
		return 2;
	}

	f = fopen(argv[1], "rb");
	if (!f) {
		fprintf(stderr, "appsbl-verify-image: cannot open %s\n", argv[1]);
		return 2;
	}
	if (fseek(f, 0, SEEK_END)) {
		fclose(f);
		return 2;
	}
	len = ftell(f);
	if (len < (long)IMAGE_SIZE_MIN) {
		fprintf(stderr, "appsbl-verify-image: %s is only %ld bytes, too small to be this image format\n",
			argv[1], len);
		fclose(f);
		return 1;
	}
	if (fseek(f, 0, SEEK_SET)) {
		fclose(f);
		return 2;
	}

	buf = malloc((size_t)len);
	if (!buf) {
		fprintf(stderr, "appsbl-verify-image: out of memory\n");
		fclose(f);
		return 2;
	}
	if (fread(buf, 1, (size_t)len, f) != (size_t)len) {
		fprintf(stderr, "appsbl-verify-image: failed reading %s\n", argv[1]);
		free(buf);
		fclose(f);
		return 2;
	}
	fclose(f);

	declared_size = ((uint32_t)buf[0] << 24) | ((uint32_t)buf[1] << 16) |
			((uint32_t)buf[2] << 8) | (uint32_t)buf[3];
	if (declared_size != (uint32_t)len) {
		fprintf(stderr,
			"appsbl-verify-image: declared size %u does not match actual file size %ld - "
			"not this image format, refusing\n",
			declared_size, len);
		free(buf);
		return 1;
	}
	if (memcmp(buf + IMAGE_SIZE_FWTYPE, "fw-type:Cloud\n", 14)) {
		fprintf(stderr, "appsbl-verify-image: missing 'fw-type:Cloud' marker - not this image format\n");
		free(buf);
		return 1;
	}

	pss_mode = (buf[IMAGE_SIZE_RSA_VER + 2] == 2);
	printf("appsbl-verify-image: %s bytes, algorithm marker selects RSA-%s\n",
	       argv[1], pss_mode ? "2048/PSS/SHA-256" : "1024/PKCS#1v1.5 (legacy)");

	ret = handle_fw_cloud(buf, (unsigned long)len,
			      pss_mode ? appsbl_vendor_pubkey_rsa2048 : appsbl_vendor_pubkey_rsa1024,
			      pss_mode);

	free(buf);

	if (ret) {
		printf("appsbl-verify-image: VALID - genuinely signed by TP-Link/Mercusys's real key\n");
		return 0;
	}

	printf("appsbl-verify-image: INVALID - signature does not verify against the real vendor key\n");
	return 1;
}
