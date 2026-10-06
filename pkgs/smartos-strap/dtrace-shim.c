/*
 * dtrace-shim.so, preloaded (LD_PRELOAD_64) into the platform's dtrace when a build runs it, so that what dtrace -G
 * writes depends neither on the build host nor on the inode numbers of the build's files:
 *   - uname() gives the nodename "illumos" and the version $DTRACE_SHIM_VERSION (default "joyent") in place of the
 *     host's: dtrace records its utsname in the DOF it writes (libdtrace dt_open.c, the DOF's utsname section);
 *   - ftok() gives a key made of the path alone (FNV-1a): libdtrace dt_link.c names the alias of a probe's static
 *     function $dtrace<key>.<function>, key = ftok(object, 0), which is made of the object's inode and device.
 * The key only has to tell apart the objects linked together, which a build names by distinct paths.
 */
#include <sys/types.h>
#include <sys/ipc.h>
#include <sys/utsname.h>
#include <dlfcn.h>
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
