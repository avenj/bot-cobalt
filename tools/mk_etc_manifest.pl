#!/usr/bin/env perl

use v5.10;
use strictures 1;
use Path::Tiny;

my $Dir = path(shift @ARGV || 'share/etc');
die "Not found: '$Dir'" unless $Dir->exists;
die "Not a directory: '$Dir'" unless $Dir->is_dir;

my $Manifest = path(shift @ARGV || 'share/etc/Manifest');

say "Compiling files from etcdir '$Dir'";

my $iter = $Dir->iterator(
  +{ recurse => 1, follow_symlinks => 0 }
);

# FIXME
#  walk path
#  get basename relative to $Dir
#    share/etc/quux.conf      -> quux.conf
#    share/etc/foo/bar.conf   -> foo/bar.conf
my $accum = '';
while ( my $path = $iter->() ) {
  my $rel = $path->relative($Dir);
  say "  -> $rel";
  $accum .= $rel . "\n";
}

say "Writing Manifest to '$Manifest'";
$Manifest->spew_utf8($accum);
