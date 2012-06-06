package Bot::Cobalt::Plugin::Version;
our $VERSION = '0.007';
## Always declare a package name as the first line.
## For example, if your module lives in:
##   lib/Cobalt/Plugin/User/MyPlugin.pm
## Your package would be:
##   Bot::Cobalt::Plugin::User::MyPlugin

## This is a very simple bot info plugin.
## Excessively commented for educational purposes.
## Commands:
##  'info'
##  'version'
##  'os'

## Specifying a recent Perl is usually a good idea.
## You get handy new features like given/when case statements,
## better Unicode semantics, etc.
## You need at least 5.10.1 to run cobalt2 anyway:
use 5.10.1;

## Always, always use strict & warnings:
use strict;
use warnings;

## You can get functional-style Core sugar from Bot::Cobalt
## (register, unregister, broadcast, core ...)
use Bot::Cobalt;

## You should always import the PLUGIN_ constants.
## Event handlers should return one of:
##  - PLUGIN_EAT_NONE
##    (Continue to pass the event through the pipeline)
##  - PLUGIN_EAT_ALL
##    (Do not push event to plugins farther down the pipeline)
use Object::Pluggable::Constants qw/ :ALL /;

## Bot::Cobalt::Utils provides a handful of functional utils.
## We need secs_to_str to compose uptime strings
## (and rplprintf to format langset replies)
## also see Bot::Cobalt::Utils POD
use Bot::Cobalt::Utils qw/ secs_to_str rplprintf /;

## Minimalist constructor example.
## This is all you need to create an object for this plugin:
sub new { bless {}, shift  }

## Called when the plugin is loaded:
sub Cobalt_register {
  ## We can grab $self (this plugin) and $core here:
  my ($self, $core) = splice @_, 0, 2;
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
  my ($self, $core) = splice @_, 0, 2;
  ## You could do some kind of clean-up here . . .
  $core->log->info("Unregistering core IRC plugin");
  return PLUGIN_EAT_NONE
}


## Bot_public_msg is broadcast on channel PRIVMSG events:
sub Bot_public_msg {
  my ($self, $core) = splice @_, 0, 2;

  ## Arguments are provided as references
  ## deref:
  my $msg     = ${$_[0]};      ## our msg object
  my $context = $msg->context; ## our server context

  ## return unless bot is addressed:
  return PLUGIN_EAT_NONE unless $msg->highlight;

  my $resp;

  ## $message_array->[1] is the first word aside from botnick.
  my $cmd = $msg->message_array->[1] || return PLUGIN_EAT_NONE;

  given ( lc($cmd) ) {

    when ("info") {
      my $startedts = $core->State->{StartedTS} // 0;
      my $delta = time() - $startedts;

      my $randstuffs = $core->Provided->{randstuff_items} // 0;
      my $infoglobs  = $core->Provided->{info_topics}    // 0;

      $resp = rplprintf( $core->lang->{RPL_INFO},
        {
          version => 'Bot::Cobalt '.$core->version,
          plugins => scalar keys %{ $core->plugin_list },
          uptime => secs_to_str($delta),
          sent   => $core->State->{Counters}->{Sent},
          topics     => $infoglobs,
          randstuffs => $randstuffs,
        }
      );
    }

    when ("version") {
      $resp = rplprintf( $core->lang->{RPL_VERSION},
        {
          version => 'Bot::Cobalt '.$core->version,
          perl_v  => sprintf("%vd", $^V),
          poe_v   => $POE::VERSION,
          pocoirc_v => $POE::Component::IRC::VERSION,
        }
      );
    }

    when ("os") {
      $resp = rplprintf( $core->lang->{RPL_OS}, { os => $^O } );
    }

  }

  if ($resp) {
    ## We have a response . . .
    ## Send it back to the relevant location.
    my $target = $msg->channel;
    broadcast( 'message', $context, $target, $resp );
  }

  ## Always return an Object::Pluggable::Constants value
  ## (otherwise you might interrupt the plugin pipeline)
  return PLUGIN_EAT_NONE
}

1;
__END__

=pod

=head1 NAME

Bot::Cobalt::Plugin::Version - Retrieve bot version and info

=head1 SYNOPSIS

  ## Get uptime and other info:
  <JoeUser> botnick: info
  
  ## Get version information:
  <JoeUser> botnick: version
  
  ## Find out what OS we're using:
  <JoeUser> botnick: os

=head1 DESCRIPTION

Retrieves information about the running Cobalt instance.

If L<Bot::Cobalt::Plugin::Info3> is available, the number of Info3 topics 
is included.

If L<Bot::Cobalt::Plugin::RDB> is available, the number of items in the 'main' 
RDB will be reported.

The source code for this plugin is overly-commented for the sake of 
new plugin authors looking for a working example plugin. Try:

  perldoc -m Bot::Cobalt::Plugin::Version

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
