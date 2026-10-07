# The tun/tap driver 1.3 as illumos-extra builds it for the platform (tun/Makefile): 64 bits only, its two patches
# (configure's kernel flags), then the drivers, their .conf files and if_tun.h copied into place.
#
# illumos-extra bug, not reproduced: configure puts the day of the build in the version string the drivers report
# (TUN_VER, `date '+%m/%d/%Y'`); here the day of SOURCE_DATE_EPOCH.
{ mkAutoconf }:

mkAutoconf {
  pname = "smartos-extra-tun";
  version = "1.3";
  dir = "tun";
  ver = "tun-1.3";
  patches = "Patches/*";
  bits = [ 64 ];
  frob = ''
    chmod 755 $d/configure
    substituteInPlace $d/configure \
      --replace-fail "\`date '+%m/%d/%Y'\`" "$(date -u -d @$SOURCE_DATE_EPOCH '+%m/%d/%Y')"
  '';
  install = suffix: ''
    mkdir -p $out/usr/include/net $out/usr/kernel/drv/amd64
    cp tun-1.3-64${suffix}/if_tun.h $out/usr/include/net
    cp tun-1.3-64${suffix}/tap.conf tun-1.3-64${suffix}/tun.conf $out/usr/kernel/drv
    cp tun-1.3-64${suffix}/tap tun-1.3-64${suffix}/tun $out/usr/kernel/drv/amd64
  '';
}
