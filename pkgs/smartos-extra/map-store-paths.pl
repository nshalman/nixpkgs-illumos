#!/usr/bin/env perl
# map-store-paths.pl DIR: in every regular file under DIR, replace the store paths of this build's inputs by the
# places they stand for, each replacement as long as the path it replaces, so that binaries keep their layout; prints
# the files it changed.
#
#   the nightly (smartos-illumos-nightly-*), whose proto area follows as /proto: slashes, leaving /proto/...
#   gcc 10 (gcc-illumos-*, compiler or runtime libraries): /usr/gcc/10, then slashes
#   a platform package (smartos-extra-*, this one or a dependency): /proto, then slashes (their DESTDIR)
#   a strap package (smartos-strap-*): /proto.strap, then slashes
# Any other store path is left as it is. A run of slashes names the same place as one.
use strict;
use warnings;
use File::Find;

my $dir = shift or die "usage: $0 DIR\n";
my $store = $ENV{NIX_STORE} // "/nix/store";

sub replacement {
  my ($path) = @_;
  my $name = substr($path, length($store) + 1 + 33);
  my $prefix;
  if ($name =~ /^smartos-illumos-nightly-/) { $prefix = "" }
  elsif ($name =~ /^gcc-illumos-/) { $prefix = "/usr/gcc/10" }
  elsif ($name =~ /^smartos-extra-/) { $prefix = "/proto" }
  elsif ($name =~ /^smartos-strap-/) { $prefix = "/proto.strap" }
  else { return $path }
  return $prefix . ("/" x (length($path) - length($prefix)));
}

find(
  {
    no_chdir => 1,
    wanted => sub {
      my $f = $_;
      return if -l $f || !-f $f;
      open(my $in, "<:raw", $f) or die "$f: $!\n";
      my $contents = do { local $/; <$in> };
      close($in);
      (my $mapped = $contents) =~ s{(\Q$store\E/[a-z0-9]{32}-[A-Za-z0-9+._?=-]+)}{replacement($1)}ge;
      return if $mapped eq $contents;
      my $mode = (stat($f))[2] & 07777;
      chmod($mode | 0200, $f) or die "$f: $!\n";
      open(my $out, ">:raw", $f) or die "$f: $!\n";
      print $out $mapped;
      close($out) or die "$f: $!\n";
      chmod($mode, $f) or die "$f: $!\n";
      print "$f\n";
    },
  },
  $dir
);
