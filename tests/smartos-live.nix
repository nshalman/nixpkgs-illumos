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
in
{
  # f entries only, as for illumos-extra (tests/smartos-extra.nix): the builder makes the links. src's manifest is
  # what src/Makefile's manifest target writes: src/manifest and the vm and fw tests and examples, which it lists with
  # git ls-files (here with find, the source having no .git). Not this stage's, so left out: src/manifest's
  # 0-devpro-stamp section (projects/devpro installs those), and of man's, man.cf (made from the whole manifest by
  # tools/mancf) and, of src's, var/log/syslog (made empty in the image by tools/build_live).
  #
  # Expected to differ: the dist.shasum npm writes into fs-ext's package.json, a sha1 of the tarball npm makes from
  # the git archive of the pinned commit (npm 1.4.3's addRemoteGit, then addTmpTarball). Why theirs differs is not
  # known: ours is the same from one build to the next, and is not the sha1 of that git archive gzipped by the strap
  # node's zlib as addRemoteGit does, so the tarball hashed is another; their git's archive may differ from nixpkgs'.
  # The rest of the file, _resolved and _from (what was installed) among it, is compared apart.
  livesrc =
    pkgs.runCommand "smartos-live-src-compare" { } ''
      src=${live.smartosLive}/src
      fsExtJson=usr/node/0.10/node_modules/fs-ext/package.json
      {
        awk '/^# / { section = $0 } $1 == "f" && section != "# 0-devpro-stamp" { print $2 }' $src/manifest |
          grep -vx var/log/syslog
        awk '$1 == "f" { print $2 }' ${live.smartosLive}/man/manifest | grep -vx usr/share/man/man.cf
        # and the pages man installs over illumos-extra's, which illumos-extra's manifest lists
        awk '/^MAN_FILES =/ { on = 1; next } on && NF == 0 { on = 0 } on { print $1 }' ${live.smartosLive}/man/Makefile
        (cd $src/vm && find tests \( -type f -o -type l \) -print) | grep -v /testdata/ | sed 's|^|usr/vm/test/|'
        (cd $src/vm/tests && find testdata \( -type f -o -type l \) -print) | sed 's|^|usr/vm/test/|'
        (cd $src/fw/test && find integration \( -type f -o -type l \) -print) | sed 's|^|usr/fw/test/|'
        (cd $src/fw/etc && find examples \( -type f -o -type l \) -print) | sed 's|^|usr/fw/etc/|'
      } | sort -u >list
      IGNORE_MODES=1 PATH_LIST=$PWD/list GCC_LIB=${gcc10-illumos.lib} GCC_OUT=${gcc10-illumos} \
        bash ${./strap-compare.sh} ${extra.platformReference} ${live.livesrc} '.' "^$fsExtJson$" >report 2>&1 ||
        { cat report; exit 1; }
      cat report
      diff <(grep -v '"shasum": ' ${extra.platformReference}/$fsExtJson) <(grep -v '"shasum": ' ${live.livesrc}/$fsExtJson)
      echo "ok   $fsExtJson but for dist.shasum" | tee -a report
      cp report $out
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
