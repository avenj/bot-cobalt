package Cobalt::Plugin::Games::RockPaperScissors;
our $VERSION = '0.01';

use 5.12.1;
use strict;
use warnings;

sub new { bless {}, shift }

sub execute {
  my ($self, $rps) = @_;

  if      (! $rps) {
    return "What did you want to throw?"
  } elsif ( !(lc($rps) ~~ [ qw/rock paper scissors/ ]) ) {
    return "You gotta throw rock, paper, or scissors!"
  }

  my $beats = {
    scissors => 'paper',
    paper => 'rock',
    rock => 'scissors',
  };

  my $throw = (keys %$beats)[rand(scalar keys %$beats)];

  if      ($throw eq $rps) {
    return "You threw $rps, I threw $throw -- it's a tie!";
  } elsif ($beats->{$throw} eq $rps) {
    return "You threw $rps, I threw $throw -- I win!";
  } else {
    return "You threw $rps, I threw $throw -- you win :(";
  }
}

1;
