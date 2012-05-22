package Bot::Cobalt::Core;
our $VERSION = '0.001';

## This is the core Syndicator singleton.

use 5.10.1;
use strictures 1;
use Carp;
use Moo;

use Log::Handler;

use POE;
use Object::Pluggable::Constants qw(:ALL);

use Bot::Cobalt::Common;
use Bot::Cobalt::IRC;

use Bot::Cobalt::Core::ContextMeta::Auth;
use Bot::Cobalt::Core::ContextMeta::Ignore;

use Storable qw/dclone/;

use Scalar::Util qw/blessed/;

use File::Spec;

## usually a hashref from Bot::Cobalt::Conf created via frontend:
has 'cfg' => ( is => 'rw', isa => HashRef, required => 1 );
## path to our var/ :
has 'var' => ( is => 'ro', isa => Str,     required => 1 );

has 'etc' => ( is => 'ro', isa => Str, lazy => 1,
  default => sub { $_[0]->cfg->{path} }
);

has 'log'      => ( is => 'rw', isa => Object );
has 'loglevel' => ( 
  is => 'rw', isa => Str, 
  default => sub { 'info' } 
);

has 'detached' => ( is => 'ro', isa => Int, lazy => 1,
  default => sub { 0 },
);

has 'debug'    => ( 
  is => 'rw', isa => Int, 
  default => sub { 0 } 
);

## pure plugin convenience, ->VERSION is a better idea:
has 'version' => ( 
  is => 'ro', isa => Str, lazy => 1,
  default => sub { $Bot::Cobalt::Core::VERSION }
);

## Mostly used for W~ in Plugin::Info3 str formatting:
has 'url' => ( 
  is => 'ro', isa => Str,
  default => sub { "http://www.cobaltirc.org" },
);

## pulls hash from Bot::Cobalt::Lang->load_langset later
has 'lang' => ( is => 'rw', isa => HashRef );

has 'State' => (
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

## alias -> object:
has 'PluginObjects' => (
  is  => 'rw',  isa => HashRef,
  default => sub { {} },
);

## Some plugins provide optional functionality.
## The 'Provided' hash lets other plugins see if an event is available.
has 'Provided' => (
  is  => 'ro',  isa => HashRef,
  default => sub { {} },
);

has 'auth' => ( is => 'rw', isa => Object,
  default => sub {
    Bot::Cobalt::Core::ContextMeta::Auth->new
  },
);

has 'ignore' => ( is => 'rw', isa => Object,
  default => sub {
    Bot::Cobalt::Core::ContextMeta::Ignore->new
  },
);

extends 'POE::Component::Syndicator';

with 'Bot::Cobalt::Lang';

with 'Bot::Cobalt::Core::Role::Singleton';

with 'Bot::Cobalt::Core::Role::EasyAccessors';

with 'Bot::Cobalt::Core::Role::Unloader';

with 'Bot::Cobalt::Core::Role::Timers';

with 'Bot::Cobalt::Core::Role::IRC';

sub init {
  my ($self) = @_;

  my $newlogger = Log::Handler->create_logger("cobalt");
  my $maxlevel = $self->loglevel;
  $maxlevel = 'debug' if $self->debug;
  my $logfile = $self->cfg->{core}->{Paths}->{Logfile}
                // File::Spec->catfile( $self->var, 'cobalt.log' );
  $newlogger->add(
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

  $self->log($newlogger);

  ## Load configured langset (defaults to english)
  my $language = ($self->cfg->{core}->{Language} //= 'english');
  $self->lang( $self->load_langset($language) );

  unless ($self->detached) {
    $newlogger->add(
     screen => {
       log_to => "STDOUT",
       maxlevel => $maxlevel,
       timeformat     => "%Y/%m/%d %H:%M:%S",
       message_layout => "[%T] %L (%p) %m",
     },
    );
  }

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

        '_core_timer_check_pool',
      ],
    ],
  );

}

sub syndicator_started {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  $kernel->sig('INT'  => 'shutdown');
  $kernel->sig('TERM' => 'shutdown');
  $kernel->sig('HUP'  => 'sighup');

  $self->log->info('-> '.__PACKAGE__.' '.$self->version);
 
  ## add configurable plugins
  $self->log->info("-> Initializing plugins . . .");

  my $i = 0;
  my @plugins = sort {
    ($self->cfg->{plugins}->{$b}->{Priority}//1)
    <=>
    ($self->cfg->{plugins}->{$a}->{Priority}//1)
                } keys %{ $self->cfg->{plugins} };

  for my $plugin (@plugins)
  { 
    next if $self->cfg->{plugins}->{$plugin}->{NoAutoLoad};
    
    my $module = $self->cfg->{plugins}->{$plugin}->{Module};
    
    eval "require $module";
    if ($@) {
      $self->log->warn("Could not load $module: $@");
      $self->unloader_cleanup($module);
      next 
    }
    
    my $obj = $module->new();

    $self->PluginObjects->{$obj} = $plugin;

    unless ( $self->plugin_add($plugin, $obj) ) {
      $self->log->error("plugin_add failure for $plugin");
      delete $self->PluginObjects->{$obj};
      $self->unloader_cleanup($module);
      next
    }

    $self->is_reloadable($plugin, $obj);

    $i++;
  }

  $self->log->info("-> $i plugins loaded");

  $self->send_event('plugins_initialized', $_[ARG0]);

  $self->log->info("-> started, plugins_initialized sent");

  ## kickstart timer pool
  $kernel->yield('_core_timer_check_pool');
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
  $self->log->warn("Shutting down");
}

sub ev_plugin_error {
  my ($kernel, $self, $err) = @_[KERNEL, OBJECT, ARG0];
  
  ## Receives the same error as 'debug => 1' (in Syndicator init)
  
  $self->log->error("Plugin err: $err");

  ## syndicate a Bot_plugin_error
  ## FIXME: irc plugin to relay these to irc?
  $self->send_event( 'plugin_error', $err );
}

### Core low-pri timer

sub _core_timer_check_pool {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my $tick = $_[ARG0];
  ++$tick;

  ## Timers are provided by Core::Role::Timers

  my $timerpool = $self->TimerPool;
  
  TIMER: for my $id (keys %$timerpool) {
    my $timer = $timerpool->{$id};

    unless (blessed $timer && $timer->isa('Bot::Cobalt::Timer') ) {
      ## someone's been naughty
      $self->log->warn("not a Bot::Cobalt::Timer: $id (in tick $tick)");
      delete $timerpool->{$id};
      next TIMER
    }
    
    if ( $timer->execute_if_ready ) {
      my $event = $timer->event;
      $self->log->debug("timer execute; $id ($event) in tick $tick")
        if $self->debug > 1;

      $self->send_event( 'executed_timer', $id, $tick );
      $self->timer_del($id);
    }
  
  } ## TIMER
  
  ## most definitely not a high-precision timer.
  ## checked every second or so
  ## tracks timer pool ticks
  $kernel->alarm('_core_timer_check_pool' => time + 1, $tick);
}


## Moose-compatible 'no Moo'
no Moo; 1;
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

See:

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

=item *

L<Bot::Cobalt::Core::Role::Unloader>

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
  Bot::Cobalt::Core->instace(
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

L<http://www.cobaltirc.org>

=cut
