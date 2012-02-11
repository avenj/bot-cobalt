package Cobalt::Core;
our $VERSION = '2.00_18';

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

## a whole bunch of attributes ...

has 'cfg' => (
  is => 'rw',
  isa => 'HashRef',
  required => 1,
);

has 'var' => (
  ## path to our var/
  is => 'ro',
  isa => 'Str',
  required => 1,
);

has 'log' => (
  ## the Log::Handler instance
  is => 'rw',
  isa => 'Object',
);

has 'loglevel' => (
  is => 'rw',
  isa => 'Str',
  default => 'info',
);

has 'debug' => (
  is => 'rw',
  isa => 'Int',
  default => 0,
);

has 'detached' => (
  is => 'ro',
  isa => 'Int',
  required => 1,
);

has 'version' => (
  is => 'ro',
  isa => 'Str',
  default => $VERSION,
);

has 'url' => (
  is  => 'ro',
  isa => 'Str',
  default => "http://www.cobaltirc.org",
);

has 'lang' => (
  ## pull hash from Conf->load_langset
  ## see Cobalt::Lang POD
  is => 'rw',
  isa => 'HashRef',
);

has 'State' => (
  ## global 'heap' of sorts
  is => 'rw',
  isa => 'HashRef',
  default => sub {
    {
      ## non-core plugins can make use of State->{HEAP}
      ## care should be taken to use specific naming..
      ## this is here for convenience with no guarantee regarding 
      ## collisions
      HEAP => { },
    
      StartedTS => time(),
      Counters => {
        Sent => 0,
      },
     # each server context should set up its own Auth->{$context} hash:
      Auth => { },   ## ->{$context}->{$nickname} = {}
      Ignored => { },
      
     # nonreloadable plugin list keyed on alias for plugin mgrs
      NonReloadable => { },
    } 
  },
);

has 'TimerPool' => (
  ## timers; see _core_timer_check_pool and timer_set methods
  is  => 'rw',
  isa => 'HashRef',
  default => sub { 
    {
      TIMERS => { },
    } 
  },
);

has 'PluginObjects' => (
  is  => 'rw',
  isa => 'HashRef',
  default => sub { {} },
);

## the core IRC plugin is single-server
## however a MultiServer plugin is possible (and planned)
## thusly, track hashes for our servers here.
## Servers->{$alias} = {
##   Name => servername,
##   PreferredNick => nick,
##   Object => poco-obj,
##   Connected => BOOL,
##   ConnectedAt => time(),
## }
has 'Servers' => (
  is  => 'rw',
  isa => 'HashRef',
  default => sub { {} },
);

## Some plugins provide optional functionality.
## The 'Provided' hash lets other plugins see if an event is available.
has 'Provided' => (
  is  => 'rw',
  isa => 'HashRef',
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

  if ($self->detached)
  {
    close(STDERR);
    close(STDOUT);
    open(STDERR,'>>', $logfile)
      or $self->log->warn("Could not redirect STDERR");
    open(STDOUT,'>>', $logfile)
      or $self->log->warn("Could not redirect STDOUT");
  }
  else
  {
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

sub syndicator_started {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  $kernel->sig('INT'  => 'shutdown');
  $kernel->sig('TERM' => 'shutdown');
  $kernel->sig('HUP'  => 'shutdown');

  $self->log->info('-> '.__PACKAGE__.' '.$self->version);
  $self->log->info("-> Loading Core IRC module");
  my $irc_obj = Cobalt::IRC->new();
  $self->plugin_add('IRC', $irc_obj);
  $self->is_reloadable('IRC', $irc_obj);

  ## add configurable plugins
  $self->log->info("-> Initializing plugins . . .");

  my $i = 0;
  my @plugins = sort {
    ($self->cfg->{plugins}->{$b}->{Priority}//1)
    <=>
    ($self->cfg->{plugins}->{$a}->{Priority}//1)
                } keys %{ $self->cfg->{plugins} };
  for my $plugin (sort keys %{ $self->cfg->{plugins} })
  { 
    next if $self->cfg->{plugins}->{$plugin}->{NoAutoLoad};
    
    my $module = $self->cfg->{plugins}->{$plugin}->{Module};
    
    eval "require $module";
    if ($@)
      { $self->log->warn("Could not load $module: $@"); next }
    
    my $obj = $module->new();
    $self->PluginObjects->{$obj} = $plugin;
    unless ( $self->plugin_add($plugin, $obj) ) {
      $self->log->error("plugin_add failure for $plugin");
      delete $self->PluginObjects->{$obj};
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

  my $timerpool = $self->TimerPool->{TIMERS};
  
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
      $self->log->debug("timer execute: $id (ev: $event)");
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
  ##  timer_set( 60,
  ##    {
  ##      Type => 'event', 
  ##      Event => 'join',
  ##      Args => [ $context, $channel ],
  ##    } 
  ##  );

  my ($self, $delay, $ev, $id) = @_;

  unless (ref $ev eq 'HASH') {
    $self->log->warn("timer_set not called with hashref in ".caller);
    return
  }

  ## automatically pick a unique id unless specified
  unless ($id) {
    my @p = ('a' .. 'z', 'A' .. 'Z', 0 .. 9);
    do {
      $id = join '', map { $p[rand@p] } 1 .. 8;
    } while exists $self->TimerPool->{TIMERS}->{$id};    
  } else {
    ## an id was specified, overrule an existing by the same name
    delete $self->TimerPool->{TIMERS}->{$id};
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

  if ($event_name) {
    $self->TimerPool->{TIMERS}->{$id} = {
      ExecuteAt => time() + $delay,
      Event => $event_name,
      Args => [ @event_args ],
      AddedBy => scalar caller(),
    };
    $self->log->debug("timer_set; $id $delay $event_name");
    return $id
  } else {
    $self->log->debug("timer_set called but no timer added; bad type?");
    $self->log->debug("returning empty list to ".join(' ', (caller)[0,2]) );
  }

}

sub timer_del {
  ## delete a timer by its ID
  my $self = shift;
  my $id = shift || return;
  $self->log->debug("timer del; $id");
  return delete $self->TimerPool->{TIMERS}->{$id};
}

## FIXME: timer_del_pkg is deprecated as of 2.00_18 and should go away
## (may clobber other timers if there are dupe modules)
sub timer_del_pkg {
  my $self = shift;
  my $pkg = shift || return;
  ## $core->timer_del_pkg( __PACKAGE__ )
  ## convenience method for plugins
  ## delete timers by 'AddedBy' package name
  ## (f.ex when unloading a plugin)
  for my $timer (keys %{ $self->TimerPool->{TIMERS} }) {
    my $ev = $self->TimerPool->{TIMERS}->{$timer};
    delete $self->TimerPool->{TIMERS}->{$timer}
      if $ev->{AddedBy} eq $pkg;
  }
}


### Accessors acting on State->{Auth}:

## Work is mostly done by Auth.pm or equivalent
## These are just easy ways to get at the hash.

sub auth_level {
  ## retrieve an auth level for $nickname in $context
  ## unidentified users get access level 0 by default
  ## FIXME: configurable default access level
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

  ## We might have proper args but no auth for this user:

  return 0 unless exists $self->State->{Auth}->{$context};
  my $context_rec = $self->State->{Auth}->{$context};

  return 0 unless exists $context_rec->{$nickname};
  my $level = $context_rec->{$nickname}->{Level} // 0;

  return $level
}

sub auth_user { auth_username(@_) }
sub auth_username {
  ## retrieve an auth username by context -> IRC nick
  ## retval is boolean untrue if user can't be found
  my ($self, $context, $nickname) = @_;

  if (! $context) {
    $self->log->debug("auth_username called but no context specified");
    $self->log->debug("returning empty list to ".join(' ', (caller)[0,2] ) );
    return
  } elsif (! $nickname) {
    $self->log->debug("auth_username called but no nickname specified");
    $self->log->debug("returning empty list to ".join(' ', (caller)[0,2] ) );
    return
  }

  return unless exists $self->State->{Auth}->{$context};
  my $context_rec = $self->State->{Auth}->{$context};

  return unless exists $context_rec->{$nickname};
  my $username = $context_rec->{$nickname}->{Username};

  return $username ? $username : ();
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


### Accessors acting on ->Servers:

sub get_irc_obj {
  ## retrieve our POE::Component::IRC obj for $context
  my ($self, $context) = @_;
  if (! $context) {
    $self->log->debug("get_irc_obj called but no context specified");
    $self->log->debug("returning empty list to ".join(' ', (caller)[0,2]) );
    return
  }
  elsif (! exists $self->Servers->{$context} ) {
    $self->log->debug("get_irc_obj called but context $context not found");
    $self->log->debug("returning empty list to ".join(' ', (caller)[0,2]) );
    return
  }

  my $irc = $self->Servers->{$context}->{Object} // return;
  return ref $irc ? $irc : ();
}

sub get_irc_casemap {
  my ($self, $context) = @_;
  if (! $context) {
    $self->log->debug("get_irc_casemap called but no context specified");
    $self->log->debug("returning empty list to ".join(' ', (caller)[0,2]) );
    return
  }
  elsif (! exists $self->Servers->{$context} ) {
    $self->log->debug("get_irc_casemap called but context $context not found");
    $self->log->debug("returning empty list to ".join(' ', (caller)[0,2]) );
    return
  }

  my $map = $self->Servers->{$context}->{CaseMap} // 'rfc1459';
  return $map
}

sub get_irc_server {
  ## return a REF to the hash for this server context.
  my ($self, $context) = @_;
  if (! $context) {
    $self->log->debug("get_irc_server called but no context specified");
    $self->log->debug("returning empty list to ".join(' ', (caller)[0,2]) );
    return
  }
  elsif (! exists $self->Servers->{$context} ) {
    $self->log->debug("get_irc_server called but context $context not found");
    $self->log->debug("returning empty list to ".join(' ', (caller)[0,2]) );
    return
  }

  return $self->Servers->{$context};  
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

sub get_plugin_cfg {
  my ($self, $plugin) = @_;
  ## my $plugcf = $core->get_plugin_cfg( $self )
  ## Returns undef if no cfg was found
  
  my $alias;

  if (ref $plugin) {
    ## plugin obj (theoretically) specified
#    (my $plugobj, $alias) = $self->pipeline->get($plugin);
#    unless ($plugobj) {
#      $self->log->error("get_plugin_cfg; pipeline->get failure");
#      return undef
#    }
    $alias = $self->PluginObjects->{$plugin};
    unless ($alias) {
      $core->log->error("No alias for $plugin");
      return undef
    }
  } else {
    ## string alias specified
    $alias = $plugin;
  }

  unless ($alias) {
    $self->log->error("get_plugin_cfg: no plugin alias? ".scalar caller);
    return undef
  }
  
  my $plugin_cf = $self->cfg->{plugin_cf}->{$alias} // return;
  
  unless (ref $plugin_cf eq 'HASH') {
    $self->log->debug("get_plugin_cfg; $alias cfg not a HASH");
    return undef
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
L<Log::Handler> instance and other useful tools.

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

FIXME

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

L<http://www.cobaltirc.org>

=cut
