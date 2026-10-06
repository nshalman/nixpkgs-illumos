#!/usr/bin/env bash
#
# smartos-strap.platformDtrace, the platform's dtrace with pkgs/smartos-strap/dtrace-shim.c preloaded, against the
# platform's dtrace itself: dtrace -G on two copies of one object (a probe in a static function, which dtrace -G
# names $dtrace<key>.<function> with key = ftok(object): the object's inode) at the same path in turn, as two builds
# would. Through platformDtrace the two results are the same file, and name neither this host (uname -n) nor its
# platform (uname -v); $DTRACE_SHIM_VERSION is the version they name instead. The platform's own dtrace gives two
# different files naming both (so the test shows something). Nor do they hold what follows the shim's strings in the
# whole utsname fields the DOF keeps: the rest of the host's, were the shim to leave it, which a search for the whole
# node name or platform does not find; uname() through the shim, in a program of its own, shows the fields all zeros
# after its strings. And a ustack helper (as node's v8ustack.d) compiled by
# dtrace -C -G five times: the platform's dtrace, under the address space layout randomization processes here get,
# lays its DOF out differently from one run to the next; through platformDtrace the five are the same.
#
# usage: dtrace-shim.sh PKGS-FILE   (on illumos, for dtrace; nix-build on PATH)

set -uo pipefail

pkgsFile=${1:?usage: $0 PKGS-FILE}
tmp=$(mktemp -d)
# leave $tmp first, as illumos' rm does not remove the current directory
trap 'cd / && rm -rf "$tmp"' EXIT

pass=0 fail=0
ok()  { echo "PASS: $1"; pass=$((pass+1)); }
bad() { echo "FAIL: $1"; fail=$((fail+1)); }

host=$(uname -n) version=$(uname -v)
dtraceDir=$(nix-build "$pkgsFile" -A smartos-strap.platformDtrace --no-out-link) || { bad "no platformDtrace"; exit 1; }
cc=$(nix-build "$pkgsFile" -A smartos-strap.gcc10-illumos --no-out-link)/bin/gcc || { bad "no compiler"; exit 1; }

cd "$tmp"
echo 'provider shimtest { probe fired(int); };' >prov.d
cat >t.c <<'EOF'
extern void __dtrace_shimtest___fired(int);
static int counter;
static void tick(void) { __dtrace_shimtest___fired(++counter); }
int main(void) { tick(); return 0; }
EOF
"$cc" -m64 -c -o t.o t.c || { bad "cannot compile"; exit 1; }

# g DTRACE OUT: dtrace -G on a fresh copy (a new inode) of t.o at the same path, writing dof.o (a build gives it the
# same name each time, which it records): the object it writes (the DOF) in OUT, the input it rewrites (the probe
# sites, and the aliases) in OUT.in
g() {
    rm -f obj.o
    cp t.o obj.o
    cp t.o keep-inode-$RANDOM.o   # takes the inode the next copy would have reused
    rm -f dof.o
    "$1" -G -64 -s prov.d -o dof.o obj.o 2>"$2.err" && cp dof.o "$2" && cp obj.o "$2.in"
}

if g /usr/sbin/dtrace plain1.o && g /usr/sbin/dtrace plain2.o && ! cmp -s plain1.o.in plain2.o.in &&
    grep -qF "$host" plain1.o; then
    ok "the platform's dtrace: two runs differ, and name the host"
else
    bad "the platform's dtrace does not show the problem: the test shows nothing"; cat plain1.o.err
fi

export DTRACE_SHIM_VERSION=joyent_test
if g "$dtraceDir/bin/dtrace" shim1.o && g "$dtraceDir/bin/dtrace" shim2.o; then
    ok "platformDtrace runs dtrace -G"
else
    bad "platformDtrace fails"; cat shim1.o.err shim2.o.err
fi
if cmp -s shim1.o shim2.o && cmp -s shim1.o.in shim2.o.in; then
    ok "platformDtrace: two runs give the same object"
else
    bad "platformDtrace: two runs differ"; cmp -l shim1.o shim2.o | head -3 | sed 's/^/    /'
fi
if ! grep -qF "$host" shim1.o && ! grep -qF "$version" shim1.o && grep -qF joyent_test shim1.o; then
    ok "platformDtrace: neither the host nor its platform, but DTRACE_SHIM_VERSION"
else
    bad "platformDtrace: names the host or its platform, or not DTRACE_SHIM_VERSION"
fi
# The DOF holds utsname's fields whole (SYS_NMLN bytes each), so what the shim leaves of the host's after its own
# string is in it too: the host's node name past "illumos\0" (its first 8 bytes), its platform's stamp past
# "joyent\0" (joyent_<stamp>: the stamp from its 8th byte on).
if { [ ${#host} -gt 8 ] && grep -qF -e "${host:8}" shim1.o; } || { [ ${#version} -gt 8 ] && grep -qF -e "${version:8}" shim1.o; }; then
    bad "platformDtrace: the rest of the host's node name or platform is in the object"
else
    ok "platformDtrace: nothing of the host's node name or platform after the shim's"
fi

# uname() through the shim, in a program of its own: each field it sets is all zeros after its string
cat >u.c <<'EOF'
#include <stdio.h>
#include <string.h>
#include <sys/utsname.h>
/* the bytes of FIELD after its string that are not zero */
static int
rest(const char *field, size_t size)
{
	size_t i, n = 0;

	for (i = strlen(field) + 1; i < size; i++)
		n += field[i] != '\0';
	return ((int)n);
}
int
main(void)
{
	struct utsname u;

	if (uname(&u) < 0)
		return (2);
	printf("%s %s %d %d\n", u.nodename, u.version, rest(u.nodename, sizeof (u.nodename)),
	    rest(u.version, sizeof (u.version)));
	return (rest(u.nodename, sizeof (u.nodename)) + rest(u.version, sizeof (u.version)) != 0);
}
EOF
"$cc" -m64 -o u u.c || { bad "cannot compile u.c"; exit 1; }
if out=$(DTRACE_SHIM_VERSION=v LD_PRELOAD_64=$dtraceDir/lib/dtrace-shim.so ./u) && [ "${out%% *}" = illumos ]; then
    ok "the shim's uname(): node name and version all zeros after its strings ($out)"
else
    bad "the shim's uname() leaves bytes of the host's after its strings: $out"
fi

cat >h.d <<'EOF'
dtrace:helper:ustack:
{
	this->a = copyin(arg1, 8);
	this->c = *(uint32_t *)this->a + 8;
	this->s = strjoin("frame ", lltostr(this->c));
	this->t = this->c > 4 ? strjoin(this->s, " big") : strjoin(this->s, " small");
}
dtrace:helper:ustack:
/this->c == 7/
{
	this->t = strjoin(this->t, " seven");
}
dtrace:helper:ustack:
{
	substr(this->t, 0, 20)
}
EOF
# h DTRACE: the distinct objects five runs of dtrace -C -G on h.d give
h() {
    for i in 1 2 3 4 5; do
        rm -f h.o
        "$1" -32 -C -G -s h.d -o h.o 2>h.err && cksum <h.o
    done | sort -u | wc -l
}
if [ "$(h /usr/sbin/dtrace)" -gt 1 ]; then
    ok "the platform's dtrace: a ustack helper's DOF differs from run to run"
else
    bad "the platform's dtrace gives one ustack helper DOF: the test shows nothing"; cat h.err
fi
if [ "$(h "$dtraceDir/bin/dtrace")" = 1 ]; then
    ok "platformDtrace: a ustack helper's DOF is the same in every run"
else
    bad "platformDtrace: a ustack helper's DOF differs from run to run"; cat h.err
fi

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
