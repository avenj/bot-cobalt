package Bot::Cobalt::Core::ContextMeta;
our $VERSION = '0.200_48';

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

has 'core' => ( is => 'rw', isa => Object, lazy => 1,
  default => sub {
    require Bot::Cobalt::Core;
    croak "No Cobalt::Core instance found"
      unless Bot::Cobalt::Core->is_instanced;
    Bot::Cobalt::Core->instance
  },
);

sub add {
  my ($self, $context, $key, $meta) = @_;

  croak "add() needs at least a context and key"
    unless defined $context and defined $key;

  my $ref = {
    AddedAt => time(),
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

sub list {
  my ($self, $context) = @_;
  my $list = $context ? $self->_list->{$context} : $self->_list ;
  
  return wantarray ? keys(%$list) : $list ;
}

1;

