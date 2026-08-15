#include <string.h>

#include "base64.h"

static int b64_value(unsigned char c)
{
	if (c >= 'A' && c <= 'Z')
		return c - 'A';
	if (c >= 'a' && c <= 'z')
		return c - 'a' + 26;
	if (c >= '0' && c <= '9')
		return c - '0' + 52;
	if (c == '+')
		return 62;
	if (c == '/')
		return 63;
	return -1;
}

long base64_decode(const char *in, unsigned char *out, size_t out_cap)
{
	size_t len = strlen(in);
	size_t i;
	size_t outlen = 0;
	unsigned int buf = 0;
	int bits = 0;
	size_t pad = 0;

	if (len == 0 || len % 4 != 0)
		return -1;

	for (i = 0; i < len; i++) {
		unsigned char c = (unsigned char)in[i];

		if (c == '=') {
			pad++;
			if (i < len - 2)
				return -1; /* '=' only valid in the last two positions */
			continue;
		}
		if (pad)
			return -1; /* non-padding after padding started */

		int v = b64_value(c);

		if (v < 0)
			return -1;

		buf = (buf << 6) | (unsigned int)v;
		bits += 6;
		if (bits >= 8) {
			bits -= 8;
			if (outlen >= out_cap)
				return -1;
			out[outlen++] = (unsigned char)((buf >> bits) & 0xff);
		}
	}

	return (long)outlen;
}
