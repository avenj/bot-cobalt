package Cobalt::IRC::Event::Nick;

use Moo;
use Cobalt::Common qw/:types/;
use IRC::Utils qw/eq_irc/;

extends 'Cobalt::IRC::Event';

has 'old_nick' => ( is => 'rw', isa => Str, required => 1 );
has 'new_nick' => ( is => 'rw', isa => Str, required => 1 );

has 'channels' => ( is => 'rw', isa => ArrayRef, required => 1 );
has 'common'   => ( is => 'ro', lazy => 1,
  default => sub { $_[0]->channels },
);

has 'equal' => ( is => 'ro', isa => Bool, lazy => 1,
  default => sub {
    my ($self) = @_;
    my $casemap = $self->core->get_irc_casemap($self->context);
    eq_irc($self->old, $self->new, $casemap) ? 1 : 0
  },
);

1;
__END__

=pod

=head1 NAME

Cobalt::IRC::Event::Nick - IRC Event subclass for nick changes

=head1 SYNOPSIS

  my $old = $nchg_ev->old_nick;
  my $new = $nchg_ev->new_nick;
  
  if ( $nchg_ev->equal ) {
    ## Case change only
  }
  
  my $common_chans = $nchg_ev->channels;

=head1 DESCRIPTION

This is the L<Cobalt::IRC::Event> subclass for nickname changes.

=head2 new_nick

Returns the new nickname, after the nick change.

=head2 old_nick

Returns the previous nickname, prior to the nick change.

=head2 channels

Returns an arrayref containing the list of channels we share with the 
user that changed nicks (at the time of the nickname change).

=head2 equal

Returns a boolean value indicating whether or not this was simply a 
case change (as determined via the server's announced casemapping and 
L<IRC::Utils/eq_irc>)

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

L<http://www.cobaltirc.org>

=cut
