use Test::More tests => 7;
use strict; use warnings;

BEGIN{
  use_ok('Bot::Cobalt::IRC::Event');
}

my $ev = new_ok('Bot::Cobalt::IRC::Event' => 
  [ context => 'Main', src => 'yomomma!your@mother.org' ]
);

ok( $ev->context eq 'Main', 'context()' );

ok( $ev->src eq 'yomomma!your@mother.org', 'src()' );

ok( $ev->src_nick eq 'yomomma', 'src_nick()' );
ok( $ev->src_user eq 'your', 'src_user()' );
ok( $ev->src_host eq 'mother.org', 'src_host()' );
