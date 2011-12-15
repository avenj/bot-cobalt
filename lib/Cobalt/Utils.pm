package Cobalt::Utils;

use 5.14.1;
use strict;
use warnings;

require Exporter;
our @ISA = qw(Exporter);

our @EXPORT = qw/
  timestr_to_secs

/;

sub timestr_to_secs {
  ## turn something like 2h3m30s into seconds
  my $timestr = shift;
  my($hrs,$mins,$secs,$total);
  if ($timestr =~ m/(\d+)h/)
    { $hrs = $1; }
  if ($timestr =~ m/(\d+)m/)
    { $mins = $1; }
  if ($timestr =~ m/(\d+)s/)
    { $secs = $1; }
  $total = $secs;
  $total += (int $mins * 60) if $mins;
  $total += (int $hrs * 3600) if $hrs;
  return int($total)
}


1;
