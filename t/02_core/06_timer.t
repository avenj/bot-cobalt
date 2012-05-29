use Test::More tests => 20;
use strict; use warnings;

BEGIN {
  use_ok( 'Bot::Cobalt::Timer' );
}

my $timer = new_ok( 'Bot::Cobalt::Timer' => [
    delay => 60,
    
    id    => 'mytimer',
   
    event => 'test',
   
    alias => 'Pkg::Snackulate', 
  ],
);

is( $timer->delay, 60, 'delay()' );
is( $timer->event, 'test', 'event()' );
is( $timer->alias, 'Pkg::Snackulate', 'alias()' );
ok( $timer->has_id, 'has_id()' );
is( $timer->id, 'mytimer', 'id()' );
is( $timer->type, 'event', 'type()' );

ok( $timer->at, 'delay() -> at()' );
ok( $timer->at(1), 'reset at()' );
is( $timer->at, 1, 'at() is reset' );

ok( $timer->args(['arg1', 'arg2']), 'set args()' );
is_deeply( $timer->args, ['arg1', 'arg2'], 'get args()' );

ok( $timer->is_ready, 'timer would be ready' );

my $mtimer = new_ok( 'Bot::Cobalt::Timer' => [
    context => 'Test',
    target  => 'target',
    text    => 'testing things',
  ],
);

is( $mtimer->context, 'Test', 'context()' );
is( $mtimer->target, 'target', 'target()' );
is( $mtimer->text, 'testing things', 'text()' );
is( $mtimer->type, 'msg', 'assume msg type()' );
is( $mtimer->at, 0, 'no delay set' );
