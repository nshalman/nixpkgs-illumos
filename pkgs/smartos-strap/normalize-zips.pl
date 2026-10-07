#!/usr/bin/env perl
#
# normalize-zips.pl DIR...: each zip archive under the DIRs (.jar, .jmod, .zip, .sym; symbolic links not followed)
# with the time of every entry made SOURCE_DATE_EPOCH, its owner and group 0, and its entries in order of name. The
# jar and jmod tools of openjdk 11, and zip, record each file's modification time (and zip its owner), which differ from
# one build to the next and between build users, and take a directory's files in the order the file system gives,
# which differs between hosts. In each entry:
#   - each entry's DOS time and date, in its local header and in the central directory: SOURCE_DATE_EPOCH in UTC
#     (DOS times start at 1980; an earlier time is 1980-01-01 00:00);
#   - its extended timestamp extra field (0x5455, zip's), each time it holds;
#   - its Unix owner extra field (0x7875, zip's), uid and gid.
# The entries are then written again in order of name (a jar's META-INF/ and META-INF/MANIFEST.MF first), each local
# header and its data as they were, the central directory's offsets made to match. The central directory is found from
# the end record, so data before the archive (a jmod's "JM" header) is kept; an archive whose entries do not fill the
# space before the central directory exactly, and a zip64 archive, are refused. Files with these names that are not
# zip archives are left as they are.

use strict;
use warnings;
use File::Find;

my $epoch = $ENV{SOURCE_DATE_EPOCH};
defined $epoch && $epoch =~ /^\d+$/ or die "normalize-zips.pl: SOURCE_DATE_EPOCH is not set to a time\n";
my ($sec, $min, $hour, $mday, $mon, $year) = gmtime($epoch < 315532800 ? 315532800 : $epoch);
my $dostime = ($hour << 11) | ($min << 5) | int($sec / 2);
my $dosdate = (($year + 1900 - 1980) << 9) | (($mon + 1) << 5) | $mday;

my $path;
sub fail { die "normalize-zips.pl: $path: @_\n"; }

# extras DATA POS LEN LOCAL: the extra fields at POS..POS+LEN of DATA (a reference) with their times and owners set
sub extras {
    my ($data, $pos, $len, $local) = @_;
    my $end = $pos + $len;
    while ($pos + 4 <= $end) {
        my ($tag, $size) = unpack('v v', substr($$data, $pos, 4));
        my $at = $pos + 4;
        $at + $size <= $end or fail("extra field past its end at $pos");
        if ($tag == 0x5455 && $size >= 1) {
            # flags, then the times the flags name: in a local header each one present, in the central directory
            # the modification time alone
            my $flags = unpack('C', substr($$data, $at, 1));
            my $n = $local ? (($flags & 1) + (($flags >> 1) & 1) + (($flags >> 2) & 1)) : ($flags & 1);
            for my $i (0 .. $n - 1) {
                my $t = $at + 1 + 4 * $i;
                last if $t + 4 > $at + $size;
                substr($$data, $t, 4) = pack('V', $epoch);
            }
        } elsif ($tag == 0x7875 && $size >= 1) {
            # version 1, then the uid's size and uid, the gid's size and gid
            my $p = $at + 1;
            for (1 .. 2) {
                last if $p + 1 > $at + $size;
                my $n = unpack('C', substr($$data, $p, 1));
                $p + 1 + $n <= $at + $size or fail("owner extra field too short at $pos");
                substr($$data, $p + 1, $n) = "\0" x $n;
                $p += 1 + $n;
            }
        }
        $pos = $at + $size;
    }
}

sub normalize {
    ($path) = @_;
    open(my $in, '<:raw', $path) or fail($!);
    local $/;
    my $data = <$in>;
    close($in);

    # the end record: the last "PK\5\6" with its comment reaching to the end
    my $eocd = -1;
    for (my $p = length($data) - 22; $p >= 0 && $p >= length($data) - 22 - 65535; $p--) {
        next unless substr($data, $p, 4) eq "PK\5\6";
        my $clen = unpack('v', substr($data, $p + 20, 2));
        if ($p + 22 + $clen == length($data)) { $eocd = $p; last; }
    }
    return if $eocd < 0;
    my ($entries, $cdsize, $cdoff) = unpack('x10 v V V', substr($data, $eocd, 22));
    fail("zip64 archive") if $entries == 0xffff || $cdoff == 0xffffffff || $cdsize == 0xffffffff;
    my $base = $eocd - $cdsize - $cdoff;
    $base >= 0 or fail("central directory before the start of the file");

    my $pos = $base + $cdoff;
    my @entries;
    for my $i (1 .. $entries) {
        substr($data, $pos, 4) eq "PK\1\2" or fail("no central directory entry $i at $pos");
        my ($nlen, $xlen, $clen) = unpack('v v v', substr($data, $pos + 28, 6));
        my $lho = unpack('V', substr($data, $pos + 42, 4));
        substr($data, $pos + 12, 4) = pack('v v', $dostime, $dosdate);
        extras(\$data, $pos + 46 + $nlen, $xlen, 0);

        my $l = $base + $lho;
        substr($data, $l, 4) eq "PK\3\4" or fail("no local header for entry $i at $l");
        my ($lnlen, $lxlen) = unpack('v v', substr($data, $l + 26, 4));
        substr($data, $l + 10, 4) = pack('v v', $dostime, $dosdate);
        extras(\$data, $l + 30 + $lnlen, $lxlen, 1);

        # the entry's data, and its data descriptor where general purpose bit 3 says there is one (12 bytes, or 16
        # with its signature)
        my $flags = unpack('v', substr($data, $pos + 8, 2));
        my $csize = unpack('V', substr($data, $pos + 20, 4));
        my $llen = 30 + $lnlen + $lxlen + $csize;
        $llen += substr($data, $l + $llen, 4) eq "PK\7\10" ? 16 : 12 if $flags & 8;
        push @entries, {
            name => substr($data, $pos + 46, $nlen),
            cd => substr($data, $pos, 46 + $nlen + $xlen + $clen),
            local => substr($data, $l, $llen),
        };
        $pos += 46 + $nlen + $xlen + $clen;
    }
    $pos == $eocd or fail("central directory ends at $pos, the end record is at $eocd");
    my $locals = 0;
    $locals += length($_->{local}) for @entries;
    $locals == $cdoff or fail("the entries take $locals bytes before the central directory, not $cdoff");

    # the entries in order of name, as jar and jmod take them from directories in the order the file system gives;
    # a jar's META-INF/ and MANIFEST.MF first, where JarInputStream looks for the manifest
    my %first = ("META-INF/" => 0, "META-INF/MANIFEST.MF" => 1);
    my $i = 0;
    $_->{index} = $i++ for @entries;
    @entries = sort {
        ($first{$a->{name}} // 2) <=> ($first{$b->{name}} // 2)
            || $a->{name} cmp $b->{name}
            || $a->{index} <=> $b->{index}
    } @entries;
    my ($body, $cd) = ("", "");
    for my $e (@entries) {
        my $c = $e->{cd};
        substr($c, 42, 4) = pack('V', length($body));
        $cd .= $c;
        $body .= $e->{local};
    }
    my $end = substr($data, $eocd);
    substr($end, 16, 4) = pack('V', length($body));
    $data = substr($data, 0, $base) . $body . $cd . $end;

    my $mode = (stat($path))[2] & 07777;
    chmod($mode | 0200, $path) or fail($!);
    open(my $out, '>:raw', $path) or fail($!);
    print $out $data;
    close($out) or fail($!);
    chmod($mode, $path) or fail($!);
}

find({ no_chdir => 1, wanted => sub { normalize($_) if -f $_ && !-l $_ && /\.(jar|jmod|zip|sym)$/ } }, @ARGV);
