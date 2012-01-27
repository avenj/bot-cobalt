package Cobalt::Plugin::Extras::Morse;
our $VERSION = '0.01';

## should be rolled into a generic 'encode' plugin
## (maybe under games?)
## should be moved out into an extras dist

use 5.12.1;
use strict;
use warnings;

use Text::Morse;

use Object::Pluggable::Constants qw/:ALL/;

sub new { bless {}, shift }

sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;
  
  $self->{morse} = Text::Morse->new;
  
  $core->plugin_register($self, 'SERVER',
    [ 
      'Bot_public_cmd_morse',
      'Bot_public_cmd_morsedecode',
      'Bot_public_cmd_morsedec',
    ],
  );
  $core->log->info("Registered");
      
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = splice @_, 0, 2;
  $core->log->info("Unregistered");
  return PLUGIN_EAT_NONE
}

sub Bot_public_cmd_morse {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${ $_[0] };
  my $msg     = ${ $_[1] };
  my $txt = $msg->{txt};
  return PLUGIN_EAT_ALL unless $txt;
  my $resp = $self->{morse}->Encode($txt);
  my $channel = $msg->{channel};
  $core->send_event( 'send_message', $context, $channel, $resp );
  return PLUGIN_EAT_ALL
}

sub Bot_public_cmd_morsedec {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${ $_[0] };
  my $msg     = ${ $_[1] };
  my $morse_in = $msg->{txt};
  my $resp = $self->{morse}->Decode($morse_in);
  my $channel = $msg->{channel};
  $core->send_event( 'send_message', $context, $channel, $resp );
  return PLUGIN_EAT_ALL
}

sub Bot_public_cmd_morsedecode {
  Bot_public_cmd_morsedec(@_);
}

1;
