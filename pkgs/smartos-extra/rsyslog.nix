# rsyslog 5.8.9 as illumos-extra builds it for the platform (rsyslog/Makefile): 32 bits, its patches, with the
# Solaris log input, imfile, mail and program outputs; installed by its own install target: rsyslogd, the runtime's
# and plugins' shared objects in usr/lib/rsyslog, two manuals, and illumos-extra's rsyslog.conf in etc (their proto
# area has etc already; it is made here). The platform's rsyslogd links libz (lmzlibw), so libz is given.
{ mkAutoconf, libz }:

mkAutoconf {
  pname = "smartos-extra-rsyslog";
  version = "5.8.9";
  dir = "rsyslog";
  ver = "rsyslog-5.8.9";
  patches = "patches/*";
  deps = [ libz ];
  configureFlags = [
    "--enable-imsolaris=yes"
    "--enable-imfile=yes"
    "--enable-mail=yes"
    "--enable-omprog=yes"
  ];
  install = suffix: ''
    d=rsyslog-5.8.9-32${suffix}
    mkdir -p $out/usr/sbin $out/usr/lib/rsyslog $out/usr/share/man/man5 $out/usr/share/man/man8 $out/etc
    install -m 0755 $d/tools/rsyslogd $out/usr/sbin/rsyslogd
    cp $d/runtime/.libs/*.so $out/usr/lib/rsyslog
    cp $d/plugins/*/.libs/*.so $out/usr/lib/rsyslog
    cp $d/.libs/*.so $out/usr/lib/rsyslog
    cp $d/tools/rsyslogd.8 $out/usr/share/man/man8/rsyslogd.8
    cp $d/tools/rsyslog.conf.5 $out/usr/share/man/man5/rsyslog.conf.5
    cp rsyslog.conf $out/etc/rsyslog.conf
  '';
}
