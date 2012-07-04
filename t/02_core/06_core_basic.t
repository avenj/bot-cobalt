use Test::More tests => 27;
use strict; use warnings;

BEGIN {
  use_ok( 'Bot::Cobalt::Common' );
  use_ok( 'Bot::Cobalt::Conf' );
  use_ok( 'Bot::Cobalt::Core' );
  
  use_ok( 'Bot::Cobalt::Core::Loader' );
}

can_ok( 'Bot::Cobalt::Conf', 'read_cfg' );
can_ok( 'Bot::Cobalt::Core', 'init' );

can_ok( 'Bot::Cobalt::Core::Loader',
  qw/
    load
    unload
    is_reloadable
  /
);

use Module::Build;
use File::Spec;
my $basedir;

use Try::Tiny;
try { 
  $basedir = Module::Build->current->base_dir
} catch {
  die "\n! Failed to retrieve base_dir() from Module::Build\n"
     ."...are you trying to run the test suite outside of `./Build`?\n"
};

my $etcdir  = File::Spec->catdir( $basedir, 'etc' );
my $cfg;
ok( 
  $cfg = Bot::Cobalt::Conf->new(etc => $etcdir)->read_cfg,
  'read_cfg()'
);
ok( ref $cfg eq 'HASH', 'cfg() is a hash' );

my $core;
ok( 
  $core = Bot::Cobalt::Core->instance(
    cfg => $cfg,
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
  
);

ok( $core->get_core_cfg, 'get_core_cfg()' );

ok( $core->get_channels_cfg('Main'), 'get_channels_cfg(Main)' );
ok( $core->get_plugin_cfg('None'), 'get_plugin_cfg(None)' );

ok( !$core->is_connected('Main'), 'is_connected(Main)' );
ok( !$core->get_irc_context('Main'), 'get_irc_context(Main)' );
ok( !$core->get_irc_object('Main'), 'get_irc_object(Main)' );
ok( !$core->get_irc_casemap('Main'), 'get_irc_casemap(Main)' );
