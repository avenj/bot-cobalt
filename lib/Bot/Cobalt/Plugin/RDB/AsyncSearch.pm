package Bot::Cobalt::Plugin::RDB::AsyncSearch;

use 5.10.1;
use strictures 1;

use POE qw/Wheel::Run Filter::Reference/;

sub new {

  POE::Session->create(
    object_states => [
      $self => [
        '_start',
        '_stop',
        
        'reap_all',
        
        'worker_err',
        'worker_input',
        'worker_stderr',
      ],
    ],
  
  );

}

sub _start {
  my ($self, $kernel) = @_[OBJECT, KERNEL];

}

sub _stop {
  my ($self, $kernel) = @_[OBJECT, KERNEL];
  $kernel->call( $_[SESSION], 'reap_all' );
}

sub reap_all {
  my ($self, $kernel) = @_[OBJECT, KERNEL];
  
}

sub worker_err {

}

sub worker_input {

}

sub worker_stderr {

}

1;
