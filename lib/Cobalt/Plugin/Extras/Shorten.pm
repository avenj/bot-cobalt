package Cobalt::Plugin::Extras::Shorten;
our $VERSION = '0.05';

use 5.12.1;
use strict;
use warnings;

use Object::Pluggable::Constants qw/ :ALL /;

use HTTP::Request;
use URI::Escape;

use LWP::UserAgent;

sub new { bless {}, shift }

sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;
  $self->{core} = $core;
  $core->plugin_register( $self, 'SERVER',
    [
      'public_cmd_short',
      'public_cmd_shorten',
      'public_cmd_long',
      'public_cmd_lengthen',
      'shorten_response_recv',
    ],
  );
  $core->log->info("Loaded, cmds: !short / !long <url>");
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = splice @_, 0, 2;
  $core->log->info("Unregistered");
  return PLUGIN_EAT_NONE
}

sub Bot_public_cmd_short {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${ $_[0] };
  my $msg = ${ $_[1] };
  my $nick    = $msg->{src_nick};
  my $channel = $msg->{channel};
  my @message = @{ $msg->{message_array} };
  my $url = shift @message if @message;
  $url = uri_escape($url); ## FIXME utf8 escapes ?

  my $shorturl;

  if ($core->Provided->{www_request}) {
    $self->_request_shorturl($url, $context, $channel, $nick);
  } else {
    ## no async http, use LWP
    my $ua = LWP::UserAgent->new(
      timeout      => 5,
      max_redirect => 0,
      agent => 'cobalt2',
    );
    my $shorturl = $ua->post('http://metamark.net/api/rest/simple',
      [ long_url => $url ] )->content;
    if ($shorturl) {
      $shorturl = "shorturl for ${nick}: $shorturl";
    } else {
      $shorturl = "${nick}: shortener timed out";
    }
    $core->send_event( 'send_message', $context, $channel, $shorturl );
  }
    
  return PLUGIN_EAT_NONE
}

sub Bot_public_cmd_shorten {
 Bot_public_cmd_short(@_);
}

sub Bot_public_cmd_long {
  my ($self, $core) = splice @_, 0, 2;
  ## FIXME
  return PLUGIN_EAT_NONE
}

sub Bot_public_cmd_lengthen {
  Bot_public_cmd_long(@_);
}


sub Bot_shorten_response_recv {
  my ($self, $core) = splice @_, 0, 2;
  ## handler for received shorturls
  my $shorturl = ${ $_[0] }; 
  my $args = ${ $_[2] };
  my ($context, $channel, $nick) = @$args;

  $core->log->debug("shorturl; $shorturl");

  $core->send_event( 'send_message', $context, $channel,
    "shorturl for ${nick}: ${shorturl}",
  );
  
  return PLUGIN_EAT_ALL
}

sub _request_shorturl {
  my ($self, $url, $context, $channel, $nick) = @_;
  my $core = $self->{core};

  my $request = HTTP::Request->new(
    'GET',
    "http://metamark.net/api/rest/simple?long_url=".$url,
  );

  $core->send_event( 'www_request',
    $request,
    'shorten_response_recv',
    [ $context, $channel, $nick ],
  );
}

1;
