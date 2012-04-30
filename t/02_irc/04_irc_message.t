## FIXME test IRC::Message
use Test::More tests => 2;
use strict; use warnings;

BEGIN {
  use_ok('Bot::Cobalt::IRC::Message');
  use_ok('Bot::Cobalt::IRC::Message::Public');
}
