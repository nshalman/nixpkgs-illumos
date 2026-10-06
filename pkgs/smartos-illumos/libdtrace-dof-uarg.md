Subject: dtrace -G output depends on the address space layout of dtrace

Category: lib - userland libraries (libdtrace)

`dtrace -G` produces a different object from one run to the next when the
dtrace process runs with ASLR (e.g. in a zone or process with the aslr
security flag).  Compiling the same D program five times gives five
different objects; with ASLR disabled (`psecflags -s current,-aslr -e
/usr/sbin/dtrace ...`) the five are identical.  This defeats reproducible
builds of anything that ships USDT/ustack-helper DOF (node, perl, the gate's
own -G users).

The difference is confined to the dofa_uarg field of DOF_SECT_ACTDESC
entries.  dtrace_stmt_action() (dt_program.c) sets each action's
dtad_uarg to the address of its dtrace_stmtdesc_t:

	new->dtad_uarg = (uintptr_t)sdp;

and dtrace_dof_create() (dt_dof.c) copies that into the DOF:

	dofa[i].dofa_uarg = ap->dtad_uarg;

For DOF the consumer enables itself, this is by design: the kernel hands
the value back in dtrd_uarg, and libdtrace dereferences it (dt_map.c) or
compares it (dt_consume.c, dt_printf.c) to interpret the records.  But
dtrace_program_link() also calls dtrace_dof_create(), for DOF that goes
into an object and is loaded by other processes as helper DOF.  There the
value is a heap address of the dtrace process that built the object: it
means nothing (dtrace_helper_action_add() takes only the kind and DIFO of
each action, and dtrace_helper_slurp() ignores ECBs other than
dtrace:helper:ustack:), and under ASLR it changes from run to run.

Reproduce (ustack helper; any action in a -G program will do):

	$ cat h.d
	dtrace:helper:ustack:
	{
		"@helped"
	}
	$ psecflags $$ | grep E:
		E:	aslr
	$ for i in 1 2 3 4 5; do dtrace -32 -G -s h.d -o h.o && cksum <h.o; done

gives five different checksums.

Proposed fix: dtrace_program_link() writes zero in dofa_uarg.  A private
dt_dof_create(dtp, pgp, flags, uarg) does the work, with the public
dtrace_dof_create() calling it with uarg = B_TRUE (unchanged behaviour for
live enablings and for dtrace -A), and dtrace_program_link() with B_FALSE.

Related: #729 and #13240 (wsdiff ignores .SUNW_dof) attribute the
variation in .SUNW_dof to ftok(3C) alone; this is a second, independent
source.  (Anonymous enablings written by dtrace -A carry the same
pointers; they are left as they are, since a later dtrace -a compares
them to group records by statement.)
