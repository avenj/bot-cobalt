package Cobalt::Plugin::Games::Dice;

our $VERSION = '0.01';

use 5.12.1;
use strict;
use warnings;

sub new { bless( {}, shift ) }

sub execute {
  my ($self, $str) = @_;
  return "Syntax: roll XdY  [ +/- <modifier> ]" unless $str;
  my ($dice, $modifier, $modify_by) = split ' ', $str;

  given ($dice) {
  
    when (/^(\d+)?d(\d+)?$/i) {  ## Xd / dY / XdY syntax
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
      
      my $resp = "Rolled $n_dice dice of $sides sides: ";
      $resp .= join ' ', @rolls;
      $resp .= " [total: $total / $potential]";
      return $resp
    }
    
    when (/^\d+$/) {
      my $rolled = (int rand $dice) + 1;
      $modifier = undef unless $modify_by and $modify_by =~ /^\d+$/;
      if ($modifier) {
        if      ($modifier eq '+') {
          $rolled += $modify_by;
        } elsif ($modifier eq '-') {
          $rolled -= $modify_by;
        }
      }
      return "Rolled single die of $dice sides: $rolled"
    }
    
    default {
      return "Syntax: roll XdY  [ +/- <modifier> ]"
    }
  
  }

}

1;
