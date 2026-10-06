#!/usr/bin/env perl
#
# normalize-zips.pl DIR...: each zip archive under the DIRs (.jar, .jmod, .zip, .sym; symbolic links not followed)
# with the time of every entry made SOURCE_DATE_EPOCH and its owner and group 0. The jar and jmod tools of openjdk
# 11, and zip, record each file's modification time (and zip its owner), which differ from one build to the next and
# between build users. Only fixed-size fields change, so nothing moves:
#   - each entry's DOS time and date, in its local header and in the central directory: SOURCE_DATE_EPOCH in UTC
#     (DOS times start at 1980; an earlier time is 1980-01-01 00:00);
#   - its extended timestamp extra field (0x5455, zip's), each time it holds;
#   - its Unix owner extra field (0x7875, zip's), uid and gid.
# The central directory is found from the end record, so data before the archive (a jmod's "JM" header) is allowed
# for. Zip64 archives are refused. Files with these names that are not zip archives are left as they are.

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

        $pos += 46 + $nlen + $xlen + $clen;
    }
    $pos == $eocd or fail("central directory ends at $pos, the end record is at $eocd");

    my $mode = (stat($path))[2] & 07777;
    chmod($mode | 0200, $path) or fail($!);
    open(my $out, '>:raw', $path) or fail($!);
    print $out $data;
    close($out) or fail($!);
    chmod($mode, $path) or fail($!);
}

find({ no_chdir => 1, wanted => sub { normalize($_) if -f $_ && !-l $_ && /\.(jar|jmod|zip|sym)$/ } }, @ARGV);
