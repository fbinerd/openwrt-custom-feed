CFLAGS ?= -O2
CC ?= cc

VENDOR_SRCS = vendor-rsa/rsaVerify.c vendor-rsa/bigNumber.c vendor-rsa/shaAndSha512.c vendor-rsa/aes.c
VENDOR_OBJS = $(VENDOR_SRCS:.c=.o)

all: appsbl-dualkey-patcher appsbl-verify-image

appsbl-dualkey-patcher: appsbl-patch.c sha256.c sha256.h base64.c base64.h puff.c puff.h patch_data.h
	$(CC) $(CFLAGS) $(LDFLAGS) appsbl-patch.c sha256.c base64.c puff.c -o $@

# appsbl-verify-image links TP-Link/Mercusys's own vendor-rsa/*.c verbatim
# (their real GPL-released verification code, not a reimplementation - see
# appsbl-verify-image.c's own comment) - compiled with -w since this
# project does not modify vendor code to satisfy its own warning flags.
appsbl-verify-image: appsbl-verify-image.o $(VENDOR_OBJS)
	$(CC) $(LDFLAGS) appsbl-verify-image.o $(VENDOR_OBJS) -o $@

appsbl-verify-image.o: appsbl-verify-image.c vendor_keys.h vendor-rsa/rsaVerify.h vendor-rsa/md5_min.h
	$(CC) $(CFLAGS) -Ivendor-rsa -c appsbl-verify-image.c -o $@

$(VENDOR_OBJS): %.o: %.c
	$(CC) $(CFLAGS) -w -c $< -o $@

clean:
	rm -f appsbl-dualkey-patcher appsbl-verify-image appsbl-verify-image.o $(VENDOR_OBJS)
