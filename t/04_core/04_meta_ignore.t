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

ok( $cmeta->addedby('Context', $mask) eq 'MyPackage', 'addedby()' );

ok( $cmeta->del('Context', $mask), 'del()' );

eval {; $cmeta->add };
like $@, qr/argument/, 'add with zero args dies';
eval {; $cmeta->add('foo') };
like $@, qr/argument/, 'add with one arg dies';

done_testing
