# smartos-live's own stages (pkgs/smartos-live), each against what SmartOS's own platform from the same smartos-live
# commit ships of it (tests/strap-compare.sh with smartos-extra.platformReference as the reference, limited to the
# paths the stage's manifests list as files; modes left out, since the platform takes them from the manifest), and
# used.
#   nix-build tests/smartos-live.nix --arg pkgs 'import /etc/nixos/pkgs.nix'
{ pkgs }:

let
  live = pkgs.smartos-live;
  extra = pkgs.smartos-extra;
  inherit (pkgs.smartos-strap) gcc10-illumos;
  node = "${live.strapProto}/usr/node/0.10/bin/node";

  # compareWith ENV NAME PKG LIST EXPECTED CHECK: PKG against the platform's files and links that LIST (shell
  # commands writing relative paths, one per line) names, with the differences in the paths EXPECTED (a regex)
  # matches shown and accepted (each caller says why); CHECK is more shell, run after; ENV is more of
  # strap-compare.sh's environment. f entries only, as for illumos-extra (tests/smartos-extra.nix): the builder makes
  # the links. compare is compareWith no more environment.
  compareWith =
    env: name: pkg: list: expected: check:
    pkgs.runCommand "smartos-live-${name}-compare" { } ''
      {
        ${list}
      } | sort -u >list
      ${env} IGNORE_MODES=1 PATH_LIST=$PWD/list GCC_LIB=${gcc10-illumos.lib} GCC_OUT=${gcc10-illumos} \
        bash ${./strap-compare.sh} ${extra.platformReference} ${pkg} '.' '${expected}' >report 2>&1 ||
        { cat report; exit 1; }
      cat report
      # nothing installed under a store path's name ($DESTDIR followed by an absolute path)
      if [ -e ${pkg}/nix ]; then echo "FAIL ${pkg}/nix exists:"; find ${pkg}/nix; exit 1; fi
      echo "ok   nothing under nix/" | tee -a report
      ${check}
      cp report $out
    '';
  compare = compareWith "";
  # the f entries of src/manifest's section SECTION (its "# SECTION" comment line up to the next)
  srcManifestSection =
    section:
    ''awk '/^# / { s = $0 } $1 == "f" && s == "# ${section}" { print $2 }' ${live.smartosLive}/src/manifest'';
  # the f entries of local project NAME's manifest
  localManifest = name: ''awk '$1 == "f" { print $2 }' ${live.localSrc.${name}}/manifest'';
in
{
  # src's manifest is what src/Makefile's manifest target writes: src/manifest and the vm and fw tests and examples,
  # which it lists with git ls-files (here with find, the source having no .git). Not this stage's, so left out:
  # src/manifest's 0-devpro-stamp section (devpro, below), and of man's, man.cf (made from the whole manifest by
  # tools/mancf) and, of src's, var/log/syslog (made empty in the image by tools/build_live).
  #
  # Expected to differ: the dist.shasum npm writes into fs-ext's package.json, a sha1 of the tarball npm makes from
  # the git archive of the pinned commit (npm 1.4.3's addRemoteGit, then addTmpTarball). Why theirs differs is not
  # known: ours is the same from one build to the next, and is not the sha1 of that git archive gzipped by the strap
  # node's zlib as addRemoteGit does, so the tarball hashed is another; their git's archive may differ from nixpkgs'.
  # The rest of the file, _resolved and _from (what was installed) among it, is compared apart.
  livesrc =
    let
      src = "${live.smartosLive}/src";
      fsExtJson = "usr/node/0.10/node_modules/fs-ext/package.json";
    in
    compare "src" live.livesrc
      ''
        awk '/^# / { s = $0 } $1 == "f" && s != "# 0-devpro-stamp" { print $2 }' ${src}/manifest |
          grep -vx var/log/syslog
        awk '$1 == "f" { print $2 }' ${live.smartosLive}/man/manifest | grep -vx usr/share/man/man.cf
        # and the pages man installs over illumos-extra's, which illumos-extra's manifest lists
        awk '/^MAN_FILES =/ { on = 1; next } on && NF == 0 { on = 0 } on { print $1 }' ${live.smartosLive}/man/Makefile
        (cd ${src}/vm && find tests \( -type f -o -type l \) -print) | grep -v /testdata/ | sed 's|^|usr/vm/test/|'
        (cd ${src}/vm/tests && find testdata \( -type f -o -type l \) -print) | sed 's|^|usr/vm/test/|'
        (cd ${src}/fw/test && find integration \( -type f -o -type l \) -print) | sed 's|^|usr/fw/test/|'
        (cd ${src}/fw/etc && find examples \( -type f -o -type l \) -print) | sed 's|^|usr/fw/etc/|'
      ''
      "^${fsExtJson}$"
      ''
        diff <(grep -v '"shasum": ' ${extra.platformReference}/${fsExtJson}) \
          <(grep -v '"shasum": ' ${live.livesrc}/${fsExtJson})
        echo "ok   ${fsExtJson} but for dist.shasum" | tee -a report
      '';

  # src/manifest's 0-devpro-stamp section
  devpro = compare "devpro" live.devpro (srcManifestSection "0-devpro-stamp") "" "";
  # a program built by the strap gcc against libdemangle, for each word size, run: it demangles a Sun C++ name
  devpro-use = pkgs.runCommand "smartos-live-devpro-use" { } ''
    cat >t.c <<'C'
    #include <stdio.h>
    #include <demangle.h>
    int main(void) {
      char out[128];
      if (cplus_demangle("__1cDfoo6Fi_v_", out, sizeof out) != 0) return 1;
      printf("%s\n", out);
      return 0;
    }
    C
    for bits in 32 64; do
      if [ $bits = 32 ]; then l=${live.devpro}/usr/lib; else l=${live.devpro}/usr/lib/amd64; fi
      ${pkgs.smartos-strap.gcc} -m$bits -I${live.devpro}/usr/include -isystem ${live.illumosProto}/usr/include t.c \
        -o t$bits $l/libdemangle.so.1 -R$l
      /usr/bin/ldd t$bits | grep "libdemangle.so.1 =>[[:space:]]*$l/" >/dev/null
      ./t$bits | tee out$bits
      grep -x 'void foo(int)' out$bits >/dev/null
      echo "ok   $bits-bit libdemangle demangles"
    done
    touch $out
  '';

  # manifest.gen: every file it lists is in the platform (built from another illumos-joyent commit, so not compared
  # line by line), and it has entries from each stage's manifest
  manifest = pkgs.runCommand "smartos-live-manifest-check" { } ''
    m=${live.manifest}/manifest.gen
    awk '$1 == "f" { print $2 }' $m >files
    n=0
    while read f; do [ -e ${extra.platformReference}/$f ] || { echo "not in the platform: $f"; n=$((n + 1)); }; done <files
    [ $n = 0 ]
    for p in kernel/drv/amd64/zfs usr/bin/bash usr/vm/sbin/vmadmd usr/share/man/man8/vmadm.8 usr/lib/kbm/kbmd \
      usr/kernel/drv/amd64/kvm smartdc/bin/qemu-system-x86_64 usr/sbin/mdata-get smartdc/ur-agent/ur-agent; do
      grep -q "^f $p " $m || { echo "FAIL $p not in manifest.gen"; exit 1; }
    done
    echo "ok   all $(wc -l <files) files manifest.gen lists are in the platform; each stage's are there" | tee $out
  '';
  # gitstatus.json: written as build_etcrelease writes it (the platform's own entries give its etc/versions/build
  # byte for byte), and from the pins the same as the platform's but for illumos-joyent (pinned at a master commit,
  # not the release's) and the URLs' case (theirs are their clones' remotes)
  gitstatus =
    let
      platformJSON = "${extra.platformReference}/etc/versions/build";
      again = pkgs.writeText "gitstatus-again" (
        live.gitstatusText (builtins.fromJSON (builtins.readFile platformJSON))
      );
    in
    pkgs.runCommand "smartos-live-gitstatus-check" { nativeBuildInputs = [ pkgs.python3 ]; } ''
      cmp ${again} ${platformJSON}
      echo "ok   gitstatusText writes the platform's gitstatus.json as it is"
      python3 - ${live.gitstatus} ${platformJSON} <<'EOF'
      import json, sys
      ours, theirs = (json.load(open(f)) for f in sys.argv[1:3])
      assert [e["repo"] for e in ours] == [e["repo"] for e in theirs], (ours, theirs)
      for o, t in zip(ours, theirs):
          o["url"], t["url"] = o["url"].lower(), t["url"].lower()
          if o["repo"] != "illumos-joyent":
              assert o == t, (o, t)
      print("ok   gitstatus.json from the pins: the platform's but for illumos-joyent and the URLs' case")
      EOF
      touch $out
    '';
  # build_live's tools: its checks pass on the manifest and the illumos build's proto area, as build_live runs them;
  # cryptpass hashes; builder runs (as far as wanting root: copying and owning the image's files is a root step).
  # tzcheck's check that the zoneinfo files the manifest makes hard links are hard links in the proto area cannot
  # hold in the store, which keeps no hard links: there each such pair has to be the same file's contents.
  liveTools = pkgs.runCommand "smartos-live-tools-check" { } ''
    t=${live.liveTools}/tools
    p=${live.illumosProto}
    rc=0; $t/tzcheck/tzcheck -f ${live.manifest}/manifest.gen -p $p >tz || rc=$?
    # everything but "hardlink mismatch: NAME / manifest: TARGET / proto: check manually" and the count
    awk '/^hardlink mismatch: / { name = $3; getline; target = $2; getline; print name, target; next }
      /^$/ || /^time zone errors found: / { next } { print "OTHER", $0 }' tz >links
    if grep "^OTHER" links; then exit 1; fi
    [ $rc = 0 ] || [ $rc = 60 ]
    while read name target; do
      cmp $p/usr/share/lib/zoneinfo/$name $p/usr/share/lib/zoneinfo/$target
    done <links
    echo "ok   tzcheck: no errors but $(wc -l <links) hard links, each the same contents in the proto area"
    $t/ucodecheck/ucodecheck -f ${live.manifest}/manifest.gen -p ${live.illumosProto}
    echo "ok   ucodecheck"
    $t/cryptpass secret | tee hash
    grep '^\$.' hash >/dev/null
    echo "ok   cryptpass"
    rc=0; $t/builder/builder >out || rc=$?
    [ $rc = 1 ] && grep -x "euid must be 0 to use this tool." out >/dev/null
    echo "ok   builder wants root"
    # with BUILDER_UNOWNED, without root: each file from the first search directory that has it (a symbolic link
    # there followed), modes as the manifest says, directories' last, and the links made; nothing owned
    mkdir -p a/usr/bin b/usr/bin img
    echo first >a/usr/bin/x; echo second >b/usr/bin/x; echo only-b >b/usr/bin/y; ln -s $PWD/b/usr/bin/y a/usr/bin/z
    printf '%s\n' "d usr 0755 root sys" "d usr/bin 0555 root bin" "f usr/bin/x 0555 root bin" \
      "f usr/bin/y 0444 bin bin" "f usr/bin/z 0400 root sys" "s usr/bin/sx=x" "h usr/bin/hx=usr/bin/x" >m
    BUILDER_UNOWNED=1 $t/builder/builder $PWD/m $PWD/img $PWD/a $PWD/b
    [ "$(cat img/usr/bin/x img/usr/bin/y img/usr/bin/z)" = "$(printf 'first\nonly-b\nonly-b')" ]
    [ ! -L img/usr/bin/z ] && [ "$(readlink img/usr/bin/sx)" = x ] && [ img/usr/bin/hx -ef img/usr/bin/x ]
    [ "$(stat -c %a img/usr img/usr/bin img/usr/bin/x img/usr/bin/y img/usr/bin/z | tr '\n' ' ')" = "755 555 555 444 400 " ]
    chmod -R u+w img
    echo "ok   builder without root (BUILDER_UNOWNED)"
    touch $out
  '';
  # builder's search directories: every file manifest.gen lists is in one, and the two that are in two stages are
  # taken from the stage the platform has them from (livesrc's sshd_config, illumos-extra's gzip's zcat)
  searchDirs = pkgs.runCommand "smartos-live-search-dirs-check" { } ''
    awk '$1 == "f" { print $2 }' ${live.manifest}/manifest.gen >files
    while read -r f; do
      found=
      for d in ${toString live.searchDirs}; do
        if [ -e "$d/$f" ]; then found=$d; break; fi
      done
      [ -n "$found" ] || { echo "FAIL $f is in none of them"; exit 1; }
      echo "$f $found"
    done <files >found
    grep -x "etc/ssh/sshd_config ${live.livesrc}" found
    cmp ${live.livesrc}/etc/ssh/sshd_config ${extra.platformReference}/etc/ssh/sshd_config
    grep -x "usr/bin/zcat ${live.extraJoin}" found
    readlink ${live.extraJoin}/usr/bin/zcat | grep "^${extra.gzip}/" >/dev/null
    echo "ok   all $(wc -l <files) files in the search directories; sshd_config from livesrc, zcat from gzip"
    touch $out
  '';
  # the SMF repositories: not reproducible byte for byte (sqlite 2), so what they configure, `svccfg archive`,
  # flattened to sorted lines (./smf-flatten.py: the order the repository lists things in is not the platform's),
  # against the platform's. Its manifest hashes are two MD5s, of a file's owner, size and time and of its contents:
  # here only the second is compared, as the import ran without root on the store's files (the platform's on the
  # image's); at boot a hash whose contents half matches is reconciled, not imported again.
  smf =
    let
      svccfg = "${pkgs.smartos-illumos.tools}/opt/onbld/bin/i386/svccfg";
    in
    pkgs.runCommand "smartos-live-smf-check" { nativeBuildInputs = [ pkgs.python3 ]; } ''
      archive() {
        cp $1 repo.db && chmod u+w repo.db
        SVCCFG_REPOSITORY=$PWD/repo.db SVCCFG_CONFIGD_PATH=/lib/svc/bin/svc.configd ${svccfg} archive >archive.xml
        rm repo.db
        grep -c '<service ' archive.xml >$2.services
        python3 ${./smf-flatten.py} archive.xml | sed -E 's/(propval=md5sum type=opaque value=)[0-9a-f]{32}/\1/' >$2
      }
      for r in etc/svc/repository.db:${live.smfRepository} usr/lib/brand/joyent-minimal/repository.db:${live.smfSeed}; do
        f=''${r%%:*} p=''${r#*:}
        archive ${extra.platformReference}/$f theirs
        archive $p/$f ours
        diff theirs ours
        echo "ok   $f configures what the platform's does ($(cat ours.services) services)"
      done
      touch $out
    '';
  # the whatis databases, made from the image's manual pages
  whatis =
    compare "whatis" live.whatis "printf '%s\\n' usr/share/man/whatis smartdc/man/whatis" ""
      "";
  # man.cf, made from the manifest by mancf
  man-cf = compare "man-cf" live.man-cf "echo usr/share/man/man.cf" "" "";

  # The local projects, each against the f entries of its own manifest (their manifest targets copy it as it is).
  # mdata-client: expected to differ in RUNPATH, gcc 10's here and pkgsrc's gcc 13's in theirs (pkgs/smartos-live).
  mdata-client =
    compareWith "IGNORE_RUNPATHS=1" "mdata-client" live.mdata-client (localManifest "mdata-client") ""
      "";
  # they run; the metadata socket is root's alone, so only as far as their usage messages
  mdata-client-use = pkgs.runCommand "smartos-live-mdata-client-use" { } ''
    for p in get put delete; do
      rc=0; ${live.mdata-client}/usr/sbin/mdata-$p 2>err || rc=$?
      cat err
      [ $rc = 3 ] && grep -q "^mdata-$p: Usage: .*mdata-$p <keyname>" err
    done
    echo "ok   mdata-get, mdata-put and mdata-delete run"
    touch $out
  '';
  kvm = compare "kvm" live.kvm (localManifest "kvm") "" "";
  # a driver, an mdb module and a devfsadm link module, which cannot be loaded in a zone: their entry points and CTF
  kvm-use = pkgs.runCommand "smartos-live-kvm-use" { } ''
    k=${live.kvm}
    for s in _init _info _fini; do
      /usr/bin/elfdump -s $k/usr/kernel/drv/amd64/kvm | grep "FUNC GLOB .* $s$" >/dev/null
    done
    /usr/bin/elfdump -s $k/usr/lib/mdb/kvm/amd64/kvm.so | grep "FUNC GLOB .* _mdb_init$" >/dev/null
    /usr/bin/elfdump -s $k/usr/lib/devfsadm/linkmod/JOY_kvm_link.so |
      grep "OBJT GLOB .* _devfsadm_create_reg$" >/dev/null
    for f in usr/kernel/drv/amd64/kvm usr/lib/mdb/kvm/amd64/kvm.so usr/lib/devfsadm/linkmod/JOY_kvm_link.so; do
      /usr/bin/elfdump -c $k/$f | grep "sh_name: *.SUNW_ctf" >/dev/null
    done
    echo "ok   kvm, kvm.so and JOY_kvm_link.so have their entry points and CTF"
    touch $out
  '';
  kbmd = compare "kbmd" live.kbmd (localManifest "kbmd") "" "";
  # pivy-tool, pivy-box, reset-piv and kbmadm run as far as their arguments (they need a PIV token or kbmd; kbmd
  # itself, run, starts)
  kbmd-use = pkgs.runCommand "smartos-live-kbmd-use" { } ''
    s=${live.kbmd}/usr/sbin
    $s/pivy-tool 2>&1 | tee out || true
    grep -x "pivy-tool: operation required" out >/dev/null
    $s/pivy-box 2>&1 | tee out || true
    grep -x "pivy-box: type and operation required" out >/dev/null
    $s/reset-piv -h 2>&1 | tee out || true
    grep -x "reset-piv: failed to parse guid '-h'" out >/dev/null
    $s/kbmadm -h 2>&1 | tee out || true
    grep "kbmadm: illegal option -- h$" out >/dev/null
    echo "ok   pivy-tool, pivy-box, reset-piv and kbmadm run"
    touch $out
  '';
  kvm-cmd = compare "kvm-cmd" live.kvm-cmd (localManifest "kvm-cmd") "" "";
  # QEMU 0.14.1: qemu-img makes, reads and converts an image; qemu-system-x86_64 runs as far as its version (KVM
  # itself is not in a zone); the mdb module has its entry point
  kvm-cmd-use = pkgs.runCommand "smartos-live-kvm-cmd-use" { } ''
    b=${live.kvm-cmd}/smartdc/bin
    $b/qemu-system-x86_64 -version | tee out
    grep "^QEMU emulator version 0.14.1 (qemu-kvm-devel)" out >/dev/null
    $b/qemu-img create -f qcow2 disk.qcow2 64M
    $b/qemu-img info disk.qcow2 | tee info
    grep -x "file format: qcow2" info >/dev/null && grep "^virtual size: 64M " info >/dev/null
    $b/qemu-img convert -O raw disk.qcow2 disk.raw
    [ $(wc -c <disk.raw) = 67108864 ]
    /usr/bin/elfdump -s ${live.kvm-cmd}/usr/lib/mdb/proc/amd64/qemu.so | grep "FUNC GLOB .* _mdb_init$" >/dev/null
    echo "ok   qemu-img round trip, qemu-system-x86_64 runs, qemu.so has _mdb_init"
    touch $out
  '';
  ur-agent = compare "ur-agent" live.ur-agent (localManifest "ur-agent") "" "";
  # its modules load in node 0.10
  ur-agent-use = pkgs.runCommand "smartos-live-ur-agent-use" { } ''
    ${node} -e '
      var m = process.argv[1];
      console.log(typeof require(m + "/amqp").createConnection, typeof require(m + "/triton-netconfig").isNicAdmin);
    ' ${live.ur-agent}/smartdc/node_modules | tee out
    grep -x "function function" out >/dev/null
    echo "ok   amqp and triton-netconfig load"
    touch $out
  '';

  # the node add-ons, loaded by a node 0.10 (the strap's; the platform's is the same 0.10.26) and used: those built
  # with nan (dtrace-provider, fs-ext, zonename) and the others; their libraries resolve as on the platform, on the
  # system's library path. And json, a node program.
  livesrc-use = pkgs.runCommand "smartos-live-src-use" { } ''
    m=${live.livesrc}/usr/node/0.10/node_modules
    ${node} -e '
      var m = process.argv[1];
      console.log("zonename", require(m + "/zonename").getzonename());
      var fs = require("fs"), fsext = require(m + "/fs-ext");
      fsext.flockSync(fs.openSync("lock", "w"), "exnb");
      console.log("flock ok");
      var p = require(m + "/dtrace-provider").createDTraceProvider("smartoslivetest");
      p.addProbe("probe", "int");
      p.enable();
      p.fire("probe", function () { return [1]; });
      console.log("dtrace-provider ok");
      console.log("qlocker", typeof require(m + "/qlocker").lock);
      var ks = new (require(m + "/kstat.node").Reader)({ module: "unix", name: "system_misc" }).read();
      console.log("kstat", ks[0].data.ncpus > 0);
      var n = 0, x = new (require(m + "/node-expat").Parser)("UTF-8");
      x.on("startElement", function () { n++; });
      x.parse("<a><b/><c/></a>", true);
      console.log("expat", n);
    ' $m | tee out
    /usr/bin/zonename | sed 's/^/zonename /' >expect
    printf '%s\n' "flock ok" "dtrace-provider ok" "qlocker function" "kstat true" "expat 3" >>expect
    diff expect out
    echo '{"a":{"b":1}}' | ${node} ${live.livesrc}/usr/bin/json a.b | grep -x 1 >/dev/null
    echo "ok   add-ons load and work; json runs"
    touch $out
  '';
}
