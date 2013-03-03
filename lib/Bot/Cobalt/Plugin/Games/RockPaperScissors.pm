package Bot::Cobalt::Plugin::Games::RockPaperScissors;
our $VERSION = '0.016001';

use 5.10.1;
use strict;
use warnings;

sub new { bless [], shift }

sub execute {
  my ($self, $msg, $rps) = @_;
  my $nick = $msg->src_nick//'';

  if      (! $rps) {
    return "What did you want to throw, ${nick}?"
  } elsif ( ! grep { $_ eq lc($rps) } qw/rock paper scissors/ ) {
    return "${nick}: You gotta throw rock, paper, or scissors!"
  }

  my $beats = {
    scissors => 'paper',
    paper    => 'rock',
    rock     => 'scissors',
  };

  my $throw = (keys %$beats)[rand(keys %$beats)];

  if      ($throw eq $rps) {
    return "$nick threw $rps, I threw $throw -- it's a tie!";
  } elsif ($beats->{$throw} eq $rps) {
    return "$nick threw $rps, I threw $throw -- I win!";
  } else {
    return "$nick threw $rps, I threw $throw -- you win :(";
  }
}

1;
__END__

=pod

=head1 NAME

Bot::Cobalt::Plugin::Games::RockPaperScissors - IRC rock-paper-scissors

=head1 SYNOPSIS

  !rps rock
  !rps scissors
  !rps paper

=head1 DESCRIPTION

Play rock-paper-scissors against the bot.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
