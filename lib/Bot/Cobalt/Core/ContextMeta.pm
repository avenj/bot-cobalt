package Bot::Cobalt::Core::ContextMeta;
our $VERSION = '0.001';

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
  my ($self, $context, $key) = @_;

  croak "del() needs a context and item"
    unless defined $context and defined $key;
  
  my $list = $self->_list->{$context} // return;

  return delete $list->{$key}   
}

sub fetch {
  my ($self, $context, $key) = @_;
  
  croak "fetch() needs a context and key"
    unless defined $context and defined $key;

  return unless exists $self->_list->{$context};
  return $self->_list->{$context}->{$key}  
}

sub list {
  my $self = shift;
  wantarray ? $self->list_as_array(@_) : $self->list_as_ref(@_)
}

## Less ambiguous list methods.

sub list_as_array {
  my $self = shift;
  my $listref = $self->list_as_ref(@_);
  keys %$listref
}

sub list_as_ref {
  my ($self, $context) = @_;
  $context ? $self->_list->{$context} : $self->_list ;
}

1;
__END__

=pod

=head1 NAME

Bot::Cobalt::Core::ContextMeta - Base class for context-related metadata

=head1 SYNOPSIS

  $cmeta->add($context, $key, $ref);
  
  $cmeta->del($context, $key);
  
  $cmeta->clear($context);
  
  $cmeta->list($context);

=head1 DESCRIPTION

This is the ContextMeta base class, providing some easy per-context hash 
management methods to subclasses such as 
L<Bot::Cobalt::Core::ContextMeta::Auth> and 
L<Bot::Cobalt::Core::ContextMeta::Ignore>.

L<Bot::Cobalt::Core> uses ContextMeta subclasses to provide B<auth> and 
B<ignore> attributes.

=head2 add

  ->add($context, $key, $meta_ref)

Add a new item; subclasses will usually use a custom constructor to 
provide a custom metadata hashref as the third argument.

=head2 del

  ->del($context, $key)

Delete a specific item.

=head2 clear

  ->clear()
  
  ->clear($context)

Clear a specified context entirely.

With no arguments, clear everything we know about every context.

=head2 fetch

  ->fetch($context, $key)

Retrieve the 'meta' hash reference for a specified key.

=head2 list

In list context, returns the list of keys:

  my @contexts = $cmeta->list;
  my @ckeys    = $cmeta->list($context);

In scalar context, returns the actual hash reference (if it exists).

=head2 list_as_ref

Less-ambiguous alternative to L</list> -- always get a hash reference.

=head2 list_as_array

Less-ambiguous alternative to L</list> -- always get a list of keys.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

L<http://www.cobaltirc.org>

=cut
