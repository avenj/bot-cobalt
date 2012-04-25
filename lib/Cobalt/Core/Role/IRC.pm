package Cobalt::Core::Role::IRC;

use strict; use warnings;
use 5.10.1;
use Moo::Role;

use Scalar::Util qw/blessed/;

requires qw/
  log
  debug
  Servers
/;


sub is_connected {
  my ($self, $context) = @_;
  return unless $context and exists $self->Servers->{$context};
  return $self->Servers->{$context}->connected;
}

sub get_irc_server  { get_irc_context(@_) }
sub get_irc_context {
  my ($self, $context) = @_;
  return unless $context and exists $self->Servers->{$context};
  return $self->Servers->{$context}
}

sub get_irc_object { get_irc_obj(@_) }
sub get_irc_obj {
  ## retrieve our POE::Component::IRC obj for $context
  my ($self, $context) = @_;
  if (! $context) {
    $self->log->warn(
      "get_irc_obj called with no context at "
        .join ' ', (caller)[0,2]
    );
    return
  }

  my $c_obj = $self->get_irc_context($context);
  unless ($c_obj && blessed $c_obj) {
    $self->log->warn(
      "get_irc_obj called but context $context not found at "
        .join ' ', (caller)[0,2]
    );
    return
  }

  my $irc = $c_obj->irc // return;
  return blessed $irc ? $irc : ();
}

sub get_irc_casemap {
  my ($self, $context) = @_;
  if (! $context) {
    $self->log->warn(
      "get_irc_casemap called with no context at "
        .join ' ', (caller)[0,2]
    );
    return
  }

  my $c_obj = $self->get_irc_context($context);
  unless ($c_obj && blessed $c_obj) {
    $self->log->warn(
      "get_irc_casemap called but context $context not found at "
        .join ' ', (caller)[0,2]      
    );
    return
  }

  return $c_obj->casemap
}


1;
