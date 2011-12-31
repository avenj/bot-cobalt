package Cobalt::Plugin::Version;

use 5.12.1;
use strict;
use warnings;

use Object::Pluggable::Constants qw/ :ALL /;

use Cobalt::Utils qw/ secs_to_timestr /;

## Commands:
##  'info'
##  'version'
##  'os'
##  'uptime'

sub new { bless( {}, shift ) }

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
  my $msg = ${ $_[0] };

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
      my $startedts = $core->State->{StartedTS} // 0;
      my $delta = time() - $startedts;
      $resp = sprintf( $core->lang->{RPL_INFO},
        'cobalt '.$core->version,
        scalar keys $core->plugin_list,
        secs_to_timestr($delta),
        $core->State->{Counters}->{Sent},
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
