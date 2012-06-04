use Test::More tests => 16;
use strict; use warnings;

BEGIN {
  use_ok( 'Bot::Cobalt::Common' );
  use_ok( 'Bot::Cobalt::Conf' );
  use_ok( 'Bot::Cobalt::Core' );
}

can_ok( 'Bot::Cobalt::Conf', 'read_cfg' );
can_ok( 'Bot::Cobalt::Core', 'init' );

my $core;
ok( 
  $core = Bot::Cobalt::Core->instance(
    cfg => {},
    var => '',
  ),
  'instance() a Bot::Cobalt::Core',
);

ok( $core->has_instance, 'Core has_instance' );

my $second;
ok( $second = Bot::Cobalt::Core->instance, 'Retrieve instance' );
is( "$core", "$second", 'instances match' );

for my $meth (qw/debug info warn error/) {
  ok( $core->log->can($meth), "Have log method $meth" );
}

isa_ok( $core->auth, 'Bot::Cobalt::Core::ContextMeta::Auth' );
isa_ok( $core->ignore, 'Bot::Cobalt::Core::ContextMeta::Ignore' );

## Did we get expected roles, here?
can_ok( $core,

  ## EasyAccessors:
  qw/
    get_plugin_alias
    get_core_cfg
    get_channels_cfg
    get_plugin_cfg
  /,
  
  ## IRC:
  qw/
    is_connected
    get_irc_context
    get_irc_object
    get_irc_casemap
  /,
  
  ## Timers:
  qw/
    timer_set
    timer_del
    timer_del_alias
    timer_get
    timer_get_alias
  /,
  
  ## Unloader:
  qw/
    is_reloadable
    unloader_cleanup
  /,
  
);
