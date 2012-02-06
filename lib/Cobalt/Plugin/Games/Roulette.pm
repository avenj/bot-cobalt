package Cobalt::Plugin::Games::Roulette;
our $VERSION = '0.001';

use 5.12.1;
use strict;
use warnings;

use Cobalt::Utils qw/color/;

sub new { bless {}, shift }

sub execute {
  my ($self, $core) = @_;
  my $cyls = 5;
  my $loaded = int rand($cyls);

  return int rand($cyls) == $loaded ? 
                color('bold', 'BANG!') 
              : 'Click . . .'  ;
}

1;
