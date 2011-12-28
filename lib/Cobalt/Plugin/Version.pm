package Cobalt::Plugin::Version;

use 5.12.1;
use strict;
use warnings;

use Object::Pluggable::Constants qw/ :ALL /;

## Commands:
##  'info'
##  'version'
##  'os'
##  'uptime'

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

  $core->log->info("Registered");
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

  ## return unless bot is addressed
  return PLUGIN_EAT_NONE unless $msg->{highlight};

  my $version = $core->version;
  my $me = $msg->{myself};
  my $txt = $msg->{message};
  $txt =~ s/^${me}.?\s+//i;  ## strip bot's nick off string
  $txt =~ s/\s+$//;          ## strip trailing white space

  my $resp;

  given ($txt) {

    when (/^info$/i) {
      $resp = sprintf( $core->lang->{RPL_INFO},
        'cobalt '.$core->version,
        0, ## FIXME uptime
        0, ## FIXME questions answered state
        0, ## FIXME
        0, ## FIXME
        0, ## FIXME
      );
    }

    when (/^version$/i) {
      $resp = sprintf( $core->lang->{RPL_VERSION},
        $core->version,
        $^V,
        $POE::VERSION,
        $POE::Component::IRC::VERSION,
      );
    }

    when (/^os$/i) {
      $resp = sprintf( $core->lang->{RPL_OS}, $^O );        
    }

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
