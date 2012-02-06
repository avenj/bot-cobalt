package Cobalt::Plugin::Games::Roulette;
our $VERSION = '0.001';

use 5.12.1;
use strict;
use warnings;

use Cobalt::Utils qw/color/;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;
  my %args = @_;
  $self->{core} = $args{core} if ref $args{core};
  return $self
}

sub execute {
  my ($self, $msg) = @_;
  my $cyls = 5;
  my $loaded = int rand($cyls);

  return int rand($cyls) == $loaded ? 
                color('bold', 'BANG!') 
              : 'Click . . .'  ;
}

1;
