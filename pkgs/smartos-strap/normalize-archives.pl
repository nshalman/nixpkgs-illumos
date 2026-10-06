#!/usr/bin/env perl
#
# normalize-archives.pl DIR...: each archive (ar) under the DIRs, symbolic links not followed, with the date of every
# member header made SOURCE_DATE_EPOCH and its owner and group 0. The platform's ar has no deterministic mode: it
# records each member file's modification time, owner and group, which differ from one build to the next (the time)
# and between build users (nixbld<N>'s uid). A header is 60 bytes of fixed fields (name 16, date 12, uid 6, gid 6,
# mode 8, size 10, "`\n"), so nothing else moves: the symbol table's offsets stay right. A field left blank (as ar
# leaves some in its own members, the symbol table and the long-name table) is left blank. Files named .a that are
# not archives are left as they are.

use strict;
use warnings;
use File::Find;

my $epoch = $ENV{SOURCE_DATE_EPOCH};
defined $epoch && $epoch =~ /^\d+$/ or die "normalize-archives.pl: SOURCE_DATE_EPOCH is not set to a time\n";

# field VALUE WIDTH: VALUE left-justified in WIDTH, as ar writes it
sub field { my ($v, $w) = @_; return sprintf("%-${w}s", $v); }

sub normalize {
    my ($path) = @_;
    open(my $in, '<:raw', $path) or die "normalize-archives.pl: $path: $!\n";
    local $/;
    my $data = <$in>;
    close($in);
    return unless substr($data, 0, 8) eq "!<arch>\n";

    my $pos = 8;
    while ($pos + 60 <= length($data)) {
        my $hdr = substr($data, $pos, 60);
        substr($hdr, 58, 2) eq "`\n" or die "normalize-archives.pl: $path: no member header at $pos\n";
        my $size = substr($hdr, 48, 10);
        $size =~ /^\s*(\d+)\s*$/ or die "normalize-archives.pl: $path: bad member size at $pos\n";
        $size = $1;
        substr($hdr, 16, 12) = field($epoch, 12) if substr($hdr, 16, 12) =~ /\S/;
        substr($hdr, 28, 6) = field(0, 6) if substr($hdr, 28, 6) =~ /\S/;
        substr($hdr, 34, 6) = field(0, 6) if substr($hdr, 34, 6) =~ /\S/;
        substr($data, $pos, 60) = $hdr;
        $pos += 60 + $size + ($size % 2);
    }
    $pos == length($data) or die "normalize-archives.pl: $path: members end at $pos, the file at " . length($data) . "\n";

    my $mode = (stat($path))[2] & 07777;
    chmod($mode | 0200, $path) or die "normalize-archives.pl: $path: $!\n";
    open(my $out, '>:raw', $path) or die "normalize-archives.pl: $path: $!\n";
    print $out $data;
    close($out) or die "normalize-archives.pl: $path: $!\n";
    chmod($mode, $path) or die "normalize-archives.pl: $path: $!\n";
}

find({ no_chdir => 1, wanted => sub { normalize($_) if -f $_ && !-l $_ && /\.a$/ } }, @ARGV);
