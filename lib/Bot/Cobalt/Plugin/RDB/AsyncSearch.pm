package Bot::Cobalt::Plugin::RDB::AsyncSearch;

use 5.10.1;
use Carp;
use strictures 1;

use POE qw/Wheel::Run Filter::Reference/;

sub spawn {
  my $self = shift;
  my %args = @_;
  $args{lc $_} = delete $args{$_} for keys %args;
  
  unless ($args{errorevent} && $args{resultevent}) {
    croak "Need an ErrorEvent and ResultEvent in spawn()"
  }

  my $sess = POE::Session->create(
    heap => {
      ErrorEvent  => delete $args{errorevent},
      ResultEvent => delete $args{resultevent},
      
      EventMap => {},
      Pending  => [],
      
      Wheels => {
        PID => {},
        WID => {},
      },
    },

    object_states => [
      $self => [
        '_start',
        '_stop',
        
        'shutdown',

        'search_rdb',
        
        'push_pending',
        
        'reap_all',
        
        'worker_err',
        'worker_input',
        'worker_stderr',
        'worker_sigchld',
      ],
    ],
  
  );

  return $sess->ID()
}

sub _start {
  my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];

  $kernel->refcount_increment( 
    $_[SESSION]->ID(), 'Waiting for requests'
  );
}

sub _stop {
  my ($self, $kernel) = @_[OBJECT, KERNEL];
  $kernel->call( $_[SESSION], 'reap_all' );
}

sub shutdown {
  my ($self, $kernel, $heap) = @_[OBJECT, KERNEL];
  $kernel->call( $_[SESSION], 'reap_all' );
  $kernel->refcount_decrement( 
    $_[SESSION]->ID(), 'Waiting for requests'
  );
}

sub search_rdb {
  my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];
  my ($dbpath, $regex) = @_[ARG0, ARG1];

  my $sender = $_[SENDER];
  
  unless ($dbpath && $regex) {
    carp "search_rdb posted but no path or regex specified";
    return
  }
  
  my @p = ( 'a' .. 'z', 1 .. 9 );
  my $unique = join '', map { $p[rand@p] } 1 .. 6;
  $unique .= $p[rand@p] while exists $heap->{EventMap}->{$unique};
  
  my $item = {
    Path   => $dbpath,
    Tag    => $unique,
    Regex  => $regex,
    SenderID => $sender->ID(),
  };
  
  $heap->{EventMap}->{$unique} = $item;
  
  push(@{ $heap->{Pending} }, $item );
  
  $kernel->yield('push_pending');
}

sub push_pending {
  my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP]:
  ## do nothing if we have too many workers
  ## try to pull pending in sigchld handler ?

  my $running = keys %{ $heap->{Wheels}->{PID} };
  
  if ($running > 5) {
    ## FIXME alarm() and return
  }
  
  my $next_item = shift @{ $heap->{Pending} };
  my $tag = $next_item->{Tag};
  
  ## try to spawn a new wheel
  
}

sub reap_all {
  my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];
  ## do nothing if we have no workers  
  ## otherwise try to send terminal signal
}

sub worker_input {
  ## FIXME post to SenderID
}

sub worker_sigchld {
  ## FIXME worker's gone, try to pull pending?
}

sub worker_err {

}

sub worker_stderr {

}

1;
