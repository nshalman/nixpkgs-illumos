/*
 * dof_zero_uarg(FILE): zero the dofa_uarg of every action in the DOF of FILE, an object dtrace -G wrote, in place; a
 * FILE that is not an ELF object, or has no DOF, is left as it is. ./dtrace-shim.c calls it on each object dtrace -G
 * writes; built with DOF_ZERO_UARG_MAIN it is the command dof-zero-uarg FILE.
 *
 * libdtrace's dtrace_stmt_action() sets each action's dtad_uarg to the address of its statement in the dtrace
 * process's heap, and dtrace_dof_create() copies it into the DOF, also for dtrace -G (dtrace_program_link()), whose
 * DOF no process ever reads it from: the kernel takes only the kind and DIFO of each action of a helper. The address
 * differs from one run to the next under ASLR, and between build hosts' dtraces without it. illumos' own fix
 * (../smartos-illumos/libdtrace-dof-uarg.patch) writes zero there; this does the same afterwards for a build
 * host's dtrace.
 */
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <sys/dtrace.h>
#include <fcntl.h>
#include <gelf.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

/* zero the uargs of the DOF of SIZE bytes at DOF; -1 if it is not well formed */
static int
zero(char *dof, uint64_t size)
{
	dof_hdr_t *h = (dof_hdr_t *)dof;
	uint_t i, j;

	if (size < sizeof (*h) || h->dofh_ident[DOF_ID_MAG0] != DOF_MAG_MAG0 ||
	    h->dofh_ident[DOF_ID_MAG1] != DOF_MAG_MAG1 || h->dofh_ident[DOF_ID_MAG2] != DOF_MAG_MAG2 ||
	    h->dofh_ident[DOF_ID_MAG3] != DOF_MAG_MAG3 || h->dofh_secsize < sizeof (dof_sec_t) ||
	    h->dofh_secoff > size || (uint64_t)h->dofh_secnum * h->dofh_secsize > size - h->dofh_secoff)
		return (-1);
	for (i = 0; i < h->dofh_secnum; i++) {
		dof_sec_t *s = (dof_sec_t *)(dof + h->dofh_secoff + (uint64_t)i * h->dofh_secsize);
		dof_actdesc_t *a;

		if (s->dofs_type != DOF_SECT_ACTDESC)
			continue;
		if (s->dofs_offset > size || s->dofs_size > size - s->dofs_offset)
			return (-1);
		a = (dof_actdesc_t *)(dof + s->dofs_offset);
		for (j = 0; j < s->dofs_size / sizeof (*a); j++)
			a[j].dofa_uarg = 0;
	}
	return (0);
}

/* 0, or -1 with the reason on standard error */
int
dof_zero_uarg(const char *path)
{
	struct stat st;
	Elf *e = NULL;
	Elf_Scn *scn = NULL;
	GElf_Shdr sh;
	char *map = MAP_FAILED;
	int fd, r = 0;

	if ((fd = open(path, O_RDWR)) < 0 || fstat(fd, &st) < 0) {
		perror(path);
		if (fd >= 0)
			(void) close(fd);
		return (-1);
	}
	(void) elf_version(EV_CURRENT);
	if (st.st_size == 0 || (e = elf_begin(fd, ELF_C_READ, NULL)) == NULL || elf_kind(e) != ELF_K_ELF)
		goto done;
	if ((map = mmap(NULL, st.st_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0)) == MAP_FAILED) {
		perror(path);
		r = -1;
		goto done;
	}
	while ((scn = elf_nextscn(e, scn)) != NULL) {
		if (gelf_getshdr(scn, &sh) == NULL || sh.sh_type != SHT_SUNW_dof)
			continue;
		if (sh.sh_offset > (uint64_t)st.st_size || sh.sh_size > (uint64_t)st.st_size - sh.sh_offset ||
		    zero(map + sh.sh_offset, sh.sh_size) != 0) {
			(void) fprintf(stderr, "dof-zero-uarg: %s: DOF not well formed\n", path);
			r = -1;
		}
	}
	if (munmap(map, st.st_size) != 0) {
		perror(path);
		r = -1;
	}
done:
	if (e != NULL)
		(void) elf_end(e);
	if (close(fd) != 0) {
		perror(path);
		r = -1;
	}
	return (r);
}

#ifdef DOF_ZERO_UARG_MAIN
int
main(int argc, char **argv)
{
	if (argc != 2) {
		(void) fprintf(stderr, "usage: dof-zero-uarg FILE\n");
		return (2);
	}
	return (dof_zero_uarg(argv[1]) == 0 ? 0 : 1);
}
#endif
