package Bot::Cobalt::Core::ContextMeta::Ignore;
our $VERSION = '0.016001';

use 5.10.1;
use strictures 1;

use Carp;
use Moo;

use IRC::Utils qw/normalize_mask/;
use Bot::Cobalt::Common qw/:types/;

extends 'Bot::Cobalt::Core::ContextMeta';

around 'add' => sub {
  my $orig = shift;
  my ($self, $context, $mask, $reason, $addedby) = @_;
  
  my ($pkg, $line) = (caller)[0,2];
  
  confess "Missing arguments in ignore add()"
    unless defined $context and defined $mask;
  
  $mask    = normalize_mask($mask);
  $addedby = $pkg unless defined $addedby;
  $reason  = "Added by $pkg" unless defined $reason;

  my $meta = {
    AddedBy => $addedby,
    Reason  => $reason,
  };

  $self->$orig($context, $mask, $meta)
};

sub reason {
  my ($self, $context, $mask) = @_;
  
  return unless exists $self->_list->{$context}
            and exists $self->_list->{$context}->{$mask};

  return $self->_list->{$context}->{$mask}->{Reason}
}

sub addedby {
  my ($self, $context, $mask) = @_;
  return unless exists $self->_list->{$context}
            and exists $self->_list->{$context}->{$mask};
  
  return $self->_list->{$context}->{$mask}->{AddedBy}
}

1;
__END__

=pod

=head1 NAME

Bot::Cobalt::Core::ContextMeta::Ignores - Ignore list management

=head1 SYNOPSIS

  FIXME

=head1 DESCRIPTION

A L<Bot::Cobalt::Core::ContextMeta> subclass for managing an ignore 
list.

This is used by L<Bot::Cobalt::Core> to 
provide a global ignore list for use by L<Cobalt::IRC> and the core 
plugin set.

=head2 add

  ->add($context, $mask, $reason, $addedby)

Add a new ignore list entry for a specified mask.

At least a mask and reason must be specified; 'Reason' and 'AddedBy' can 
be used to tag ignore entries.

=head2 reason

  ->reason($context, $mask)

Returns preserved Reason for specified mask.

=head2 addedby

  ->addedby($context, $mask)

Returns preserved AddedBy for specified mask.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

L<http://www.cobaltirc.org>

=cut
