use Test::More tests => 4;
use strict; use warnings;

use Try::Tiny;

use_ok( 'Bot::Cobalt::Plugin::RDB::Error' );

my $obj = new_ok( 'Bot::Cobalt::Plugin::RDB::Error' => [
    "SOME_ERROR"
  ],
);

is( $obj->error, 'SOME_ERROR', 'error() seems to work' );

cmp_ok( $obj, 'eq', 'SOME_ERROR', 'Stringification seems to work' );
