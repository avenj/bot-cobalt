use Test::More tests => 9;
use strict; use warnings;

BEGIN{
  use_ok('Bot::Cobalt::IRC::Server');
}

my $server = new_ok('Bot::Cobalt::IRC::Server' => 
  [ name => 'irc.example.org', prefer_nick => 'abc' ]
);

ok( $server->connectedat(time), 'connectedat()' );
ok( $server->connected(1), 'connected()' );
ok( $server->casemap('ascii'), 'casemap(ascii)' );
ok( $server->casemap eq 'ascii', 'casemap eq ascii' );
ok( $server->casemap('rfc1459'), 'casemap(rfc1459)' );
ok( $server->casemap eq 'rfc1459', 'casemap eq rfc1459' );
ok( $server->maxmodes(4) == 4, 'maxmodes(4)' );
