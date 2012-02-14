package Cobalt::Plugin::FloodProtect;
our $VERSION = '0.10';

## store ignorelist in ->State
## IRC.pm/MultiServer.pm should check ignorelist before dispatch
## manage temp ignores

## FIXME

use 5.12.1;
use strict;
use warnings;

use Cobalt::Utils qw/ timestr_to_secs /;

use Object::Pluggable::Constants qw/ :ALL /;

sub new {
  my $self = {};
  my $class = shift;
  bless $self, $class;
  return $self
}


sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;

  ## FIXME push myself towards the top of the pipeline
  

  $self->{core} = $core;

  ## FIXME grab a cfg file to determine flood rates and ignore expiries
  ## per-channel and per-privmsg should include ctcp actions
  ## per-ctcp should exclude actions

  $core->plugin_register($self, 'SERVER',
    [
      'public_msg',
      'private_msg',
      'notice',
      'ctcp_action',

# FIXME catch Outgoing_*
# if we've sent the same string too many times sequentially in a short span
#  then eat it

    ],

  );

  $core->log->info("$VERSION loaded");

  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = splice @_, 0, 2;
  ## FIXME cleanup our ignorelist entries
  $core->log->info("Unregistered");
  return PLUGIN_EAT_NONE
}

sub Bot_public_msg {
  ## start a context->chan->user counter when a user speaks
}

sub Bot_private_msg {
}

sub Bot_notice {
  ## fold in with pubmsg/privmsg trackers
}

sub Bot_ctcp_action {
  ## fold in with pubmsg/privmsg trackers as appropriate
}

sub Bot_floodprot_ignore_expire {
  ## FIXME event called by timer to clear a floodprot ignore
}

sub Bot_floodprot_counters_expire {
  ## check TS delta since last message seen, clear if needed

}

sub _clear_all_ignores {
  ## clear all temp ignores belonging to our alias
}

## FIXME CTCP

1;
__END__
