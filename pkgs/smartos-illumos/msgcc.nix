# The AST message tools (msgcc, msgcpp, msgcvt, msggen, msgget) that the nightly's _msg pass runs as $(ASTBINDIR)/msgcc
# to build the AST libraries' message catalogs (usr/src/cmd/ast/Makefile.astmsg). smartos-live takes them from
# pkgsrc's smartos-build-tools (ASTBINDIR=/opt/local/ast/bin), whose binaries were copied from a SmartOS proto area
# in 2013; there is no recipe to follow there. They are the gate's own usr/src/cmd/ast/msgcc, so they are built here
# from the same illumos-joyent tree, after `dmake setup`, with what they link against (cmd/ast's Makefile: msgcc needs
# libast and libpp; libast needs tools). `install` builds no catalogs (that is the separate _msg pass), so this needs
# no msgcc of its own.
#
# In the nightly, libast links against the libc, libm and libsocket built before it into the proto area, and the
# gate's link checks (LDCHECKS: -z assert-deflib, -z fatal-warnings) fail a link that takes them from the default
# path instead. Here they are the build host's, as for a native tool: NATIVE_LIBS, the gate's list of "libraries we
# expect to use natively on the build machine", names them (set after setup, whose tools add their own).
#
# The output is the proto area's usr/ast/bin, as the gate builds it: msgcpp and the others load libast.so.1 and
# libpp.so.1 from the build host's /usr/lib, as they do in smartos-live's build zone.
{
  mkBldenvStep,
  setup,
}:

mkBldenvStep {
  pname = "smartos-illumos-msgcc";
  description = "illumos-joyent's AST message catalog tools (msgcc and friends)";
  dir = "usr/src";
  command =
    "dmake setup && cd cmd/ast && export NATIVE_LIBS='libc.so libm.so libsocket.so' && "
    + "for d in tools libast libpp msgcc; do (cd \\$d && dmake install) || exit 1; done";

  extra.postUnpack = setup.postUnpack;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/usr
    cp -r proto/usr/ast $out/usr/ast
    runHook postInstall
  '';

  # msgcc run as Makefile.astmsg runs it, on msgcc.tst's first case: the .mso has the strings its error() and
  # errormsg() calls translate, and the linked .msg, with its $translation line removed, is a catalog gencat accepts.
  installCheckPhase = ''
    runHook preInstallCheck
    b=$out/usr/ast/bin
    for t in msgcc msgcpp msgcvt msggen msgget; do
      test -x $b/$t || { echo "missing $b/$t"; exit 1; }
    done
    mkdir ic && cd ic
    printf '%s\n' '#include <foo-bar.h>' 'void f(void)' '{' '#if 0' '	error(1, "foo bar");' '#else' \
      '	errormsg(locale, 2, "%s: bar foo");' '#endif' '}' >t.c
    msgcc() { env PATH="$b:/bin:/usr/bin" /usr/bin/ksh93 $b/msgcc "$@"; }
    msgcc -M-set=ast -c t.c -o t.mso
    printf '%s\n' 'str "foo bar"' 'str "%s: bar foo"' | diff - t.mso
    msgcc -M-set=ast -o t.msg t.mso
    sed 's/^$translation msgcc .*//' <t.msg | /usr/bin/gencat t.cat -
    grep -F '%s: bar foo' t.msg >/dev/null
    test -s t.cat
    runHook postInstallCheck
  '';
}
