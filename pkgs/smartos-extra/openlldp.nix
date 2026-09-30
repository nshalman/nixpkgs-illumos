# openlldp 0.4alpha as illumos-extra builds it for the platform (openlldp/Makefile): 32 bits, its three patches, CFLAGS
# for CTF (-gdwarf-2, no inlining); lldpd and lldpneighbors installed stripped by the platform's /usr/sbin/install, with
# illumos-extra's SMF manifest, then CTF from their DWARF by tools/make-ctf with ctfconvert -m (the programs are
# stripped already). Their proto area has lib/svc/manifest/network and usr/sbin already; they are made here.
{ mkAutoconf, ctfconvert }:

mkAutoconf {
  pname = "smartos-extra-openlldp";
  version = "0.4alpha";
  dir = "openlldp";
  extraDirs = [ "tools" ];
  ver = "openlldp-0.4alpha";
  patches = "Patches/*";
  cflags = "-gdwarf-2 -fno-inline-functions -fno-inline-functions-called-once -fno-inline-small-functions";
  install = suffix: ''
    mkdir -p $out/usr/sbin $out/lib/svc/manifest/network
    /usr/sbin/install -s -m 555 -f $out/usr/sbin openlldp-0.4alpha-32${suffix}/src/lldpd
    /usr/sbin/install -s -m 555 -f $out/usr/sbin openlldp-0.4alpha-32${suffix}/src/lldpneighbors
    /usr/sbin/install -s -m 444 -f $out/lib/svc/manifest/network lldpd.xml
    env -i PATH="$PATH" DESTDIR=$out CTFCONVERT=${ctfconvert} CTFCONVERTFLAGS=-m \
      bash ../tools/make-ctf openlldp-0.4alpha-32${suffix} ctfobjects-32${suffix} openlldp-0.4alpha \
      /usr/sbin/lldpd /usr/sbin/lldpneighbors
  '';
}
