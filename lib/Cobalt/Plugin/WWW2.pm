package Cobalt::Plugin::WWW2;
our $VERSION = '0.001';

sub POE::Kernel::ASSERT_DEFAULT () { 1 }

use 5.12.1;
use strict;
use warnings;

use POE;
use POE::Session;
use POE::Filter::Reference;

use POE::Wheel::Run;

use Object::Pluggable::Constants qw/:ALL/;

use HTTP::Response;
use HTTP::Request;

use Cobalt::HTTP;

use Config;

use constant MAX_WORKERS => 3;  ## FIXME configurable?

sub new { bless {}, shift }

sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;
  $self->{core} = $core;
  $core->Provided->{www_request} = 1;
  $self->{WorkersByPID} = {};
  $self->{WorkersByWID} = {};
  
  ## Hashref mapping tags to pipeline events/args
  $self->{EventMap} = { };

  ## Array of arrays containing request_str, request_tag:
  $self->{PendingReqs} = [ ];

  $core->plugin_register($self, 'SERVER',
    [
      'www_request',
    ],
  );
  
  $core->log->info("Registered");

  $core->log->debug("Spawning POE session");
  
  POE::Session->create(
    object_states => [
      $self => [
        '_start',
        '_stop',
        '_master_shutdown',
  
        '_worker_spawn',      
        '_worker_input',
        '_worker_stderr',
        '_worker_error',
        '_worker_closed',
        '_worker_signal',
      ],
    ],
  );
 
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = splice @_, 0, 2;
  $core->Provided->{www_request} = 0;
  $poe_kernel->call('WWW' => '_master_shutdown');
  $core->log->info("Unregistered");
  return PLUGIN_EAT_NONE
}


sub Bot_www_request {
  my ($self, $core) = splice @_, 0, 2;
  $core->log->debug("www_request received");
  my $request = ${ $_[0] };
  my $event   = ${ $_[1] };
  my $ev_arg  = ${ $_[2] };
 
  unless ($request) {
    $core->log->debug("www_request received but no request");
    return PLUGIN_EAT_NONE
  }
  
  unless ($event) {
    ## no event at all is fairly legitimate
    ## (if you don't care if the request succeeds)
    $core->log->debug("HTTP req without event handler");
    $event = 'www_handled';
  }
  
  $ev_arg = [] unless $ev_arg;
  my @p = ( 'a' .. 'z', 'A' .. 'Z' );
  my $req_tag;
  do {
    $req_tag = join '', map { $p[rand@p] } 1 .. 8;
  } while exists $self->{EventMap}->{$req_tag};
  
  $self->{EventMap}->{$req_tag} = {
    Event => $event,
    EventArgs => $ev_arg,
  };
  
  $core->log->debug("www_request; $req_tag -> $event");

  ## add to pending request pool:
  push(@{ $self->{PendingReqs} },
    [ $request, $req_tag ]
  );

  $poe_kernel->post('WWW', '_worker_spawn');

  return PLUGIN_EAT_ALL
}


## Master's POE handlers
sub _start {
  my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];
  my $core = $self->{core};
  $kernel->alias_set('WWW');
  $core->log->debug("Session started");

}

sub _stop {
  my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];
  my $core = $self->{core};
  $core->log->debug("Session stopped");
  $kernel->alias_remove('WWW');
}

sub _master_shutdown {
  my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];
  $kernel->alias_remove('WWW');
  for my $wheelid (keys %{ $self->{WorkersByPID} }) {
    my $wheel = $self->{WorkersByPID}->{$wheelid};
    $wheel->kill(9);
  }
  $self->{PendingReqs} = [ ];
  $self->{WorkersByPID} = { };
  $self->{WorkersByWID} = { };
}

sub _worker_spawn {
  my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];
  my $core = $self->{core};  
  ## fork a worker generated by Cobalt::HTTP
  
  $core->log->debug("_worker_spawn called");

  ## do nothing if we have no requests
  ## (www_request will tell us when there is one)
  return unless @{ $self->{PendingReqs} };
  
  ## do nothing if we have too many workers already
  ## when one falls off a new one will pull pending
  my $workers = scalar keys %{ $self->{WorkersByPID} };
  return unless $workers < MAX_WORKERS;

  ## path to perl + suffix if applicable
  ## (see perldoc perlvar w.r.t $^X)
  my $perlpath = $Config{perlpath};
  if ($^O ne 'VMS') {
    $perlpath .= $Config{_exe}
      unless $perlpath =~ m/$Config{_exe}$/i;
  }

  ## Cobalt::HTTP->worker() (LWP bridge)
  my $forkable;
  unless ($^O eq "MSWin32") {
    $forkable = [
      $perlpath, (map { "-I$_" } @INC),
      '-MCobalt::HTTP', '-e',
      'Cobalt::HTTP->worker()'
    ];
  } else {
    $forkable = \&Cobalt::HTTP::worker;
  }

  $core->log->debug("spawning new wheel");

  my $wheel = POE::Wheel::Run->new(
    Program => $forkable,
    ErrorEvent  => '_worker_error',
    StdoutEvent => '_worker_input',
    StderrEvent => '_worker_stderr',
    CloseEvent  => '_worker_closed',
    StdioFilter => POE::Filter::Reference->new(),
  );
  
  my $wheel_id = $wheel->ID();
  my $pid = $wheel->PID();
  $kernel->sig_child($pid, "_worker_signal");
  
  $self->{WorkersByPID}->{$pid} = $wheel;
  $self->{WorkersByWID}->{$wheel_id} = $wheel;
  
  $core->log->debug("created new worker: pid $pid");
  
  ## feed this worker the top of the pending req stack
  my $pending = shift @{ $self->{PendingReqs} };
  my ($request, $req_tag) = @{ $pending };
  $wheel->put([ $request, $req_tag ]);
}

sub _worker_closed {
  ## stdout closed on worker
  my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];
  my $core = $self->{core};
  $core->log->debug("HTTP worker closed");
  my $wheelid = $_[ARG0];
  my $wheel = delete $self->{WorkersByWID}->{$wheelid};
  if (defined $wheel) {
    my $pid = $wheel->PID();
    $wheel->kill(9);
    delete $self->{WorkersByPID}->{$pid};
  }
  ## spawn another worker if there are pending requests
  $kernel->yield('_worker_spawn') if @{ $self->{PendingReqs} };
}

sub _worker_signal {
  ## child's gone (sig_chld handler)
  my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];
  my $pid = $_[ARG1];
  my $core = $self->{core};
  $core->log->debug("HTTP worker SIGCHLD; PID $pid");
  return unless $self->{WorkersByPID}->{$pid};
  my $wheel = delete $self->{WorkersByPID}->{$pid};
  if (defined $wheel) {
    my $wheelid = $wheel->ID();
    delete $self->{WorkersByWID}->{$wheelid};
  }
  $kernel->yield('_worker_spawn') if @{ $self->{PendingReqs} };
  return undef
}

sub _worker_input {
  my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];
  my $core = $self->{core};
  $core->log->debug("HTTP worker input on stdin");
  my $ref = $_[ARG0];

  my ($response_str, $tag) = @$ref;
  my $response = HTTP::Response->parse($response_str);
  
  unless (ref $response) {
    $core->log->warn("HTTP::Response obj could not be formed; tag $tag");
    ## FIXME create and return generic error response?
  }

  my $eventmap = delete $self->{EventMap}->{$tag};
  my $event   = $eventmap->{Event};
  my $ev_args = $eventmap->{EventArgs};

  $core->log->debug("dispatching $event ($tag)");

  my $content = $response->content || '';

  $core->send_event($event, $content, $response, $ev_args);  
}

sub _worker_stderr {
  my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];
  my ($err, $worker_wheelid) = @_[ARG0, ARG1];
  my $core = $self->{core};
  $core->log->warn("HTTP worker reported err: $err");  
  ## FIXME terminate this worker perhaps?
}

sub _worker_error {
  my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];
  my $core = $self->{core};
  my $op = $_[ARG0];
  $core->log->warn("HTTP worker error in $op");
}

1;