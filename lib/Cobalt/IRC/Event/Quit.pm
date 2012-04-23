package Cobalt::IRC::Event::Quit;

use Moo;
use Sub::Quote;
use Cobalt::Common;

extends 'Cobalt::IRC::Event';

has 'reason' => ( is => 'rw', isa => Str, lazy => 1, 
  default => quote_sub q{''},
);

has 'common' => ( is => 'rw', isa => ArrayRef, lazy => 1,
  default => quote_sub q{[]},
);

1;
__END__
=pod

=head1 NAME

Cobalt::IRC::Event::Quit - IRC Event subclass for user quits

=head1 SYNOPSIS

  my $reason = $quit_ev->reason;
  
  my $shared_chans = $quit_ev->common;

=head1 DESCRIPTION

This is the L<Cobalt::IRC::Event> subclass for user quit events.

=head2 reason

Returns the displayed reason for the quit.

=head2 common

Returns an arrayref containing the list of channels previously shared 
with the user.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

L<http://www.cobaltirc.org>

=cut
