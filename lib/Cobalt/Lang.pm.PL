#!perl
use 5.12.1;
use strict;
use warnings;

my $langset = 'etc/langs/english.yml';
die "langset $langset not found\n" unless -f $langset;

my $libfile = 'lib/Cobalt/Lang.pm';
die "lib $libfile not found\n" unless -f $libfile;

open my $libf_fh, '<', $libfile.'.in'
  or die "could not open $libfile: $!\n";
my @lang_pm = <$libf_fh>;
close $libf_fh;

open my $langf_fh, '<', $langset
  or die "could not open $langset: $!\n";
my @lang = <$langf_fh>;
close $langf_fh;

push(@lang_pm, "\n", "__DATA__", "\n", @lang);

open $liboutf_fh, '>', $libfile
  or die "could not open $libfile: $!\n";
print $liboutf_fh @lang_pm;
close $libf_fh;
