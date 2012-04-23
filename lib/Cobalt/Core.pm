package Cobalt::Core;
our $VERSION = '2.00_42';

use 5.10.1;
use Carp;

use Moo;
use Sub::Quote;

use Log::Handler;

use POE;
use Object::Pluggable::Constants qw(:ALL);

use Cobalt::IRC;
use Cobalt::Common;

use Storable qw/dclone/;

extends 'POE::Component::Syndicator',
        'Cobalt::Lang';

with 'Cobalt::Core::Role::Timers';
with 'Cobalt::Core::Role::Auth';

### a whole bunch of attributes ...

## usually a hashref from Cobalt::Conf created via frontend:
has 'cfg' => ( is => 'rw', isa => HashRef, required => 1 );
## path to our var/ :
has 'var' => ( is => 'ro', isa => Str,     required => 1 );

## the Log::Handler instance:
has 'log'      => ( is => 'rw', isa => Object );
has 'loglevel' => ( 
  is => 'rw', isa => Str, 
  default => quote_sub q{ 'info' } 
);

## passed in via frontend, typically:
has 'detached' => ( is => 'ro', isa => Int, required => 1 );
has 'debug'    => ( 
  is => 'rw', isa => Int, 
  default => quote_sub q{ 0 } 
);

## pure convenience, ->VERSION is a better idea:
has 'version' => ( 
  is => 'ro', isa => Str, lazy => 1,
  default => sub { $VERSION }
);

## frontends can specify a bot url if they like
## (mostly used for W~ in Plugin::Info3 str formatting)
has 'url' => ( 
  is => 'ro', isa => Str,
  default => quote_sub q{ "http://www.cobaltirc.org" },
);

## pulls hash from Conf->load_langset later
## see Cobalt::Lang POD
has 'lang' => ( is => 'rw', isa => HashRef );

has 'State' => (
  ## global 'heap' of sorts
  is => 'rw',
  isa => HashRef,
  default => quote_sub q{
    {
      ## {HEAP} is here for convenience with no guarantee regarding 
      ## collisions
      ## may be useful for plugins to share some info bits
      ## . . . better to interact strictly via events
      HEAP => { },
    
      StartedTS => time(),
      Counters => {
        Sent => 0,
      },
      # each server context should set up its own Auth->{$context} hash:
      Auth => { },    ## ->{$context}->{$nickname} = { . . .}
      Ignored => { }, ##             ->{$mask} = { . . . }
      
      # nonreloadable plugin list keyed on alias for plugin mgrs:
      NonReloadable => { },
    } 
  },
);

has 'TimerPool' => (
  ## timers; see _core_timer_check_pool and timer_set methods
  is  => 'rw',  isa => HashRef,
  default => quote_sub q{ {} },
);

## alias -> object:
has 'PluginObjects' => (
  is  => 'rw',  isa => HashRef,
  default => quote_sub q{ {} },
);

## Servers->{$alias} = {
##   Name => servername,
##   PreferredNick => nick,
##   Object => poco-obj,
##   Connected => BOOL,
##   ConnectedAt => time(),
## }
has 'Servers' => (
  is  => 'rw',  isa => HashRef,
  default => quote_sub q{ {} },
);

## Some plugins provide optional functionality.
## The 'Provided' hash lets other plugins see if an event is available.
has 'Provided' => (
  is  => 'rw',  isa => HashRef,
  default => quote_sub q{ {} },
);

sub init {
  my ($self) = @_;

  my $logger = Log::Handler->create_logger("cobalt");
  my $maxlevel = $self->loglevel;
  $maxlevel = 'debug' if $self->debug;
  my $logfile = $self->cfg->{core}->{Paths}->{Logfile}
                // $self->var . "/cobalt.log" ;
  $logger->add(
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

  $self->log($logger);

  ## Load configured langset (defaults to english)
  my $language = ($self->cfg->{core}->{Language} //= 'english');
  $self->lang( $self->load_langset($language) );

  unless ($self->detached) {
    $logger->add(
     screen => {
       log_to => "STDOUT",
       maxlevel => $maxlevel,
       timeformat     => "%Y/%m/%d %H:%M:%S",
       message_layout => "[%T] %L (%p) %m",
     },
    );
  }

  $self->_syndicator_init(
#    debug => 1,  ## shouldfix; enable on higher debug level?
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
  my $self = $_[OBJECT];
  $self->log->warn("Shutdown called, destroying syndicator");
  $self->_syndicator_destroy();
}

sub syndicator_stopped {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  $self->log->warn("Shutting down");
}

sub ev_plugin_error {
  my ($kernel, $self, $err) = @_[KERNEL, OBJECT, ARG0];
  $self->log->warn("Plugin err: $err");
  ## syndicate a Bot_plugin_error
  ## FIXME: irc plugin to relay these to irc?
  $self->send_event( 'plugin_error', $err );
}


### Plugin utils

sub is_reloadable {
  my ($self, $alias, $obj) = @_;
  
  if ($obj and ref $obj) {
    ## passed an object
    ## see if the object is marked non-reloadable
    ## if it is, update State
    if ( $obj->{NON_RELOADABLE} || 
       ( $obj->can("NON_RELOADABLE") && $obj->NON_RELOADABLE() )
    ) {
      $self->log->debug("Marked plugin $alias non-reloadable");
      $self->State->{NonReloadable}->{$alias} = 1;
      ## not reloadable, return 0
      return 0
    } else {
      ## reloadable, return 1
      delete $self->State->{NonReloadable}->{$alias};
      return 1
    }
  }
  ## passed just an alias (or a bustedass object)
  ## return whether the alias is reloadable
  return 0 if $self->State->{NonReloadable}->{$alias};
  return 1
}

sub unloader_cleanup {
  ## clean up symbol table after a module load fails miserably
  ## (or when unloading)
  my ($self, $module) = @_;

  $self->log->debug("cleaning up after $module (unloader_cleanup)");

  my $included = join( '/', split /(?:'|::)/, $module ) . '.pm';  
  
  $self->log->debug("removing from INC: $included");
  delete $INC{$included};
  
  { no strict 'refs';

    @{$module.'::ISA'} = ();
    my $s_table = $module.'::';
    for my $symbol (keys %$s_table) {
      next if $symbol =~ /\A[^:]+::\z/;
      delete $s_table->{$symbol};
    }
  
  }
  
  $self->log->debug("finished module cleanup");
  return 1
}

### Core low-pri timer

sub _core_timer_check_pool {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my $tick = $_[ARG0];
  ++$tick;

  ## Timer hash format:
  ##   Event => $event_to_syndicate,
  ##   Args => [ @event_args ],
  ##   ExecuteAt => $ts,
  ##   AddedBy => $caller,
  ## Timers are provided by Core::Role::Timers

  my $timerpool = $self->TimerPool;
  
  for my $id (keys %$timerpool) {
    my $timer = $timerpool->{$id};
     # this should never happen ...
     # ... unless a plugin author is a fucking idiot:
    unless (ref $timer eq 'HASH' && scalar keys %$timer) {
      $self->log->warn("broken timer, not a hash: $id (in tick $tick)");
      delete $timerpool->{$id};
      next
    }
    
    my $execute_ts = $timer->{ExecuteAt} // next;
    if ( $execute_ts <= time ) {
      my $event = $timer->{Event};
      my @args = @{ $timer->{Args} };
      $self->log->debug("timer execute: $id (ev: $event) [tick $tick]")
        if $self->debug > 1;
      ## dispatch this event:
      $self->send_event( $event, @args ) if $event;
      ## send executed_timer to indicate this timer's done:
      $self->send_event( 'executed_timer', $id, $tick );
      delete $timerpool->{$id};
    }
  }

  ## most definitely not a high-precision timer.
  ## checked every second or so
  ## tracks timer pool ticks
  $kernel->alarm('_core_timer_check_pool' => time + 1, $tick);
}


### Ignores (->State->{Ignored})

## FIXME role
## FIXME documentation
sub ignore_add {
  my ($self, $context, $username, $mask, $reason) = @_;
  
  my ($pkg, $line) = (caller)[0,2];
  unless (defined $context && defined $username && defined $mask) {
    $self->log->debug("ignore_add missing arguments in $pkg ($line)");
    return
  }

  my $ignore = $self->State->{Ignored}->{$context} //= {};

  $mask   = normalize_mask($mask);
  $reason = "added by $pkg" unless $reason;

  $ignore->{$mask} = {
    AddedBy => $username,
    AddedAt => time(),
    Reason  => $reason,
  };
}

sub ignore_del {
  my ($self, $context, $mask) = @_;

  unless (defined $context && defined $mask) {
    my ($pkg, $line) = (caller)[0,2];
    $self->log->debug("ignore_del missing arguments in $pkg ($line)");
    return  
  }

  my $ignore = $self->State->{Ignored}->{$context} // return;
  
  unless (exists $ignore->{$mask}) {
    my ($pkg, $line) = (caller)[0,2];
    $self->log->debug("ignore_del; no such mask in $pkg ($line)");
    return
  }
  
  return delete $ignore->{$mask};
}

sub ignore_list {
  my ($self, $context) = @_;
  ## apply scalar context if you want the hashref for this context:
  my $ignorelist = $self->State->{Ignored}->{$context} // {};
  return wantarray ? keys %$ignorelist : $ignorelist ;
}


### Accessors acting on ->Servers:

sub is_connected {
  my ($self, $context) = @_;
  return unless $context and exists $self->Servers->{$context};
  return $self->Servers->{$context}->{Connected};
}

sub get_irc_server  { get_irc_context(@_) }
sub get_irc_context {
  my ($self, $context) = @_;
  return unless $context and exists $self->Servers->{$context};
  return $self->Servers->{$context}
}

sub get_irc_object { get_irc_obj(@_) }
sub get_irc_obj {
  ## retrieve our POE::Component::IRC obj for $context
  my ($self, $context) = @_;
  if (! $context) {
    $self->log->debug("get_irc_obj called but no context specified");
    $self->log->debug("returning empty list to ".join(' ', (caller)[0,2]) );
    return
  }

  my $c_hash = $self->get_irc_context($context);
  unless ($c_hash && ref $c_hash eq 'HASH') {
    $self->log->debug("get_irc_obj called but context $context not found");
    $self->log->debug("returning empty list to ".join(' ', (caller)[0,2]) );
    return
  }

  my $irc = $c_hash->{Object} // return;
  return ref $irc ? $irc : ();
}

sub get_irc_casemap {
  my ($self, $context) = @_;
  if (! $context) {
    $self->log->debug("get_irc_casemap called but no context specified");
    $self->log->debug("returning empty list to ".join(' ', (caller)[0,2]) );
    return
  }
  
  my $c_hash = $self->get_irc_context($context);
  unless ($c_hash && ref $c_hash eq 'HASH') {
    $self->log->debug("get_irc_casemap called but context $context not found");
    $self->log->debug("returning empty list to ".join(' ', (caller)[0,2]) );
    return
  }

  my $map = $c_hash->{CaseMap} // 'rfc1459';
  return $map
}


### Accessors acting on ->cfg:

sub get_core_cfg {
  ## Get (a copy of) $core->cfg->{core}:
  my ($self) = @_;
  my $corecfg = dclone($self->cfg->{core});
  return $corecfg
}

sub get_channels_cfg {
  my ($self, $context) = @_;
  unless ($context) {
    $self->log->debug("get_channels_cfg called but no context specified");
    $self->log->debug("returning undef to ".join(' ', (caller)[0,2]) );
    return undef
  } 
  ## Returns empty hash if there's no conf for this channel:
  my $chcfg = dclone( $self->cfg->{channels}->{$context} // {} );
  return $chcfg
}

sub get_plugin_alias {
  my ($self, $plugobj) = @_;
  return undef unless ref $plugobj;
  my $alias = $self->PluginObjects->{$plugobj} || undef;
  return $alias
}

sub get_plugin_cfg {
  my ($self, $plugin) = @_;
  ## my $plugcf = $core->get_plugin_cfg( $self )
  ## Returns undef if no cfg was found
  
  my $alias;

  if (ref $plugin) {
    ## plugin obj (theoretically) specified
    $alias = $self->PluginObjects->{$plugin};
    unless ($alias) {
      $self->log->error("No alias for $plugin");
      return
    }
  } else {
    ## string alias specified
    $alias = $plugin;
  }

  unless ($alias) {
    $self->log->error("get_plugin_cfg: no plugin alias? ".scalar caller);
    return
  }
  
  ## Return empty hash if there is no loaded config for this alias
  my $plugin_cf = $self->cfg->{plugin_cf}->{$alias} // return {};
  
  unless (ref $plugin_cf eq 'HASH') {
    $self->log->debug("get_plugin_cfg; $alias cfg not a HASH");
    return
  }
  
  ## return a copy, not a ref to the original.
  ## that way we can worry less about stupid plugins breaking things
  my $cloned = dclone($plugin_cf);
  return $cloned
}



no Moo; 1;
__END__

=pod

=head1 NAME

Cobalt::Core - Cobalt2 IRC bot core

=head1 DESCRIPTION

This module is the core of B<Cobalt2>, tying an event syndicator (via 
L<POE::Component::Syndicator> and L<Object::Pluggable>) into a 
L<Log::Handler> instance, configuration manager, and other useful tools.

Public methods are documented in L<Cobalt::Manual::Plugins/"Core methods">

You probably want to consult the following documentation:

=over

=item *

L<Cobalt::Manual::Plugins> - Writing Cobalt plugins

=item *

L<Cobalt::IRC> - IRC bridge / events

=item *

L<Cobalt::Manual::PluginDist> - Distributing Cobalt plugins

=back

=head1 Custom frontends

It's actually possible to write custom frontends to spawn a Cobalt 
instance; Cobalt::Core just needs to be initialized with a valid 
configuration hash and spawned via L<POE::Kernel>'s run() method.

A configuration hash is typically created by L<Cobalt::Conf>:

  my $cconf = Cobalt::Conf->new(
    etc => $path_to_etc_dir,
  );
  my $cfg_hash = $cconf->read_cfg;

. . . then passed to Cobalt::Core before the POE kernel is started:

  ## Set up Cobalt::Core's POE session:
  Cobalt::Core->new(
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
