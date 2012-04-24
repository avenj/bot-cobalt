package Cobalt::Core::Role::Ignore;

use 5.10.1;
use strict;
use warnings;
use Moo::Role;

requires qw/
  log
  debug
  State
/;

sub ignore_add {
  my ($self, $context, $username, $mask, $reason) = @_;

  my ($pkg, $line) = (caller)[0,2];
  unless (defined $context && defined $username && defined $mask) {
    $self->log->debug("ignore_add missing arguments in $pkg ($line)");
    return
  }

  my $ignore = $self->State->{Ignored}->{$context} //= {};

  $mask   = normalize_mask($mask);
  $reason = "added by $pkg" unless $reason;

  $ignore->{$mask} = {
    AddedBy => $username,
    AddedAt => time(),
    Reason  => $reason,
  };
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
  ## apply scalar context if you want the hashref for this context:
  my $ignorelist = $self->State->{Ignored}->{$context} // {};
  return wantarray ? keys %$ignorelist : $ignorelist ;
}


1;
__END__

=pod

=head1 NAME

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 AUTHOR

=cut
