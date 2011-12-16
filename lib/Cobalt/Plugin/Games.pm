package Cobalt::Plugin::Games;

use 5.12.1;
use strict;
use warnings;

use Object::Pluggable::Constants qw/ :ALL /;

## Commands:


sub new {
  my $class = shift;
  my $self = {};
  bless($self,$class);
  return $self
}

sub Cobalt_register {
  my ($self, $core) = @_;

  $core->plugin_register($self, 'SERVER',
    [ 'public_msg' ],
  );

  $core->log->info(__PACKAGE__." registered");
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = @_;
  $core->log->info("Unregistering core IRC plugin");
  return PLUGIN_EAT_NONE
}


sub Bot_public_msg {
  my ($self, $core) = splice @_, 0, 2;
  my $msg = ${ shift(@_) };

  my $me = $msg->{myself};
  my $txt = $msg->{message};
  $txt =~ s/^${me}.?\s+//i;  ## strip bot's nick off string
  $txt =~ s/\s+$//;          ## strip trailing white space

  my $resp;

  given ($txt) {

  }

  if ($resp) {
    $core->send_event( 'send_to_context',
      {
        context => $msg->{context},
        target => $msg->{channel},
        txt => $resp,
      }
    );    
  }

  return PLUGIN_EAT_NONE
}

1;
