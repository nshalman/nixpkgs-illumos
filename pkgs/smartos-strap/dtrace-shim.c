/*
 * dtrace-shim.so, preloaded (LD_PRELOAD_64) into the platform's dtrace when a build runs it, so that what dtrace -G
 * writes depends neither on the build host nor on the inode numbers of the build's files:
 *   - uname() gives the nodename "illumos" and the version $DTRACE_SHIM_VERSION (default "joyent") in place of the
 *     host's: dtrace records its utsname in the DOF it writes (libdtrace dt_open.c, the DOF's utsname section);
 *   - ftok() gives a key made of the path alone (FNV-1a): libdtrace dt_link.c names the alias of a probe's static
 *     function $dtrace<key>.<function>, key = ftok(object, 0), which is made of the object's inode and device.
 *     The key only has to tell apart the objects linked together, which a build names by distinct paths.
 *   - dtrace_program_link(), which links each object dtrace -G writes, zeroes the dofa_uargs of the actions in it
 *     afterwards (./dof-zero-uarg.c): heap addresses of the dtrace process, which differ between build hosts'
 *     dtraces (and from one run to the next under ASLR). It is given the very file dtrace names, whichever way the
 *     command line names it (-o, X.d's X.o, d.out).
 */
#include <sys/types.h>
#include <sys/ipc.h>
#include <sys/utsname.h>
#include <dlfcn.h>
#include <dtrace.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

int
uname(struct utsname *u)
{
	static int (*real)(struct utsname *);
	const char *version = getenv("DTRACE_SHIM_VERSION");
	int r;

	if (real == NULL)
		real = (int (*)(struct utsname *))dlsym(RTLD_NEXT, "uname");
	if ((r = real(u)) < 0)
		return (r);
	/* the DOF holds each field whole: none of the host's string may be left after ours */
	(void) memset(u->nodename, 0, sizeof (u->nodename));
	(void) memset(u->version, 0, sizeof (u->version));
	(void) strlcpy(u->nodename, "illumos", sizeof (u->nodename));
	(void) strlcpy(u->version, version != NULL ? version : "joyent", sizeof (u->version));
	return (r);
}

key_t
ftok(const char *path, int id)
{
	uint32_t h = 2166136261u;

	for (; *path != '\0'; path++) {
		h ^= (unsigned char)*path;
		h *= 16777619u;
	}
	h ^= (uint32_t)(id & 0xff);
	return ((key_t)(h & 0x7fffffff));
}

extern int dof_zero_uarg(const char *);

int
dtrace_program_link(dtrace_hdl_t *dtp, dtrace_prog_t *pgp, uint_t dflags, const char *file, int objc,
    char *const objv[])
{
	static int (*real)(dtrace_hdl_t *, dtrace_prog_t *, uint_t, const char *, int, char *const []);
	int r;

	if (real == NULL)
		real = (int (*)(dtrace_hdl_t *, dtrace_prog_t *, uint_t, const char *, int, char *const []))
		    dlsym(RTLD_NEXT, "dtrace_program_link");
	if ((r = real(dtp, pgp, dflags, file, objc, objv)) != 0)
		return (r);
	return (dof_zero_uarg(file));
}
