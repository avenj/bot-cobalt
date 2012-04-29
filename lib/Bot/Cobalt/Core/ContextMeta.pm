package Bot::Cobalt::Core::ContextMeta;

## Base class for context-specific dynamic hashes
## (ignores, auth, .. )

use 5.10.1;
use strictures 1;

use Moo;
use Carp;

use Bot::Cobalt::Common qw/:types/;

has '_list' => ( is => 'rw', isa => HashRef,
  default => sub { {} },
);

sub add {
  my ($self, $context, $key, $meta) = @_;

  croak "add() needs at least a context and key"
    unless defined $context and defined $key;

  my $ref = {
    AddedAt => time(),
    Package => scalar caller,
  };

  if (ref $meta eq 'HASH') {
    $ref->{$_} = $meta->{$_} for keys %$meta;
  }
  
  $self->_list->{$context}->{$key} = $ref;

  return $key
}

sub clear {
  my ($self, $context) = @_;
  $self->_list({}) unless defined $context;
  delete $self->_list->{$context}  
}

sub del {
  my ($self, $context, $item) = @_;

  croak "del() needs a context and item"
    unless defined $context and defined $item;
  
  my $list = $self->_list->{$context} // return;

  return delete $list->{$item}   
}

1;

