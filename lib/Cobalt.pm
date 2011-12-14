package Cobalt;

our $VERSION = '2.0_001';

use 5.14.1;
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

has 'cfg' => (
  is => 'rw',
  isa => 'HashRef',
  required => 1,
);

has 'log' => (
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
  ## FIXME
  ## should read $Language.yml out of etc/langs
  ## need standardized format
  ## pull hash from Conf->load_langset
  is => 'rw',
  isa => 'HashRef',
);

has 'TimerPool' => (
  is => 'rw',
  isa => 'HashRef',
  default => sub {
    return({
      DatabasesDirty => 0,
    }),
  },
);

## the core IRC plugin is single-server
## however a MultiServer plugin is possible
## track hashes for our servers here.
## Servers->{$alias} = {
##   Name => servername,
##   PreferredNick => nick,
##   Object => poco-obj,
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
                // $self->etc . "/cobalt.log" ;
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

         # db sync check timer
        'timer_check_db',
      ],
    ],
  );

}

sub syndicator_started {
  my ($kernel, $self) = @_[KERNEL, OBJECT];

  $kernel->sig('INT'  => 'shutdown');
  $kernel->sig('TERM' => 'shutdown');

  ## FIXME load databases

  $self->log->info('-> '.__PACKAGE__.' '.$self->version);
  $self->log->info("-> Loading Core IRC module");
  $self->plugin_add('IRC', Cobalt::IRC->new);

  $poe_kernel->yield('timer_check_db');

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
  ## FIXME db write
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


sub timer_check_db {
  my ($kernel, $self) = @_[KERNEL, OBJECT];


  ## FIXME


  $kernel->alarm('timer_check_db' => time + 5);
}



__PACKAGE__->meta->make_immutable;
no Moose; 1;
