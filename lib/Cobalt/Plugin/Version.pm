package Cobalt::Plugin::Version;
## Always declare a package name as the first line.
## For example, if your module lives in:
##   lib/Cobalt/Plugin/User/MyPlugin.pm
## Your package would be:
##   Cobalt::Plugin::User::MyPlugin

## This is a very simple bot info plugin.
## Excessively commented for educational purposes.
## Commands:
##  'info'
##  'version'
##  'os'

## Specifying a recent Perl is usually a good idea.
## You get handy new features like given/when case statements,
## better Unicode semantics, etc.
## You need at least 5.12.1 to run cobalt2 anyway:
use 5.12.1;

## Always, always use strict & warnings:
use strict;
use warnings;

## You should always import the PLUGIN_ constants.
## Event handlers should return one of:
##  - PLUGIN_EAT_NONE
##    (Continue to pass the event through the pipeline)
##  - PLUGIN_EAT_ALL
##    (Do not push event to plugins farther down the pipeline)
use Object::Pluggable::Constants qw/ :ALL /;

## Cobalt::Utils provides a handful of functional utils.
## We just need secs_to_timestr to compose uptime strings:
use Cobalt::Utils qw/ secs_to_timestr /;

## Minimalist constructor example.
## This is all you need to create an object for this plugin:
sub new { bless( {}, shift ) }

## Called when the plugin is loaded:
sub Cobalt_register {
  ## We can grab $self (this plugin) and $core here:
  my ($self, $core) = @_;
  ## $core gives us access to the core Cobalt instance
  ## $self can be used like you would in any other Perl module, clearly

  ## Register to receive public messages from the event syndicator:
  $core->plugin_register($self, 'SERVER',
    [ 'public_msg' ],
  );

  ## report that we're here now:
  $core->log->info("Registered");

  ## ALWAYS explicitly return an appropriate PLUGIN_EAT_*
  ## Usually this will be PLUGIN_EAT_NONE:
  return PLUGIN_EAT_NONE
}

## Called when the plugin is unloaded:
sub Cobalt_unregister {
  my ($self, $core) = @_;
  ## You could do some kind of clean-up here . . .
  $core->log->info("Unregistering core IRC plugin");
  return PLUGIN_EAT_NONE
}


## Bot_public_msg is broadcast on channel PRIVMSG events:
sub Bot_public_msg {
  my ($self, $core) = splice @_, 0, 2;

  ## Arguments are provided as a reference.
  ## deref:
  my $context = $$_[0];  ## our server context
  my $msg = $$_[1];      ## our msg hash

  ## return unless bot is addressed:
  return PLUGIN_EAT_NONE unless $msg->{highlight};

  my $resp;

  ## $message_array->[1] is the first word aside from botnick.
  ## FIXME: moar complete documentation on $msg
  given ($msg->{message_array}->[1]) {

    when (/^info$/i) {
      my $startedts = $core->State->{StartedTS} // 0;
      my $delta = time() - $startedts;

      $resp = sprintf( $core->lang->{RPL_INFO},
        'cobalt '.$core->version,       ## version str
        scalar keys $core->plugin_list, ## plugin count
        secs_to_timestr($delta),        ## uptime str
        $core->State->{Counters}->{Sent}, ## sent msg events
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
    ## We have a response . . .
    ## Send it back to the relevant location.
    my $target = $msg->{channel};
    $core->send_event( 'send_message', $context, $target, $resp );
  }

  ## Always return an Object::Pluggable::Constants value
  ## (otherwise you might interrupt the plugin pipeline)
  return PLUGIN_EAT_NONE
}

1;
