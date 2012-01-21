package Cobalt::Plugin::OutputFilters::StripFormat;
our $VERSION = '0.10';

use 5.12.1;
use strict;
use warnings;

use Object::Pluggable::Constants qw/ :ALL /;

use IRC::Utils qw/ strip_formatting /;

sub new { bless {}, shift }

sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;

  $core->plugin_register( $self, 'USER',
    [ 'message', 'notice' ],
  );

  $core->log->info("Registered, filtering FORMATTING");

  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = splice @_, 0, 2;
  $core->log->info("Unregistered");
  return PLUGIN_EAT_NONE
}

sub Outgoing_message {
  my ($self, $core) = splice @_, 0, 2;
  ${$_[2]} = strip_formatting(${$_[2]});
  return PLUGIN_EAT_NONE
}

sub Outgoing_notice {
  my ($self, $core) = splice @_, 0, 2;
  ${$_[2]} = strip_formatting(${$_[2]});
  return PLUGIN_EAT_NONE
}

1;
