package Bot::Cobalt::Core::Role::Ignore;
our $VERSION = '0.200_48';

use 5.10.1;
use strict;
use warnings;
use Moo::Role;

use IRC::Utils qw/normalize_mask/;

requires qw/
  log
  debug
  State
/;

sub ignore_add {
  my ($self, $context, $mask, $reason, $username) = @_;

  my ($pkg, $line) = (caller)[0,2];
  unless (defined $context && defined $mask) {
    $self->log->debug("ignore_add missing arguments in $pkg ($line)");
    return
  }

  my $ignore = $self->State->{Ignored}->{$context} //= {};

  $mask   = normalize_mask($mask);
  
  $reason   = "Added by $pkg" unless $reason;
  $username = $pkg unless defined $username;

  $ignore->{$mask} = {
    AddedBy => $username,
    AddedAt => time(),
    Reason  => $reason,
  };
  
  return $mask
}

sub ignore_del {
  my ($self, $context, $mask) = @_;

  unless (defined $context && defined $mask) {
    my ($pkg, $line) = (caller)[0,2];
    $self->log->debug("ignore_del missing arguments in $pkg ($line)");
    return
  }

  my $ignore = $self->State->{Ignored}->{$context} // return;

  unless (exists $ignore->{$mask}) {
    my ($pkg, $line) = (caller)[0,2];
    $self->log->debug("ignore_del; no such mask in $pkg ($line)");
    return
  }

  return delete $ignore->{$mask};
}

sub ignore_list {
  my ($self, $context) = @_;

  my $ignorelist;
  if ($context) {
    $ignorelist = $self->State->{Ignored}->{$context} // {};
  } else {
    $ignorelist = $self->State->{Ignored}//{};
  }

  return wantarray ? keys %$ignorelist : $ignorelist
}

1;
__END__

=pod

=head1 NAME

Bot::Cobalt::Core::Role::Ignore - A role for managing an ignore list

=head1 SYNOPSIS

  my $listref = $core->ignore_list;
  my @ignores = $core->ignore_list;

  if ( $core->ignore_add($context, $mask, $reason, $added_by) ) {
    ## Ignore entry added
  }

  if( $core->ignore_del($context, $mask) ) {
    ## Ignore entry deleted
  }

=head1 DESCRIPTION

A Moo role for managing a plugin-controlled "ignore list."

Consumed by L<Bot::Cobalt::Core> to provide methods for manipulating the 
global ignore list; L<Bot::Cobalt::IRC> makes use of this to disregard 
incoming messages.

=head1 METHODS

=head2 ignore_list

In list context, returns the list of ignored masks for the specified 
context (or the list of contexts if no context was specified).

In scalar context, returns the reference to the actual ignore hash (or 
the context's reference, if one was specified)

=head2 ignore_add

Add an ignored mask to the specified context's list.

At least a context and mask must be specified.

Optionally, a reason and "added by" (usually username for user-issued 
ignores or __PACKAGE__ for automated ignores) can be specified.

=head2 ignore_del 

Delete an ignored mask from the specified context's list.

A context and mask must be specified. Returns the deleted entry on 
success, undef if it could not be found.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

L<http://www.cobaltirc.org>

=cut
