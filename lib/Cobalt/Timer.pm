package Cobalt::Timer;

use 5.10.1;
use Carp;
use Moo;
use Sub::Quote;
use MooX::Types::MooseLike::Base qw/:all/;

## my $timer = Cobalt::Core::Item::Timer->new(
##   core  => $core,
##   delay => $secs,
##   event => $event,
##   args  => $args,
##   alias => $alias
## );

has 'core'  => ( is => 'rw', isa => Object, required => 1 );

## Must provide either an absolute time or a delta from now
has 'at'    => ( is => 'rw', isa => Num, default => quote_sub q{0} );
has 'delay' => ( is => 'rw', isa => Num,
  trigger => sub {
    my ($self, $value) = @_;
    $self->at( time() + $value );
  }, 
);

has 'event' => ( is => 'rw', isa => Str );

has 'args'  => ( is => 'rw', isa => ArrayRef, 
  default => quote_sub q{[]},
);

has 'alias' => ( is => 'rw', isa => Str,
  default => sub { scalar caller }, 
);

has 'context' => ( is => 'rw', isa => Str, 
  default => quote_sub q{'Main'},
);

has 'text'    => ( is => 'rw', isa => Str );
has 'target'  => ( is => 'rw', isa => Str );

has 'type'  => ( is => 'rw', isa => Str, lazy => 1, 
  trigger => sub {
    my ($self, $value) = @_;
    given (lc($value)) {
      when ([qw/msg message privmsg action/]) {
        my $ev_name = $value eq 'action' ? 
            'send_action' : 'send_message' ;
        my @ev_args = ( $self->context, $self->target, $self->text );
        $self->args( \@ev_args );
        $self->event( $ev_name );
      }
      
      default { carp "Unknown type $value" }

    }
  },
);

## FIXME sanity-checking BUILD ?

sub execute {
  my ($self) = @_;
  my $args = $self->args;
  $self->core->send_event( $self->event, @$args );
}

sub is_ready {
  my ($self) = @_;
  return 1 if $self->at <= time;
  return
}

sub execute_if_ready { execute_ready(@_) }
sub execute_ready {
  my ($self) = @_;
  if ($self->at <= time) {
    my $args = $self->args;
    $self->core->send_event( $self->event, @$args );
    return 1
  }
  return
}


1;
