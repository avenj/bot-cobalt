package Bot::Cobalt::IRC::Server;
our $VERSION = '0.011';

## A server context.

use strictures 1;
use 5.10.1;

use Moo;
use Bot::Cobalt::Common qw/:types/;

has 'name' => ( 
  required => 1,

  is  => 'rw', 
  isa => Str, 
);

has 'prefer_nick' => (
  required => 1, 

  is  => 'rw', 
  isa => Str, 
);

has 'irc' => (
  is  => 'rw', 
  isa => Object,

  predicate => 'has_irc',
  clearer   => 'clear_irc',
);

has 'connected' => (
  lazy => 1,

  is  => 'rw', 
  isa => Bool, 

  clearer => 'clear_connected',

  default => sub { 0 },
);

has 'connectedat' => (
  lazy => 1,

  is  => 'rw', 
  isa => Num, 

  default => sub { 0 },
);

has 'casemap' => (
  lazy => 1,

  is  => 'rw', 
  isa => Str, 

  default => sub { 'rfc1459' },
); 

has 'maxmodes' => (
  lazy => 1,

  is => 'rw', 
  isa => Int, 

  default => sub { 3 },
);

has 'maxtargets' => (
  lazy => 1,
  
  is  => 'rw', 
  isa => Int, 
  
  default => sub { 4 },
);

1;
__END__

=pod

=head1 NAME

Bot::Cobalt::IRC::Server - An IRC server context

=head1 SYNOPSIS

  ## Get a Bot::Cobalt::IRC::Server object from Bot::Cobalt::Core
  my $server = $core->get_irc_context( $context );  
  
  if ( $server->connected ) {
    my $casemap = $server->casemap;
    
    . . .
  }

=head1 DESCRIPTION

Represents an IRC server context. 

L<Bot::Cobalt::Core> stores a server context object for every configured 
context; it can be retrieved using B<get_irc_context>.

The following attributes are available:

=head2 name

The server name.

Note that this is the server we connected to or intend to connect to;
not necessarily the announced name of a connected server.

=head2 connected

A boolean value indicating whether or not this context is marked as 
connected.

In the case of core-managed contexts, this is set by L<Bot::Cobalt::IRC>.

=head2 connectedat

The time (epoch seconds) that the server context was marked as 
connected.

=head2 prefer_nick

The preferred/configured nickname for this context.

=head2 irc

The actual IRC object for this configured context; this will typically 
be a L<POE::Component::IRC> subclass.

=head2 casemap

The available CASEMAPPING value for this server.

See L<Bot::Cobalt::Manual::Plugins/get_irc_casemap>

=head2 maxmodes

The maximum number of modes allowed in a single mode change command.

If the server does not announce MAXMODES, the default is 3.

=head2 maxtargets

The maximum number of targets allowed for a single message as specified 
by MAXTARGETS. 

Useful for combining message sends to multiple channels, for example.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

L<http://www.cobaltirc.org>

=cut
