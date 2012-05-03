#!perl
use strict;
use warnings;

use File::Spec;

my $langset = File::Spec->catfile(qw/etc langs english.yml/);
die "langset $langset not found\n" unless -f $langset;

my $libfile = shift;
my $libfile_in = File::Spec->catfile(qw/lib Bot Cobalt Lang.pm.in/);
die "lib $libfile_in not found\n" unless -f $libfile_in;

open my $libf_fh, '<', $libfile.'.in'
  or die "could not open $libfile: $!\n";
my @lang_pm = <$libf_fh>;
close $libf_fh;

open my $langf_fh, '<', $langset
  or die "could not open $langset: $!\n";
my @lang = <$langf_fh>;
close $langf_fh;

open my $liboutf_fh, '>', $libfile
  or die "could not open $libfile: $!\n";
print $liboutf_fh @lang_pm, @lang;
close $libf_fh;
