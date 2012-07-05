package Bot::Cobalt::Core;
our $VERSION = '0.012';

## This is the core Syndicator singleton.

use 5.10.1;
use strictures 1;
use Carp;
use Moo;

use Log::Handler;

use POE;

use Bot::Cobalt::Common;
use Bot::Cobalt::IRC;
use Bot::Cobalt::Lang;

use Bot::Cobalt::Core::ContextMeta::Auth;
use Bot::Cobalt::Core::ContextMeta::Ignore;

use Bot::Cobalt::Core::Loader;

use Scalar::Util qw/blessed/;

use Try::Tiny;

use File::Spec;

has 'cfg' => ( 
  ## usually a hashref from Bot::Cobalt::Conf created via frontend
  required => 1,
  is  => 'rw', 
  isa => HashRef,
);

has 'var' => (
  ## path to our var/
  required => 1,
  is  => 'ro', 
  isa => Str,
);

has 'etc' => (
  lazy => 1,
  is  => 'ro',
  isa => Str, 

  default => sub { $_[0]->cfg->{path} }
);

has 'log'      => ( 
  is => 'rw', 

  isa => sub {
    unless (blessed $_[0]) {
      die "log() not passed a blessed object"
    }

    for my $meth (qw/debug info warn error/) {
      die "log() object missing required method $meth"
        unless $_[0]->can($meth);
    }
  },
  
  default => sub {
    Log::Handler->create_logger("cobalt");
  },
);

has 'loglevel' => ( 
  is  => 'rw', 
  isa => Str, 

  default => sub { 'info' } 
);

has 'detached' => ( 
  lazy => 1,
  is   => 'ro', 
  isa  => Int, 

  default => sub { 0 },
);

has 'debug'    => (
  lazy => 1,

  isa => Int, 
  is  => 'rw', 

  default => sub { 0 },
);

## version/url used for var replacement:
has 'version' => ( 
  lazy => 1,

  is   => 'rwp', 
  isa  => Str,

  default => sub { $Bot::Cobalt::Core::VERSION }
);

has 'url' => ( 
  lazy => 1,

  is  => 'rwp',
  isa => Str,

  default => sub { "http://www.metacpan.org/dist/Bot-Cobalt" },
);

has 'langset' => (
  lazy => 1,
  
  is  => 'ro',
  isa => sub {
    die "langset() needs a Bot::Cobalt::Lang"
      unless blessed $_[0] && $_[0]->isa('Bot::Cobalt::Lang');
  },

  writer  => 'set_langset',
  
  default => sub {
    my ($self) = @_;

    my $language = $self->cfg->{core}->{Language} // 'english';
    
    my $lang_dir = File::Spec->catdir( $self->etc, 'langs' );
    
    Bot::Cobalt::Lang->new(
      use_core => 1,
      
      lang_dir => $lang_dir,
      lang     => $language,
    )
  },
);

has 'lang' => ( 
  lazy => 1,

  is  => 'ro',
  isa => HashRef,
  
  writer  => 'set_lang',
  
  default => sub {
    my ($self) = @_;
    $self->langset->rpls
  }, 
);

has 'State' => (
  lazy => 1,

  ## global 'heap' of sorts
  is => 'ro',
  isa => HashRef,

  default => sub {
    {
      HEAP => { },
      StartedTS => time(),
      Counters  => {
        Sent => 0,
      },
      
      # nonreloadable plugin list keyed on alias for plugin mgrs:
      NonReloadable => { },
    } 
  },
);

has 'PluginObjects' => (
  lazy => 1,

  ## alias -> object mapping
  is  => 'rw',  
  isa => HashRef,
  
  default => sub { {} },
);

has 'Provided' => (
  lazy => 1,

  ## Some plugins provide optional functionality.
  ## This hash lets other plugins see if an event is available.
  is  => 'ro',
  isa => HashRef,

  default => sub { {} },
);

has 'auth' => ( 
  lazy => 1,

  is  => 'rw', 
  isa => Object,
  
  default => sub {
    Bot::Cobalt::Core::ContextMeta::Auth->new
  },
);

has 'ignore' => ( 
  lazy => 1,

  is  => 'rw', 
  isa => Object,
  
  default => sub {
    Bot::Cobalt::Core::ContextMeta::Ignore->new
  },
);

## FIXME not documented
has 'resolver' => (
  lazy => 1,
  
  is  => 'rwp',
  isa => Object,
  
  default => sub {
    POE::Component::Client::DNS->spawn(
      Alias => 'core_resolver',
    )
  },
);

extends 'POE::Component::Syndicator';

with 'Bot::Cobalt::Core::Role::Singleton';
with 'Bot::Cobalt::Core::Role::EasyAccessors';
with 'Bot::Cobalt::Core::Role::Timers';
with 'Bot::Cobalt::Core::Role::IRC';

## FIXME test needed:
sub rpl  {
  my ($self, $rpl) = splice @_, 0, 2;

  confess "rpl() method requires a RPL tag"
    unless defined $rpl;
  
  my $string = $self->lang->{$rpl}
    // return "Unknown RPL $rpl, vars: ".join(' ', @_);
  
  rplprintf( $string, @_ )
}

sub init {
  my ($self) = @_;

  my $maxlevel = $self->debug ? 'debug' : $self->loglevel ;

  my $logfile  = $self->cfg->{core}->{Paths}->{Logfile}
                // File::Spec->catfile( $self->var, 'cobalt.log' );

  $self->log->add(
    file => {
      maxlevel => $maxlevel,
      timeformat     => "%Y/%m/%d %H:%M:%S",
      message_layout => "[%T] %L %p %m",

      filename => $logfile,
      filelock => 1,
      fileopen => 1,
      reopen   => 1,
      autoflush => 1,
    },
  );

  unless ($self->detached) {
    $self->log->add(
      screen => {
        log_to => "STDOUT",
        maxlevel => $maxlevel,
        timeformat     => "%Y/%m/%d %H:%M:%S",
        message_layout => "[%T] %L (%p) %m",
      },
    );
  }

  ## Language set check. Force attrib fill.
  $self->lang;

  $self->_syndicator_init(
    prefix => 'ev_',  ## event prefix for sessions
    reg_prefix => 'Cobalt_',
    types => [ SERVER => 'Bot', USER => 'Outgoing' ],
    options => { },
    object_states => [
      $self => [
        'syndicator_started',
        'syndicator_stopped',

        'shutdown',
        'sighup',

        'ev_plugin_error',

        'core_timer_check_pool',
      ],
    ],
  );

}

sub syndicator_started {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  $kernel->sig('INT'  => 'shutdown');
  $kernel->sig('TERM' => 'shutdown');
  $kernel->sig('HUP'  => 'sighup');

  $self->log->info(''.__PACKAGE__.' '.$self->version);
 
  $self->log->info("--> Initializing plugins . . .");
  
  my $i = 0;
  my @plugins = sort {
    ($self->cfg->{plugins}->{$b}->{Priority}//1)
    <=>
    ($self->cfg->{plugins}->{$a}->{Priority}//1)
                } keys %{ $self->cfg->{plugins} };

  PLUGIN: for my $plugin (@plugins)
  {
    my $this_plug_cf = $self->cfg->{plugins}->{$plugin};

    my $module = $this_plug_cf->{Module};
    
    unless (defined $module) {
      $self->log->error("Missing Module directive for $plugin");
      next PLUGIN
    }

    next PLUGIN if $this_plug_cf->{NoAutoLoad};
    
    my $obj;
    try {
      $obj = Bot::Cobalt::Core::Loader->load($module);
      
      unless ( Bot::Cobalt::Core::Loader->is_reloadable($obj) ) {
        $self->State->{NonReloadable}->{$plugin} = 1;
        $self->log->debug("$plugin marked non-reloadable");
      }

    } catch {
      $self->log->error("Load failure; $_");

      next PLUGIN
    };

    ## save stringified object -> plugin mapping:
    $self->PluginObjects->{$obj} = $plugin;

    unless ( $self->plugin_add($plugin, $obj) ) {
      $self->log->error("plugin_add failure for $plugin");

      delete $self->PluginObjects->{$obj};
            
      Bot::Cobalt::Core::Loader->unload($module);

      next PLUGIN
    }

    $i++;
  }

  $self->log->info("-> $i plugins loaded");

  $self->send_event('plugins_initialized', $_[ARG0]);

  $self->log->info("-> started, plugins_initialized sent");

  ## kickstart timer pool
  $kernel->yield('core_timer_check_pool');
}

sub sighup {
  my $self = $_[OBJECT];
  $self->log->warn("SIGHUP received");
  
  if ($self->detached) {
    ## Caught by Plugin::Rehash if present
    ## Not documented because you should be using the IRC interface
    ## (...and if the bot was run with --nodetach it will die, below)
    $self->log->info("sending Bot_rehash (SIGHUP)");
    $self->send_event( 'Bot_rehash' );
  } else {
    ## we were (we think) attached to a terminal and it's (we think) gone
    ## shut down soon as we can:
    $self->log->warn("Lost terminal; shutting down");

    $_[KERNEL]->yield('shutdown');
  }

  $_[KERNEL]->sig_handled();
}

sub shutdown {
  my $self = ref $_[0] eq __PACKAGE__ ? $_[0] : $_[OBJECT];

  $self->log->warn("Shutdown called, destroying syndicator");

  $self->_syndicator_destroy();
}

sub syndicator_stopped {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  $kernel->alarm('core_timer_check_pool');

  $self->log->debug("issuing: POCOIRC_SHUTDOWN, shutdown");

  $kernel->signal( $kernel, 'POCOIRC_SHUTDOWN' );
  $kernel->post( $kernel, 'shutdown' );

  $self->log->warn("Core syndicator stopped.");
}

sub ev_plugin_error {
  my ($kernel, $self, $err) = @_[KERNEL, OBJECT, ARG0];
  
  ## Receives the same error as 'debug => 1' (in Syndicator init)
  
  $self->log->error("Plugin err: $err");

  ## Bot_plugin_error
  $self->send_event( 'plugin_error', $err );
}

### Core low-pri timer

sub core_timer_check_pool {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  ## Timers are provided by Core::Role::Timers

  my $timerpool = $self->TimerPool;
  
  TIMER: for my $id (keys %$timerpool) {
    my $timer = $timerpool->{$id};

    unless (blessed $timer && $timer->isa('Bot::Cobalt::Timer') ) {
      ## someone's been naughty
      $self->log->warn("not a Bot::Cobalt::Timer: $id");
      delete $timerpool->{$id};
      next TIMER
    }
    
    if ( $timer->execute_if_ready ) {
      my $event = $timer->event;

      $self->log->debug("timer execute; $id ($event)")
        if $self->debug > 1;

      $self->send_event( 'executed_timer', $id );
      $self->timer_del($id);
    }
  
  } ## TIMER
  
  ## most definitely not a high-precision timer.
  ## checked every second or so
  $kernel->alarm('core_timer_check_pool' => time + 1);
}

1;
__END__

=pod

=head1 NAME

Bot::Cobalt::Core - Bot::Cobalt core and event syndicator

=head1 DESCRIPTION

This module is the core of L<Bot::Cobalt>, tying an event syndicator 
(via L<POE::Component::Syndicator> and L<Object::Pluggable>) into a 
L<Log::Handler> instance, configuration manager, and other useful tools.

Core is a singleton; within a running Cobalt instance, you can always 
retrieve the Core via the B<instance> method:

  require Bot::Cobalt::Core;
  my $core = Bot::Cobalt::Core->instance;

You can also query to find out if Core has been properly instanced:

  if ( Bot::Cobalt::Core->is_instanced ) {
  
  }

If you 'use Bot::Cobalt;' you can also access the Core singleton 
instance via the C<core()> exported sugar:

  use Bot::Cobalt;
  core->log->info("I'm here now!")

See L<Bot::Cobalt::Core::Sugar> for details.

Public methods are documented in L<Bot::Cobalt::Manual::Plugins/"Core 
methods"> and the classes & roles listed below.

See also:

=over

=item *

L<Bot::Cobalt::Manual::Plugins> - Cobalt plugin authoring manual

=item *

L<Bot::Cobalt::IRC> - IRC bridge / events

=item *

L<Bot::Cobalt::Core::Role::EasyAccessors>

=item *

L<Bot::Cobalt::Core::Role::IRC>

=item *

L<Bot::Cobalt::Core::Role::Timers>


=back

=head1 Custom frontends

It's actually possible to write custom frontends to spawn a Cobalt 
instance; Bot::Cobalt::Core just needs to be initialized with a valid 
configuration hash and spawned via L<POE::Kernel>'s run() method.

A configuration hash is typically created by L<Bot::Cobalt::Conf>:

  my $cconf = Bot::Cobalt::Conf->new(
    etc => $path_to_etc_dir,
  );
  my $cfg_hash = $cconf->read_cfg;

. . . then passed to Bot::Cobalt::Core before the POE kernel is started:

  ## Instance a Bot::Cobalt::Core singleton
  ## Further instance() calls will return the singleton
  Bot::Cobalt::Core->instance(
    cfg => $cfg_hash,
    var => $path_to_var_dir,
    
    ## See perldoc Log::Handler regarding log levels:
    loglevel => $loglevel,
    
    ## Debug levels:
    debug => $debug,
    
    ## Indicate whether or not we're forked to the background:
    detached => $detached,
  )->init;

Frontends have to worry about fork()/exec() on their own.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
