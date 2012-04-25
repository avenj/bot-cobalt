package Cobalt::IRC::Server;

## A server context.

use strictures 1;
use 5.10.1;

use Moo;
use Cobalt::Common qw/:types/;

has 'name' => ( is => 'rw', isa => Str, required => 1 );

has 'prefer_nick' => ( is => 'rw', isa => Str, required => 1 );

has 'irc' => ( is => 'rw', isa => Object,
  predicate => 'has_irc',
  clearer   => 'clear_irc',
);

has 'connected' => ( is => 'rw', isa => Bool, lazy => 1,
  default => sub { 0 },
  clearer => 'clear_connected',
);

has 'connectedat' => ( is => 'rw', isa => Num, lazy => 1,
  default => sub { 0 },
);

has 'casemap' => ( is => 'rw', isa => Str, lazy => 1,
  default => sub { 'rfc1459' },
  coerce  => sub {
    $_[0] = lc($_[0]);
    $_[0] = 'rfc1459' unless $_[0] ~~ [qw/ascii rfc1459 strict-rfc1459/]
  },
); 

has 'maxmodes' => ( is => 'rw', isa => Int, lazy => 1,
  default => sub { 3 },
);


1;
__END__
