use Test::More tests => 13;
use strict; use warnings;

BEGIN{
  use_ok('Bot::Cobalt::IRC::Event::Nick');
}

my $ev = new_ok('Bot::Cobalt::IRC::Event::Nick' =>
  [ context => 'Main', src => 'yomomma!your@mother.org',
    old_nick => 'yomomma',
    new_nick => 'bob',
    channels => [ '#otw', '#unix' ]
  ]
);

isa_ok($ev, 'Bot::Cobalt::IRC::Event' );

ok( $ev->context eq 'Main', 'context()' );

ok( $ev->src eq 'yomomma!your@mother.org', 'src()' );

ok( $ev->src_nick eq 'yomomma', 'src_nick()' );
ok( $ev->src_user eq 'your', 'src_user()' );
ok( $ev->src_host eq 'mother.org', 'src_host()' );

ok( $ev->old_nick eq 'yomomma', 'old_nick()' );
ok( $ev->new_nick eq 'bob', 'new_nick()' );
ok( ref $ev->channels eq 'ARRAY', 'channels() is ARRAY' );
is_deeply($ev->channels, [ '#otw', '#unix' ], 'channels() is correct' );
is_deeply($ev->channels, $ev->common, 'channels() eq common()' );
