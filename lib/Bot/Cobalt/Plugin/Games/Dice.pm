package Bot::Cobalt::Plugin::Games::Dice;
our $VERSION = '0.016001';

use 5.10.1;
use strict;
use warnings;

use Bot::Cobalt::Utils qw/ color /;

sub new { bless [], shift }

sub execute {
  my ($self, $msg, $str) = @_;
  return "Syntax: roll XdY  [ +/- <modifier> ]" unless $str;

  my ($dice, $modifier, $modify_by) = split ' ', $str;

  if ($dice =~ /^(\d+)?d(\d+)?$/i) {  ## Xd / dY / XdY syntax
      my $n_dice = $1 || 1;
      my $sides  = $2 || 6;

      my @rolls;

      $n_dice = 10    if $n_dice > 10;
      $sides  = 10000 if $sides > 10000;

      for (my $i = $n_dice; $i >= 1; $i--) {
        push(@rolls, (int rand $sides) + 1 );
      }
      my $total;
      $total += $_ for @rolls;

      $modifier = undef unless $modify_by and $modify_by =~ /^\d+$/;
      if ($modifier) {
        if      ($modifier eq '+') {
          $total += $modify_by;
        } elsif ($modifier eq '-') {
          $total -= $modify_by;
        }
      }

      my $potential = $n_dice * $sides;

      my $resp = "Rolled "
                 .color('bold', $n_dice)
                 ." dice of "
                 .color('bold', $sides)
                 ." sides: " ;

      $resp .= join ' ', @rolls;

      $resp .= " [total: ".color('bold', $total)." / $potential]";

      return $resp
  }

  if ($dice =~ /^\d+$/) {
      my $rolled = (int rand $dice) + 1;
      $modifier = undef unless $modify_by and $modify_by =~ /^\d+$/;
      if ($modifier) {
        if      ($modifier eq '+') {
          $rolled += $modify_by;
        } elsif ($modifier eq '-') {
          $rolled -= $modify_by;
        }
      }
      my $resp =  "Rolled single die of "
                  .color('bold', $dice)
                  ." sides: "
                  .color('bold', $rolled) ;
      return $resp
  }

  return "Syntax: roll XdY  [ +/- <modifier> ]"
}

1;
__END__

=pod

=head1 NAME

Bot::Cobalt::Plugin::Games::Dice - IRC dice roller

=head1 SYNOPSIS

  !roll 6     # Roll a six-sided die
  !roll 2d6   # Roll a pair of them
  !roll 6d10  # Roll weird dice

=head1 DESCRIPTION

Simple dice bot; accepts either the number of sides as a simple integer 
or XdY syntax.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
