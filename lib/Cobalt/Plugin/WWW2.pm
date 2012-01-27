package Cobalt::Plugin::WWW2;
our $VERSION = '0.001';

use 5.12.1;
use strict;
use warnings;

use POE;

use POE::Filter::Reference;

use POE::Wheel::ReadWrite;
use POE::Wheel::Run;
use POE::Wheel::SocketFactory;

use Object::Pluggable::Constants qw/:ALL/;

use constant WORKERS => 1;  ## FIXME configurable?

sub new { bless {}, shift }

sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;
  $self->{core} = $core;
  $self->{Workers} = {};
  $core->plugin_register($self, 'SERVER',
    [
      'www_request',
    ],
  );
  
  POE::Session->create(
    object_states => [
      '_start',
      '_stop',
      
      '_worker_input',
      '_worker_stderr',
      '_worker_error',
    ], 
  );
 
  $core->log->info("Registered");
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = splice @_, 0, 2;
  $core->log->info("Unregistered");
  return PLUGIN_EAT_NONE
}


sub Bot_www_request {
  my ($self, $core) = splice @_, 0, 2;

  ## post this to the 'WWW' session?  

  return PLUGIN_EAT_ALL
}


## Master's POE handlers
sub _start {
  my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];
  my $core = $self->{core};
  $kernel->alias_set('WWW');
  $core->log->debug("Session started");
}

sub _worker_spawn {
  my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];

  my $wheel = POE::Wheel::Run->new(
    Program => \&_UA,
    ErrorEvent  => '_worker_error',
    StdoutEvent => '_worker_input',
    StderrEvent => '_worker_stderr',
    StdioFilter => POE::Filter::Reference->new(),
  );
  
  my $wheel_id = $wheel->ID();
  
  $self->{Workers}->{$wheel_id} = $wheel;
  
  $core->log->debug("Initialization complete, waiting for requests");
}

sub _stop {
  my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];
  my $core = $self->{core};
  $core->log->debug("Cleaning up workers");
  $self->{Workers}->{$_}->kill('TERM')
    for keys %{ $self->{Workers} };
  $core->log->debug("Session stopped");
  $kernel->alias_remove('WWW');
}

sub sigchld {
  print " SIGCHLD\n";  ## FIXME sig_chld ?
}

sub _worker_input {
  my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];
  my $core = $self->{core};
  
  my $ref = $_[ARG0];
  
  ## FIXME should've gotten back a stringified HTTP::Response
  ## convert it back to an object if we can
}

sub _worker_stderr {
  my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];
  my $core = $self->{core};
  my ($err, $worker_wheelid) = @_[HEAP, ARG0, ARG1];
  ## FIXME terminate this worker?
}

sub _worker_error {
  my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];
  my $core = $self->{core};

}

## FIXME
##  maintain pool of HTTP::Requests to process
##  fork a worker that accepts stringified requests and sends back request->as_string?
##  (de)stringify on master end?
##  fork one per req up to MAX, ability for bored child to query for more requests before
##   dying?


## worker
sub _UA {


}



1;
