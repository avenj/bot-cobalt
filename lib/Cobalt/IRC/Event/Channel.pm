package Cobalt::IRC::Event::Channel;

## Generic channel events.

use Moo;
use Cobalt::Common qw/:types/;

extends 'Cobalt::IRC::Event';

has 'channel' => ( is => 'rw', isa => Str, required => 1 );

1;
__END__

=pod

=head1 NAME

Cobalt::IRC::Event::Channel - IRC Event subclass for channel events

=head1 SYNOPSIS

  my $channel = $irc_ev->channel;

=head1 DESCRIPTION

A class for Things Happening on an IRC channel.

A subclass of L<Cobalt::IRC::Event>.

=head2 channel

The only method added by this class is B<channel>, returning a string 
containing the channel name.

=head1 SEE ALSO

L<Cobalt::IRC::Event>

L<Cobalt::IRC::Event::Kick>

L<Cobalt::IRC::Event::Mode>

L<Cobalt::IRC::Event::Nick>

L<Cobalt::IRC::Event::Quit>

L<Cobalt::IRC::Event::Topic>

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

L<http://www.cobaltirc.org>

=cut
