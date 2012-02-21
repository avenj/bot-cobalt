use Test::More tests => 5;

BEGIN {
  use_ok( 'Cobalt::Common' );
  use_ok( 'Cobalt::Conf' );
  use_ok( 'Cobalt::Core' );
}

can_ok( 'Cobalt::Conf', 'read_cfg' );
can_ok( 'Cobalt::Core', 'init' );
