# openwrt-custom-feed

Custom OpenWrt package feed for research/utility packages that don't belong
in the main OpenWrt tree.

## Packages

- **`appsbl-toolkit`** / **`luci-app-appsbl-toolkit`** - research-only
  toolkit for the Mercusys MR80X v2/v5 (also sold as the MR3000X) APPSBL
  bootloader and its U-Boot environment partition: dual-key patching
  (accepts this project's own signing key as a fallback alongside
  TP-Link/Mercusys's original key), factory/baseline restore, raw
  backup/restore, U-Boot env inspection and editing, and validating an
  uploaded official TP-Link/Mercusys firmware image's RSA signature
  against the real vendor key before allowing OEM-gated recovery. See
  each package's own Makefile description and
  `appsbl/CLEAN_ROOM_STATUS.md` in the sibling `appsbl` project for the
  full research background. Research-only, no warranty - see the
  in-package warnings before using any of it against real hardware.

## Connecting this feed to an OpenWrt tree

This is a normal git-based OpenWrt feed - one `Makefile` per package,
laid out directly at the repo root (`appsbl-toolkit/Makefile`, not
nested under a `package/` prefix the way the main tree is). Point your
OpenWrt checkout's `feeds.conf` (not `feeds.conf.default` - that file is
the upstream template and is never meant to be edited locally) at it:

```
src-git-full customfeed https://github.com/fbinerd/openwrt-custom-feed.git;openwrt-25.12
```

The `;openwrt-25.12` suffix pins the feed to that branch - match it to
whichever branch of this repo you actually want (this repo mirrors the
OpenWrt release branch naming it targets). Then, from the OpenWrt tree
root:

```
./scripts/feeds update customfeed
./scripts/feeds install -a -p customfeed
make menuconfig   # enable appsbl-toolkit / luci-app-appsbl-toolkit under Utilities/LuCI
```

If you don't want to hand-edit `feeds.conf` every time, the project's own
`opw/openwrt-build-tools/scripts/apply-openwrt-patches.sh` does this
automatically (adds/removes exactly the line above) whenever
`ENABLE_CUSTOM_FEED=1` is set in that project's `.env` - see that
script's `CUSTOM_FEED_LINE` for the exact line it writes, and
`opw/openwrt-build-tools/scripts/build_openwrt.sh` for how it fits into
a full container build. `target/linux/qualcommax/image/ipq50xx.mk`'s
`DEVICE_PACKAGES` for the MR80X v2/v5 already references
`appsbl-toolkit`/`luci-app-appsbl-toolkit` by name, so once the feed is
active and installed, a normal image build picks both packages up
without any further menuconfig changes.

## Research signing keys

`keys/public/` and `keys/private/` hold this project's own self-generated
RSA keypairs (`firmware-rsa2048`, 2048-bit; `legacy-rsa1024`, 1024-bit) -
the fallback signing keys `appsbl-toolkit`'s dual-key patch injects
alongside TP-Link/Mercusys's real key (never a substitute for it; see
`appsbl-toolkit`'s own description for how the fallback path works).
These are **not** TP-Link/Mercusys's real keys - see
`appsbl-toolkit/src/vendor_keys.h` and
`appsbl/scripts/extract-vendor-keys.py` for those, extracted from a
stock APPSBL image, used only to verify an uploaded official firmware
image's signature.

`keys/public/*.publickeyblob.b64` are what's actually embedded in a
patched device's bootloader (also duplicated per-device, independently
editable, in `/etc/appsbl-dualkey/*.b64` after installing
`appsbl-toolkit` - see that package's `--set-key`/`--show-keys`).
`keys/private/*.pem` is the matching signing capability: whoever holds
these can produce a firmware signature that any device patched with the
corresponding public key will accept via the fallback verification path.
Published here deliberately, as part of this project's own research
material - being public means this exact keypair's fallback-signing
capability is no longer exclusive to the original researcher, which is
the tradeoff being made by publishing it alongside the rest of this feed.
Anyone who wants their own device's fallback path to remain exclusively
theirs should generate a fresh keypair (`appsbl/scripts/appsbl-keytool.py
generate`) instead of reusing these.
