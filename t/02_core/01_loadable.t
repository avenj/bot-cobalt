use Test::More tests => 5;

BEGIN {
  use_ok( 'Bot::Cobalt::Common' );
  use_ok( 'Bot::Cobalt::Conf' );
  use_ok( 'Bot::Cobalt::Core' );
}

can_ok( 'Bot::Cobalt::Conf', 'read_cfg' );
can_ok( 'Bot::Cobalt::Core', 'init' );
