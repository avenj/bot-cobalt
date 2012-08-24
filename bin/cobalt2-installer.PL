#!perl

use 5.10.1;
use strict;
use warnings;

use File::Find;
use File::Spec;

use Data::Dumper;

my $bin_in  = 'tools/cobalt2-installer.in';
die "Input $bin_in not found" unless -f $bin_in;

my $bin_out = shift;

my $etcdir  = 'etc';
die "$etcdir not a directory" unless -d $etcdir;

## Find example confs and langs in $etcdir
my @valid_exts = qw/ conf cf yml yaml json /;
my @paths_to_add;
find(
  sub {
    my ($ext) = $_ =~ /\.(\S+)$/;
    return unless $ext and grep { $_ eq $ext } @valid_exts;
    push(@paths_to_add, $File::Find::name);
  },
  $etcdir
);

## Slurp etc/ files found above
my $cfref = { };
for my $addable_path (@paths_to_add) {
  my $relative_path = File::Spec->abs2rel($addable_path, $etcdir);

  open my $c_fh, '<:encoding(UTF-8)', $addable_path
    or die "could not open $addable_path: $!";
  my $slurped;
  { local $/; $slurped = <$c_fh>; }
  close($c_fh);

  $cfref->{$relative_path} = $slurped;
}

my $dump_cfs = Data::Dumper->new([$cfref])->Terse(1)->Purity(1)->Dump;

## Read cobalt2-installer.in
my $installer_bin;
open my $bin_in_fh, '<', $bin_in
  or die "could not open $bin_in: $!";
{ local $/; $installer_bin = join '', <$bin_in_fh>; }
close $bin_in_fh;

die "empty installer_bin?" unless $installer_bin;

my $compiled_installer = $installer_bin . $dump_cfs . "\n" ;

open my $bin_out_fh, '>:encoding(UTF-8)', $bin_out
  or die "could not open $bin_out: $!";
print $bin_out_fh $compiled_installer;
close $bin_out_fh;

say "Created $bin_out";
