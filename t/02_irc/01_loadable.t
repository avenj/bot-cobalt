use Test::More tests => 3;
use strict; use warnings;
BEGIN{
  use_ok('Bot::Cobalt::IRC');
}

my $irc = new_ok('Bot::Cobalt::IRC');

can_ok($irc, 'Cobalt_register', 'Cobalt_unregister');
