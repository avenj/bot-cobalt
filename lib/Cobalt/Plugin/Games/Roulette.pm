package Cobalt::Plugin::Games::Roulette;
our $VERSION = '0.001';

use 5.12.1;
use strict;
use warnings;

use Cobalt::Utils qw/color/;

sub new { bless {}, shift }

sub fire {
  my ($self, $cyls) = @_;
  $cyls = 5 unless $cyls;
  my $loaded = int rand($cyls);
  int rand($cyls) == $loaded ? color('bold', 'BANG!') : 'Click . . .' ;
}

1;
