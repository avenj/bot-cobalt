use Test::More tests => 11;
use strict; use warnings;

## FIXME colorize string then check stripped() ?

BEGIN {
  use_ok('Bot::Cobalt::IRC::Message');
  use_ok('Bot::Cobalt::IRC::Message::Public');
}

my $msg = new_ok( 'Bot::Cobalt::IRC::Message' => [
   src     => 'somebody!somewhere@example.org',
   context => 'Context',
   message => 'Some IRC message',
   targets => [ 'JoeUser' ],
 ]
);
isa_ok( $msg, 'Bot::Cobalt::IRC::Event' );

ok( $msg->src_nick eq 'somebody', 'src_nick()' );
ok( $msg->src_user eq 'somewhere', 'src_user()' );
ok( $msg->src_host eq 'example.org', 'src_host()' );

ok( $msg->context eq 'Context', 'context()' );
ok( $msg->message eq 'Some IRC message', 'message()' );
ok( $msg->target eq 'JoeUser', 'target()');
ok( $msg->stripped eq 'Some IRC message', 'stripped()' );
## FIXME test arrays

## FIXME test arrays after resetting message

## FIXME test channel message also
