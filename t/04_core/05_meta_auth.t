use Test::More;
use strict; use warnings;

BEGIN{
  use_ok('Bot::Cobalt::Core::ContextMeta::Auth');
};

my $cmeta = new_ok('Bot::Cobalt::Core::ContextMeta::Auth');
isa_ok($cmeta, 'Bot::Cobalt::Core::ContextMeta');

my $mask;
ok( $cmeta->add(
    Context  => 'Context',
    Username => 'someuser',
    Nickname => 'somebody',
    Host     => 'somebody!user@example.org',
    Flags    => { SUPERUSER => 1 },
    Level    => 3,
    Alias    => 'TestPkg',
  ),
  'Auth->add'
);

ok( $cmeta->level('Context', 'somebody') == 3, 'level()' );

ok( $cmeta->username('Context', 'somebody') eq 'someuser', 'username()' );
ok( $cmeta->user('Context', 'somebody') eq 'someuser', 
  'user() same as username()' 
);

ok( $cmeta->host('Context', 'somebody') eq 'somebody!user@example.org', 
  'host()' 
);

ok( $cmeta->alias('Context', 'somebody') eq 'TestPkg', 'alias()' );

ok( $cmeta->move('Context', 'somebody', 'nobody'), 'move()' );
ok( $cmeta->has_flag('Context', 'nobody', 'SUPERUSER'), 'has_flag()' );

ok( $cmeta->drop_flag('Context', 'nobody', 'SUPERUSER'), 'drop_flag()' );

ok( !$cmeta->has_flag('Context', 'nobody', 'SUPERUSER'), '! has_flag()' );

ok( $cmeta->set_flag('Context', 'nobody', 'FLAG'), 'set_flag()' );

ok( $cmeta->has_flag('Context', 'nobody', 'FLAG'), 'has_flag after set_flag' );

eval {; $cmeta->level };
like $@, qr/Expected/, 'level without args dies';
eval {; $cmeta->level('abc') };
like $@, qr/Expected/, 'level with one arg dies';
eval {; $cmeta->level('abc', 123) };
like $@, qr/context/, 'level for unknown context dies';

eval {; $cmeta->username };
like $@, qr/Expected/, 'username without args dies';
eval {; $cmeta->username('abc') };
like $@, qr/Expected/, 'username with one arg dies';
eval {; $cmeta->username(abc => 123) };
like $@, qr/context/, 'username for unknown context dies';

eval {; $cmeta->host };
like $@, qr/Expected/, 'host without args dies';
eval {; $cmeta->host('abc') };
like $@, qr/Expected/, 'host with one arg dies';
eval {; $cmeta->host(abc => 123) };
like $@, qr/context/, 'host for unknown context dies';

eval {; $cmeta->alias };
like $@, qr/Expected/, 'alias without args dies';
eval {; $cmeta->alias('abc') };
like $@, qr/Expected/, 'alias with one arg dies';
eval {; $cmeta->alias(abc => 123) };
like $@, qr/context/, 'alias for unknown context dies';

eval {; $cmeta->move };
like $@, qr/Expected/, 'move without args dies';
eval {; $cmeta->move('abc') };
like $@, qr/Expected/, 'move with one arg dies';
eval {; $cmeta->move(abc => 123) };
like $@, qr/Expected/, 'move with two args dies';
eval {; $cmeta->move(abc => 123 => 345) };
like $@, qr/context/, 'move for unknown context dies';
eval {; $cmeta->move(Context => foo => 123) };
like $@, qr/foo/, 'move for unknown user dies';

eval {; $cmeta->has_flag(abc => 123) };
like $@, qr/Expected/, 'has_flag with two args dies';
eval {; $cmeta->has_flag(abc => 123 => 345) };
like $@, qr/context/, 'has_flag for unknown context dies';

eval {; $cmeta->drop_flag(abc => 123) };
like $@, qr/Expected/, 'drop_flag with two args dies';
eval {; $cmeta->drop_flag(abc => 123 => 345) };
like $@, qr/context/, 'drop_flag for unknown context dies';

eval {; $cmeta->set_flag(abc => 123) };
like $@, qr/Expected/, 'set_flag with two args dies';
eval {; $cmeta->set_flag(abc => 123 => 345) };
like $@, qr/context/, 'set_flag for unknown context dies';
eval {; $cmeta->set_flag(Context => foo => 123) };
like $@, qr/foo/, 'set_flag for unknown user dies';

done_testing;
