package Cobalt;

our $VERSION = '2.0_002';

use 5.12.1;
use Moose;
use MooseX::NonMoose;

use POE;

use Carp;

use Log::Handler;

use Object::Pluggable::Constants qw(:ALL);

use namespace::autoclean;

extends 'POE::Component::Syndicator',
        'Cobalt::Lang';

use Cobalt::IRC;

## a whole bunch of attributes ...

has 'cfg' => (
  is => 'rw',
  isa => 'HashRef',
  required => 1,
);

has 'var' => (
  ## path to our var/
  is => 'rw',
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
  is => 'rw',
  isa => 'Int',
  required => 1,
);

has 'version' => (
  is => 'ro',
  isa => 'Str',
  default => $VERSION,
);

has 'lang' => (
  ## should read $Language.yml out of etc/langs
  ## fixme; need some kind of schema ..
  ## pull hash from Conf->load_langset
  is => 'rw',
  isa => 'HashRef',
);

has 'State' => (
  ## global 'heap' of sorts
  is => 'rw',
  isa => 'HashRef',
  default => sub {
    {
      StartedTS => time(),
      Counters => {
        Sent => 0,
      },
      Auth => { },
      Ignored => { },
    } 
  },
);

has 'TimerPool' => (
  ## timers; see timer_check_pool and timer_set methods
  is => 'rw',
  isa => 'HashRef',
  default => sub { 
    {
      TIMERS => { },
    } 
  },
);

## the core IRC plugin is single-server
## however a MultiServer plugin is possible
## track hashes for our servers here.
## Servers->{$alias} = {
##   Name => servername,
##   PreferredNick => nick,
##   Object => poco-obj,
##   Connected => BOOL,
##   ConnectedAt => time(),
## }

has 'Servers' => (
  is => 'rw',
  isa => 'HashRef',
  default => sub { {} },
);

sub init {
  my ($self) = @_;

  my $language = $self->cfg->{core}->{Language}
    // croak "missing Language directive?" ;
  $self->lang( $self->load_langset($language) );

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
#    debug => 1,
    prefix => 'ev_',  ## event prefix for sessions
    reg_prefix => 'Cobalt_',
    types => [ SERVER => 'Bot', USER => 'OUT' ],
    options => { },
    object_states => [
      $self => [
        'syndicator_started',
        'syndicator_stopped',
        'shutdown',
        'ev_plugin_error',

        'timer_check_pool',
      ],
    ],
  );

}

sub syndicator_started {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  $kernel->sig('INT'  => 'shutdown');
  $kernel->sig('TERM' => 'shutdown');

  $self->log->info('-> '.__PACKAGE__.' '.$self->version);
  $self->log->info("-> Loading Core IRC module");
  $self->plugin_add('IRC', Cobalt::IRC->new);

  ## add configurable plugins
  $self->log->info("-> Initializing plugins . . .");

  my $i = 0;
  for my $plugin (sort keys %{ $self->cfg->{plugins} })
  { 
    my $module = $self->cfg->{plugins}->{$plugin}->{Module};
    eval "require $module";
    if ($@)
      { $self->log->warn("Could not load $module: $@"); next; }
    my $obj = $module->new();
    $self->plugin_add($plugin, $obj);
    $i++;
  }

  $self->log->info("-> $i plugins loaded");

  $self->send_event('plugins_initialized', $_[ARG0]);

  $self->log->info("-> started, plugins_initialized sent");
}

sub shutdown {
  my $self = $_[OBJECT];

  $self->_syndicator_destroy();
}

sub syndicator_stopped {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  $self->log->warn("Shutting down");
}

sub ev_plugin_error {
  my ($kernel, $self, $err) = @_[KERNEL, OBJECT, ARG0];
  $self->log->warn("Plugin err: $err");
  croak "Plugin error: $err";
}


### Core timer pieces.

sub timer_check_pool {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  ## Timer hash format:
  ##   Execute => $coderef,
  ##   ExecuteAt => $ts,
  ##   AddedBy => $caller,

  for my $id (keys $self->TimerPool->{TIMERS}) {
    my $timer = $self->TimerPool->{TIMERS}->{$id};
    my $execute_ts = $timer->{ExecuteAt};
    if ( $execute_ts <= time ) {
      $timer->{Execute}->();
      delete $self->TimerPool->{TIMERS}->{$id};
    }
  }

  $kernel->alarm('timer_check_pool' => time + 1);
}


sub timer_set {
  ## generic/easy timer set method
  ## $core->timer_set($delay, $event, $id)

  ##  $delay should always be in seconds
  ##   (timestr_to_secs from Cobalt::Utils may help)
  ##  $event should be a hashref:
  ##   Type => <ONE OF: code, event, msg>
  ##  see Type Options below for more info on these $event opts:
  ##   Code =>
  ##   Event =>
  ##   Args =>
  ##   Target =>
  ##   Content =>
  ##  $id is optional
  ##  if adding an existing id the old one will be deleted first.

  ##  Type options:
  ## TYPE = code
  ##   Code => $coderef,
  ## TYPE = event
  ##   Event => "send_to_context",  # Bot_send_to_context example
  ##   Args  => [ ], ## optional array of args for event
  ## TYPE = msg
  ##   Context => $server_context,
  ##   Target => $somewhere,
  ##   Text => $string,

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

  # assume coderef if no Type specified
  # makes it easier to just do something like:
  #  ->timer_set( 60, { Code => $coderef } )
  my $type = $ev->{Type} // 'code';
  my $coderef;
  given ($type) {
    when ("code") {
      ## coderef was specified.
      unless (exists $ev->{Code} && ref $ev->{Code} eq 'CODE') {
        $self->log->warn("timer_set no coderef specified in ".caller);
        return
      }
      $coderef = $ev->{Code};
    }

    when ("event") {

      unless (exists $ev->{Event}) {
        $self->log->warn("timer_set no Event specified in ".caller);
        return
      }

      $coderef = sub {
        $self->send_event( $ev->{Event}, @{$ev->{Args}} );
      };

    }

    when ("msg") {
      unless ($ev->{Text}) {
        $self->log->warn("timer_set no Text specified in ".caller);
        return
      }
      unless ($ev->{Target}) {
        $self->log->warn("timer_set no Target specified in ".caller);
        return
      }

      my $context = 'Main' unless $ev->{Context};

      $coderef = sub {
        my $msg = {
          context => $context,
          target => $ev->{Target},
          txt => $ev->{Text},
        };
        $self->send_event( 'send_to_context', $msg );
      };

    }

  }

  if ($coderef) {
    $self->TimerPool->{TIMERS}->{$id} = {
      ExecuteAt => time() + $delay,
      Execute => $coderef,
      AddedBy => scalar caller(),
    };
  } else {
    $self->log->warn("timer_set called but no timer added?");
  }

}

sub timer_del {
  my $self = shift;
  my $id = shift || return;
  return delete $self->TimerPool->{TIMERS}->{$id};
}

sub timer_del_pkg {
  my $self = shift;
  my $pkg = shift || return;
  my @dead_timers;
  ## delete timers by 'AddedBy' package name
  ## (f.ex when unloading a plugin)
  for my $timer (keys $self->TimerPool->{TIMERS}) {
    my $ev = $self->TimerPool->{TIMERS}->{$timer};

    delete $self->TimerPool->{TIMERS}->{$timer}
      if $ev->{AddedBy} eq $pkg;
  }
}


### Core Auth pieces.
## Work is mostly done by Auth.pm or equivalent
## These are just easy ways to get at the hash.

sub auth_level {
  ## FIXME standardize State->{Auth} hash
}




__PACKAGE__->meta->make_immutable;
no Moose; 1;
