use Test::More;
use strict; use warnings;

BEGIN{
  use_ok('Bot::Cobalt::Core::ContextMeta::Ignore');
}

my $cmeta = new_ok('Bot::Cobalt::Core::ContextMeta::Ignore');
isa_ok($cmeta, 'Bot::Cobalt::Core::ContextMeta');

my $mask;
ok( $mask = $cmeta->add(
    'Context', 'avenj@cobaltirc.org', 'TESTING', 'MyPackage'
  ),
  'Ignore->add'
);

ok( $mask eq '*!avenj@cobaltirc.org', 'Mask normalization' );

ok( $cmeta->fetch('Context', $mask), 'fetch()' );

ok( $cmeta->reason('Context', $mask) eq 'TESTING', 'reason()' );
ok !$cmeta->reason(Context => 123), 'reason for unknown mask returns';

ok( $cmeta->addedby('Context', $mask) eq 'MyPackage', 'addedby()' );
ok !$cmeta->addedby(Context => 123), 'addedby for unknown mask returns';

ok( $cmeta->del('Context', $mask), 'del()' );

eval {; $cmeta->add };
like $@, qr/argument/, 'add with zero args dies';
eval {; $cmeta->add('foo') };
like $@, qr/argument/, 'add with one arg dies';

eval {; $cmeta->reason(foo => 123) };
like $@, qr/context/, 'reason for unknown context dies';
eval {; $cmeta->addedby(foo => 123) };
like $@, qr/context/, 'addedby for unknown context dies';

done_testing
