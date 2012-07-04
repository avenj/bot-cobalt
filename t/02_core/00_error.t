use Test::More tests => 7;
use strict; use warnings;

use Try::Tiny;

use_ok( 'Bot::Cobalt::Error' );

my $obj = new_ok( 'Bot::Cobalt::Error' => [
    "SOME_ERROR"
  ],
);

cmp_ok( $obj, 'eq', 'SOME_ERROR', 'Stringification seems to work' );

$obj = new_ok( 'Bot::Cobalt::Error' => [
    "There are some", "errors here"
  ],
);

cmp_ok( $obj, 'eq', 'There are someerrors here' );

isa_ok( $obj->join, 'Bot::Cobalt::Error' );
cmp_ok( $obj->join, 'eq', 'There are some errors here' );
