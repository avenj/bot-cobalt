package Cobalt::Timer;

use strict; use warnings;
use 5.10.1;
use Carp;
use Moo;
use MooX::Types::MooseLike::Base qw/:all/;

## my $timer = Cobalt::Core::Item::Timer->new(
##   core  => $core,
##   delay => $secs,
##   event => $event,
##   args  => $args,
##   alias => $alias
## );

has 'core'  => ( is => 'rw', isa => Object, required => 1 );

## May have a timer ID specified at construction for use by 
## timer pool managers; if not, creating IDs is up to them.
## (See ::Core::Role::Timers)
## This can be any value, but most often a string or number.
has 'id' => ( is => 'rw', lazy => 1, predicate => 'has_id' );

## Must provide either an absolute time or a delta from now
has 'at'    => ( is => 'rw', isa => Num, lazy => 1, 
  default => sub { 0 } 
);
has 'delay' => ( is => 'rw', isa => Num, lazy => 1,
  default => sub { 0 },
  trigger => sub {
    my ($self, $value) = @_;
    $self->at( time() + $value );
  }, 
);

has 'event' => ( is => 'rw', isa => Str, lazy => 1,
  predicate => 'has_event',
);

has 'args'  => ( is => 'rw', isa => ArrayRef, lazy => 1,
  default => sub { [] },
);

has 'alias' => ( is => 'rw', isa => Str, lazy => 1,
  default => sub { scalar caller }, 
);

has 'context' => ( is => 'rw', isa => Str, lazy => 1,
  default   => sub { 'Main' },
  predicate => 'has_context',
);

has 'text'    => ( is => 'rw', isa => Str, lazy => 1, 
  predicate => 'has_text' 
);

has 'target'  => ( is => 'rw', isa => Str, lazy => 1, 
  predicate => 'has_target' 
);

has 'type'  => ( is => 'rw', isa => Str, lazy => 1,
  default => sub {
    my ($self) = @_;
    
    if ($self->has_context && $self->has_target) {
      ## Guessing we're a message.
      return 'msg' 
    } else {
      ## Guessing we're an event.
      return 'event'
    }
  },
  
  trigger => sub {
    my ($self, $value) = @_;
    $value = lc($value);
    $value = 'msg' if $value ~~ [qw/message privmsg/];
  },
); 


sub _process_type {
  my ($self) = @_;
  ## If this is a special type, set up event and args.
  my $type = lc($self->type);
  
  if ($type ~~ [qw/msg message privmsg action/]) {
    my $ev_name = $type eq 'action' ? 
          'send_action' : 'send_message' ;
    my @ev_args = ( $self->context, $self->target, $self->text );
    $self->args( \@ev_args );
    $self->event( $ev_name );
  }

  return 1
}

sub is_ready {
  my ($self) = @_;
  return 1 if $self->at <= time;
  return
}

sub execute {
  my ($self) = @_;
  $self->_process_type;
  
  unless ( $self->event ) {
    carp "timer execute called but no event specified";
    return
  }
  
  unless ( $self->core->can('send_event') ) {
    carp "timer execute called but specified core can't send_event";
    return
  }
  
  my $args = $self->args;
  $self->core->send_event( $self->event, @$args );
  return 1
}

sub execute_if_ready { execute_ready(@_) }
sub execute_ready {
  my ($self) = @_;
  return $self->execute if $self->is_ready;
  return
}


1;
