package Cobalt::IRC;

## Core IRC plugin

use 5.14.1;
use strict;
use warnings;
use Carp;
use Object::Pluggable::Constants qw( :ALL );

use Moose;

use POE;
use POE::Component::IRC::State;
use POE::Component::IRC::Plugin::CTCP;
use POE::Component::IRC::Plugin::AutoJoin;
use POE::Component::IRC::Plugin::Connector;
use POE::Component::IRC::Plugin::NickServID;
use POE::Component::IRC::Plugin::NickReclaim;

has 'core' => (
  is => 'rw',
  isa => 'Object',
);

has 'irc' => (
  is => 'rw',
  isa => 'Object',
);


sub Cobalt_register {
  my ($self, $core) = @_;

  $self->core($core);

  ## register for events
  $core->plugin_register($self, 'SERVER',
    [ 'all' ],
  );

  $self->core->log->info(__PACKAGE__." registered");
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = @_;
  $core->log->info("Unregistering core IRC plugin");
  return PLUGIN_EAT_NONE
}

sub _start_irc {
  my ($self) = @_;
  my $pkg = __PACKAGE__;
  $self->core->log->info(" --> $pkg spawning IRC");
  my $cfg = $self->core->cfg->{core};

  my @servers = @{ $cfg->{IRC}->{Servers} //= [ 'irc.cobaltirc.org 6667' ] };
  my ($server, $port) = split ' ', $servers[0];  ## FIXME

  my $i = POE::Component::IRC::State->spawn(
    nick => $cfg->{IRC}->{Nickname} || 'Cobalt2',
    username => $cfg->{IRC}->{Username} || 'cobalt2',
    ircname  => $cfg->{IRC}->{Realname}  || 'http://cobaltirc.org',
    server   => $server || 'irc.cobaltirc.org',
    port     => $port || 6667,
    raw => 0,
  ) or $self->core->log->emerg("poco-irc error: $!");


  $self->core->Servers->{Main} = {
    Name => $server,
    Object => $i,
    ConnectedAt => time(),
  };

  $self->irc($i);

  POE::Session->create(
    object_states => [
      $self => [
        '_start',
        'irc_chan_sync',
        'irc_public',
      ],
    ],
  );
}

sub Bot_plugins_initialized {
  my ($self, $core) = splice @_, 0, 2;
  ## wait until plugins are all loaded, start IRC session
  $self->_start_irc();
  return PLUGIN_EAT_NONE
}

 ### IRC EVENTS ###

sub _start {

}

sub irc_chan_sync {

}

sub irc_public {

}

## FIXME moar


 ### COBALT EVENTS ###


__PACKAGE__->meta->make_immutable;
no Moose; 1;
