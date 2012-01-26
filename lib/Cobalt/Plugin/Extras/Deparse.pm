package Cobalt::Plugin::Extras::Deparse;
our $VERSION = '1.0';

## silly plugin to feed perl code to B::Deparse
## handles: !deparse

use 5.12.1;
use strict;
use warnings;
use Object::Pluggable::Constants qw/ :ALL /;

use B::Deparse;

sub new { bless {}, shift }

sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;
  $core->plugin_register( $self, 'SERVER',
    [ 'public_cmd_deparse' ]
  );
  $core->log->info("Registered");
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = splice @_, 0, 2;
  $core->log->info("Unregistering");
  return PLUGIN_EAT_NONE
}

sub Bot_public_cmd_deparse {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${$_[0]};
  my $msg = ${$_[1]};
  my $channel = $msg->{channel};
  my $code = join ' ', @{ $msg->{message_array} };
  my $resp = _deparse($code);
  $core->send_event( 'send_message', $context, $channel, $resp );
  return PLUGIN_EAT_ALL
}

sub _deparse
{
  my ( $code ) = @_;
  $code =~ s/\s*$//;
  my $sub = eval "no strict; no warnings; no charnames; sub{ $code\n }";
  if( $@ ) { return("error: $@"); }

  my $dp = B::Deparse->new("-p", "-q", "-x7");
  my $ret = $dp->coderef2text($sub);

  $ret =~ s/\{//;
  $ret =~ s/package (?:\w+(?:::)?)+;//;
  $ret =~ s/ no warnings;//;
  $ret =~ s/\s+/ /g;
  $ret =~ s/\s*\}\s*$//;
  return $ret
}

