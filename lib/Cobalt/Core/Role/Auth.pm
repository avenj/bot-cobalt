package Cobalt::Core::Role::Auth;

use 5.10.1;
use strict;
use warnings;
use Moo::Role;

requires qw/
  log
  debug
  State
/;

## Work is mostly done by Auth.pm or equivalent
## These are just easy ways to get at the hash.

sub auth_level {
  ## retrieve an auth level for $nickname in $context
  ## unidentified users get access level 0 by default
  my ($self, $context, $nickname) = @_;

  if (! $context) {
    $self->log->debug("auth_level called but no context specified");
    $self->log->debug("returning undef to ".join(' ', (caller)[0,2] ) );
    return undef
  } elsif (! $nickname) {
    $self->log->debug("auth_level called but no nickname specified");
    $self->log->debug("returning undef to ".join(' ', (caller)[0,2] ) );
    return undef
  }

  ## We might have proper args but no auth for this user
  ## That makes them level 0:
  return 0 unless exists $self->State->{Auth}->{$context};
  my $context_rec = $self->State->{Auth}->{$context};

  return 0 unless exists $context_rec->{$nickname};
  my $level = $context_rec->{$nickname}->{Level} // 0;

  return $level
}

sub auth_user { auth_username(@_) }
sub auth_username {
  ## retrieve an auth username by context -> IRC nick
  ## retval is undef if user can't be found
  my ($self, $context, $nickname) = @_;

  if (! $context) {
    $self->log->debug("auth_username called but no context specified");
    $self->log->debug("returning undef to ".join(' ', (caller)[0,2] ) );
    return undef
  } elsif (! $nickname) {
    $self->log->debug("auth_username called but no nickname specified");
    $self->log->debug("returning undef to ".join(' ', (caller)[0,2] ) );
    return undef
  }

  return undef unless exists $self->State->{Auth}->{$context};
  my $context_rec = $self->State->{Auth}->{$context};

  return undef unless exists $context_rec->{$nickname};
  my $username = $context_rec->{$nickname}->{Username};

  return $username
}


sub auth_flags {
  ## retrieve auth flags by context -> IRC nick
  ##
  ## untrue if record can't be found
  ##
  ## otherwise you get a reference to the Flags hash in Auth
  ##
  ## this means you can modify flags:
  ##  my $flags = $core->auth_flags($context, $nick);
  ##  $flags->{SUPERUSER} = 1;

  my ($self, $context, $nickname) = @_;

  return unless exists $self->State->{Auth}->{$context};
  my $context_rec = $self->State->{Auth}->{$context};

  return unless exists $context_rec->{$nickname};
  return unless ref $context_rec->{$nickname}->{Flags} eq 'HASH';

  return $context_rec->{$nickname}->{Flags}
}

sub auth_pkg {
  ## retrieve the __PACKAGE__ that provided this user's auth
  ## (in other words, the plugin that created the hash)
  my ($self, $context, $nickname) = @_;

  return unless exists $self->State->{Auth}->{$context};
  my $context_rec = $self->State->{Auth}->{$context};

  return unless exists $context_rec->{$nickname};
  my $pkg = $context_rec->{$nickname}->{Package};

  return $pkg ? $pkg : ()
}


1;

