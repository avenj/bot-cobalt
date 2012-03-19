package Cobalt::Core;
our $VERSION = '2.00_32';

use 5.12.1;
use Carp;
use Moose;
use MooseX::NonMoose;
use namespace::autoclean;

use Log::Handler;

use POE;
use Object::Pluggable::Constants qw(:ALL);

extends 'POE::Component::Syndicator',
        'Cobalt::Lang';

use Cobalt::IRC;

use Storable qw/dclone/;

### a whole bunch of attributes ...

## usually a hashref from Cobalt::Conf created via frontend:
has 'cfg' => ( is => 'rw', isa => 'HashRef', required => 1 );
## path to our var/ :
has 'var' => ( is => 'ro', isa => 'Str',     required => 1 );

## the Log::Handler instance:
has 'log'      => ( is => 'rw', isa => 'Object' );
has 'loglevel' => ( is => 'rw', isa => 'Str', default => 'info' );

## passed in via frontend, typically:
has 'debug'    => ( is => 'rw', isa => 'Int', default => 0 );
has 'detached' => ( is => 'ro', isa => 'Int', required => 1 );

## pure convenience, ->VERSION is a better idea:
has 'version' => ( is => 'ro', isa => 'Str', default => $VERSION );

## frontends can specify a bot url if they like
## (mostly used for W~ in Plugin::Info3 str formatting)
has 'url' => ( is => 'ro', isa => 'Str',
  default => "http://www.cobaltirc.org",
);

## pulls hash from Conf->load_langset later
## see Cobalt::Lang POD
has 'lang' => ( is => 'rw', isa => 'HashRef' );

has 'State' => (
  ## global 'heap' of sorts
  is => 'rw',
  isa => 'HashRef',
  default => sub {
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
  is  => 'rw',
  isa => 'HashRef',
  default => sub { {} },
);

## alias -> object:
has 'PluginObjects' => (
  is  => 'rw',  isa => 'HashRef',
  default => sub { {} },
);

## Servers->{$alias} = {
##   Name => servername,
##   PreferredNick => nick,
##   Object => poco-obj,
##   Connected => BOOL,
##   ConnectedAt => time(),
## }
has 'Servers' => (
  is  => 'rw',  isa => 'HashRef',
  default => sub { {} },
);

## Some plugins provide optional functionality.
## The 'Provided' hash lets other plugins see if an event is available.
has 'Provided' => (
  is  => 'rw',  isa => 'HashRef',
  default => sub { {} },
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


### Core timer pieces.

sub _core_timer_check_pool {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  ## Timer hash format:
  ##   Event => $event_to_syndicate,
  ##   Args => [ @event_args ],
  ##   ExecuteAt => $ts,
  ##   AddedBy => $caller,

  my $timerpool = $self->TimerPool;
  
  for my $id (keys %$timerpool) {
    my $timer = $timerpool->{$id};
     # this should never happen ...
     # ... unless a plugin author is a fucking idiot:
    unless (ref $timer eq 'HASH' && scalar keys %$timer) {
      $self->log->warn("broken timer, not a hash: $id");
      delete $timerpool->{$id};
      next
    }
    
    my $execute_ts = $timer->{ExecuteAt} // next;
    if ( $execute_ts <= time ) {
      my $event = $timer->{Event};
      my @args = @{ $timer->{Args} };
      $self->log->debug("timer execute: $id (ev: $event)")
        if $self->debug > 1;
      ## dispatch this event:
      $self->send_event( $event, @args ) if $event;
      ## send executed_timer to indicate this timer's done:
      $self->send_event( 'executed_timer', $id );
      delete $timerpool->{$id};
    }
  }

  ## most definitely NOT a high-precision timer.
  ## checked every second or so
  $kernel->alarm('_core_timer_check_pool' => time + 1);
}


sub timer_set {
  ## generic/easy timer set method
  ## $core->timer_set($delay, $event, $id)

  ## Returns timer ID on success

  ##  $delay should always be in seconds
  ##   (timestr_to_secs from Cobalt::Utils may help)
  ##  $event should be a hashref:
  ##   Type => 'event' || 'msg'
  ##  If Type is 'event':
  ##   Event => name of event to syndicate to plugins
  ##   Args => [ array of arguments to event ]
  ##  If Type is 'msg':
  ##   Context => server context (defaults to 'Main')
  ##   Target => target for privmsg
  ##   Text => text string for privmsg
  ##  $id is optional (randomized if unspecified)
  ##  if adding an existing id the old one will be deleted first.

  ##  Type options:
  ## TYPE = event
  ##   Event => "send_notice",  ## send notice example
  ##   Args  => [ ], ## optional array of args for event
  ## TYPE = msg
  ##   Target => $somewhere,
  ##   Text => $string,
  ##   Context => $server_context, # defaults to 'Main'

  ## for example, a random-ID timer to join a channel 60s from now:
  ##  my $id = timer_set( 60,
  ##    {
  ##      Type  => 'event', 
  ##      Event => 'join',
  ##      Args  => [ $context, $channel ],
  ##      Alias => $core->get_plugin_alias( $self ),
  ##    } 
  ##  );

  my ($self, $delay, $ev, $id) = @_;

  unless (ref $ev eq 'HASH') {
    $self->log->warn("timer_set not called with hashref in ".caller);
    return
  }

  ## automatically pick a unique id unless specified
  unless ($id) {
    my @p = ( 'a'..'z', 0..9 );
    do {
      $id = join '', map { $p[rand@p] } 1 .. 8;
    } while exists $self->TimerPool->{$id};    
  } else {
    ## an id was specified, overrule an existing by the same name
    delete $self->TimerPool->{$id};
  }

  my $type = $ev->{Type} // 'event';
  my($event_name, @event_args);
  given ($type) {

    when ("event") {
      unless (exists $ev->{Event}) {
        $self->log->warn("timer_set no Event specified in ".caller);
        return
      }
      $event_name = $ev->{Event};
      @event_args = @{ $ev->{Args} // [] };
    }

    when ([qw/msg message privmsg/]) {
      unless ($ev->{Text}) {
        $self->log->warn("timer_set no Text specified in ".caller);
        return
      }
      unless ($ev->{Target}) {
        $self->log->warn("timer_set no Target specified in ".caller);
        return
      }

      my $context = $ev->{Context} // 'Main';

      ## send_message $context, $target, $text
      $event_name = 'send_message';
      @event_args = ( $context, $ev->{Target}, $ev->{Text} );
    }
  }

  # tag w/ __PACKAGE__ if no alias is specified
  my $addedby = $ev->{Alias} // scalar caller;

  if ($event_name) {
    $self->TimerPool->{$id} = {
      ExecuteAt => time() + $delay,
      Event   => $event_name,
      Args    => [ @event_args ],
      AddedBy => $addedby,
    };
    $self->log->debug("timer_set; $id $delay $event_name")
      if $self->debug > 1;
    return $id
  } else {
    $self->log->debug("timer_set called but no timer added; bad type?");
    $self->log->debug("timer_set failure for ".join(' ', (caller)[0,2]) );
  }
  return
}

sub del_timer { timer_del(@_) }
sub timer_del {
  ## delete a timer by its ID
  ## doesn't care if the timerID actually exists or not.
  my ($self, $id) = @_;
  return unless $id;
  $self->log->debug("timer del; $id")
    if $self->debug > 1;
  return delete $self->TimerPool->{$id};
}

sub get_timer { timer_get(@_) }
sub timer_get {
  my ($self, $id) = @_;
  return unless $id;
  $self->log->debug("timer retrieved; $id")
    if $self->debug > 2;
  return $self->TimerPool->{$id};
}

sub timer_get_alias {
  ## get all timerIDs for this alias
  my ($self, $alias) = @_;
  return unless $alias;
  my @timers;
  my $timerpool = $self->TimerPool;
  for my $timerID (keys %$timerpool) {
    my $entry = $timerpool->{$timerID};
    push(@timers, $timerID) if $entry->{AddedBy} eq $alias;
  }
  return wantarray ? @timers : \@timers;
}

sub timer_del_alias {
  my ($self, $alias) = @_;
  return $alias;
  my $timerpool = $self->TimerPool;
  
  my @deleted;
  for my $timerID (keys %$timerpool) {
    my $entry = $timerpool->{$timerID};
    if ($entry->{AddedBy} eq $alias) {
      delete $timerpool->{$timerID};
      push(@deleted, $timerID);
    }
  }
  return wantarray ? @deleted : scalar @deleted ;
}

## FIXME timer_del_pkg is deprecated as of 2.00_18 and should go away
## (may clobber other timers if there are dupe modules)
## pkgs not declaring their alias in timer_set are on their own
sub timer_del_pkg {
  my $self = shift;
  my $pkg = shift || return;
  ## $core->timer_del_pkg( __PACKAGE__ )
  ## convenience method for plugins
  ## delete timers by 'AddedBy' package name
  ## (f.ex when unloading a plugin)
  for my $timer (keys %{ $self->TimerPool }) {
    my $ev = $self->TimerPool->{$timer};
    delete $self->TimerPool->{$timer}
      if $ev->{AddedBy} eq $pkg;
  }
}


### Accessors acting on State->{Auth}:

## Work is mostly done by Auth.pm or equivalent
## These are just easy ways to get at the hash.

sub auth_level {
  ## retrieve an auth level for $nickname in $context
  ## unidentified users get access level 0 by default
  my ($self, $context, $nickname) = @_;

  if (! $context) {
    $self->log->debug("auth_level called but no context specified");
    $self->log->debug("returning undef to ".join(' ', (caller)[0,2] ) );
    return undef
  } elsif (! $nickname) {
    $self->log->debug("auth_level called but no nickname specified");
    $self->log->debug("returning undef to ".join(' ', (caller)[0,2] ) );
    return undef
  }

  ## We might have proper args but no auth for this user
  ## That makes them level 0:
  return 0 unless exists $self->State->{Auth}->{$context};
  my $context_rec = $self->State->{Auth}->{$context};
  return 0 unless exists $context_rec->{$nickname};
  my $level = $context_rec->{$nickname}->{Level} // 0;

  return $level
}

sub auth_user { auth_username(@_) }
sub auth_username {
  ## retrieve an auth username by context -> IRC nick
  ## retval is undef if user can't be found
  my ($self, $context, $nickname) = @_;

  if (! $context) {
    $self->log->debug("auth_username called but no context specified");
    $self->log->debug("returning undef to ".join(' ', (caller)[0,2] ) );
    return undef
  } elsif (! $nickname) {
    $self->log->debug("auth_username called but no nickname specified");
    $self->log->debug("returning undef to ".join(' ', (caller)[0,2] ) );
    return undef
  }

  return undef unless exists $self->State->{Auth}->{$context};
  my $context_rec = $self->State->{Auth}->{$context};

  return undef unless exists $context_rec->{$nickname};
  my $username = $context_rec->{$nickname}->{Username};

  return $username
}

sub auth_flags {
  ## retrieve auth flags by context -> IRC nick
  ##
  ## untrue if record can't be found
  ##
  ## otherwise you get a reference to the Flags hash in Auth
  ##
  ## this means you can modify flags:
  ##  my $flags = $core->auth_flags($context, $nick);
  ##  $flags->{SUPERUSER} = 1;

  my ($self, $context, $nickname) = @_;

  return unless exists $self->State->{Auth}->{$context};
  my $context_rec = $self->State->{Auth}->{$context};

  return unless exists $context_rec->{$nickname};
  return unless ref $context_rec->{$nickname}->{Flags} eq 'HASH';
  return $context_rec->{$nickname}->{Flags};
}

sub auth_pkg {
  ## retrieve the __PACKAGE__ that provided this user's auth
  ## (in other words, the plugin that created the hash)
  my ($self, $context, $nickname) = @_;

  return unless exists $self->State->{Auth}->{$context};
  my $context_rec = $self->State->{Auth}->{$context};

  return unless exists $context_rec->{$nickname};
  my $pkg = $context_rec->{$nickname}->{Package};

  return $pkg ? $pkg : ();
}

### Ignores (->State->{Ignored})

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



__PACKAGE__->meta->make_immutable;
no Moose; 1;
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
