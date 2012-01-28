package Cobalt::Plugin::Extras::Morse;
our $VERSION = '0.01';

## should be rolled into a generic 'encode' plugin
## (maybe under games?)
## should be moved out into an extras dist

use 5.12.1;
use strict;
use warnings;


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
  return PLUGIN_EAT_ALL unless $txt;

  ## FIXME walk text, discard unknown chars, convert known via MORSE hash

  my $morse;
  
  for my $word (@{ $msg->{message_array} ) {
    for my $char (split '', $word) {
      if (defined MORSE->{$char}) {
        $morse .= MORSE->{$char};
      }
    }
    $morse .= ' ';
  }

  my $channel = $msg->{channel};
  $core->send_event( 'send_message', $context, $channel, $resp );
  return PLUGIN_EAT_ALL
}

sub Bot_public_cmd_morsedec {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${ $_[0] };
  my $msg     = ${ $_[1] };
  my $morse_in = $msg->{txt};

  ## FIXME reverse MORSE hash and convert
  my $channel = $msg->{channel};
  $core->send_event( 'send_message', $context, $channel, $resp );
  return PLUGIN_EAT_ALL
}

sub Bot_public_cmd_morsedecode {
  Bot_public_cmd_morsedec(@_);
}

use constant MORSE => {
  qw/
      A .-
      B -...
      C -.-.
      D -..
      E .
      F ..-.
      G --.
      H ....
      I ..
      J .---
      K -.-
      L .-..
      M --
      N -.
      O ---
      P .--.
      Q --.-
      R .-.
      S ...
      T -
      U ..-
      V ...-
      W .--
      X -..-
      Y -.--
      Z --..
      . .-.-.-
      , --..--
      / -...-
      : ---...
      ' .----.
      - -....-
      ? ..--..
      ! ..--.
      @ ...-.-
      + .-.-.
      0 -----
      1 .----
      2 ..---
      3 ...--
      4 ....-
      5 .....
      6 -....
      7 --...
      8 ---..
      9 ----.
  /;
};

1;
