package Bot::Cobalt::DB::Async;
our $VERSION = '0.200_48';

use 5.10.1;
use strictures 1;

use POE qw/Wheel::Run Filter::Reference/;

use Moo;

has 'SessionID' => ( is => 'rw', lazy => 1 
  predicate => 'has_session',
);

## hnn..
## .. rather than a forked worker, which sucks ..
## provide simple POE session interface to running extended searches?
## DB::SearchAsync ?


sub BUILD {
  my ($self) = @_;
  
  POE::Session->create(
    object_states => [
      $self => [
        '_start',
        '_stop',
        
        'asdb_shutdown',
        
        'asdb_sigint',
        
        'asdb_worker_input',
        'asdb_worker_stderr',
        'asdb_worker_closed',
        'asdb_worker_error',
        'asdb_worker_sigchld',
      ],
    ],
  );
}


sub _start {
  my ($self, $session, $kernel) = @_[OBJECT, SESSION, KERNEL];
  
  $self->SessionID( $session->ID );
  
  $kernel->sig('INT', 'asdb_sigint');
  $kernel->sig('TERM', 'asdb_sigint');

  
}

## FIXME be sure to always kill TERM before kill KILL

1;
