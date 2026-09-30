# ipmitool 1.8.18 as illumos-extra builds it for the platform (ipmitool/Makefile): 32 bits, its six patches, with the
# Solaris options and the lanplus interface, configure given LD=/usr/bin/ld (the build host's link-editor, as theirs)
# and INSTALL; the program and its manual installed by ipmitool/install-joyent.
#
# lanplus needs OpenSSL: its configure looks for -lsunw_crypto, which only openssl3 provides. The top Makefile does not
# make it wait for openssl3, but the platform's ipmitool links libcrypto-smartos.so.3, so openssl3 is given.
#
# install-joyent puts the manual in usr/man/man1, which their proto area has as a link to share/man (the manifest
# lists usr/share/man/man1/ipmitool.1); the link is made for the install and removed after it.
{
  mkAutoconf,
  openssl3,
  gnuGTools,
}:

mkAutoconf {
  pname = "smartos-extra-ipmitool";
  version = "1.8.18";
  dir = "ipmitool";
  ver = "ipmitool-1.8.18";
  patches = "Patches/*";
  deps = [ openssl3 ];
  # its configure sets LD=gld AR=gar on Solaris, found on their build host's PATH (pkgsrc)
  nativeBuildInputs = [ gnuGTools ];
  cppflags = "-D_FILE_OFFSET_BITS=64 -D_LARGEFILE_SOURCE -D__EXTENSIONS__";
  cflags = "-g";
  configureEnv = ''LD=/usr/bin/ld INSTALL="install -c"'';
  configureFlags = [
    "--enable-solaris-opt"
    "--enable-intf-lanplus"
  ];
  install = suffix: ''
    mkdir -p $out/usr/share/man
    ln -s share/man $out/usr/man
    DESTDIR=$out VERS=ipmitool-1.8.18-32${suffix} bash ./install-joyent
    rm $out/usr/man
  '';
}
