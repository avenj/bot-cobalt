package Cobalt::Plugin::Extras::Shorten;
our $VERSION = '0.07';

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
      'public_cmd_shorturl',
      'public_cmd_shorten',
      'public_cmd_longurl',
      'public_cmd_lengthen',
      'shorten_response_recv',
    ],
  );
  $core->log->info("Loaded, cmds: !shorten / !lengthen <url>");
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = splice @_, 0, 2;
  $core->log->info("Unregistered");
  return PLUGIN_EAT_NONE
}

sub Bot_public_cmd_shorturl {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${ $_[0] };
  my $msg = ${ $_[1] };
  my $nick    = $msg->{src_nick};
  my $channel = $msg->{channel};
  my @message = @{ $msg->{message_array} };
  my $url = shift @message if @message;
  $url = uri_escape($url);

  $self->_request_shorturl($url, $context, $channel, $nick);

  return PLUGIN_EAT_NONE
}

sub Bot_public_cmd_shorten {
 Bot_public_cmd_shorturl(@_);
}

sub Bot_public_cmd_longurl {
  my ($self, $core) = splice @_, 0, 2;

  my $context = ${ $_[0] };
  my $msg = ${ $_[1] };
  my $nick    = $msg->{src_nick};
  my $channel = $msg->{channel};
  my @message = @{ $msg->{message_array} };
  my $url = shift @message if @message;
  $url = uri_escape($url);

  $self->_request_longurl($url, $context, $channel, $nick);

  return PLUGIN_EAT_NONE
}

sub Bot_public_cmd_lengthen {
  Bot_public_cmd_longurl(@_);
}


sub Bot_shorten_response_recv {
  my ($self, $core) = splice @_, 0, 2;
  ## handler for received shorturls
  my $url = ${ $_[0] }; 
  my $args = ${ $_[2] };
  my ($context, $channel, $nick) = @$args;

  $core->log->debug("url; $url");

  $core->send_event( 'send_message', $context, $channel,
    "url for ${nick}: $url",
  );
  
  return PLUGIN_EAT_ALL
}

sub _request_shorturl {
  my ($self, $url, $context, $channel, $nick) = @_;
  my $core = $self->{core};
  
  if ($core->Provided->{www_request}) {
    my $request = HTTP::Request->new(
      'GET',
      "http://metamark.net/api/rest/simple?long_url=".$url,
    );

    $core->send_event( 'www_request',
      $request,
      'shorten_response_recv',
      [ $context, $channel, $nick ],
    );

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
}

sub _request_longurl {
  my ($self, $url, $context, $channel, $nick) = @_;
  my $core = $self->{core};
  
  if ($core->Provided->{www_request}) {
    my $request = HTTP::Request->new(
      'GET',
      "http://metamark.net/api/rest/simple?short_url=".$url,
    );

    $core->send_event( 'www_request',
      $request,
      'shorten_response_recv',
      [ $context, $channel, $nick ],
    );

  } else {
    ## no async http, use LWP
    my $ua = LWP::UserAgent->new(
      timeout      => 5,
      max_redirect => 0,
      agent => 'cobalt2',
    );
    my $longurl = $ua->post('http://metamark.net/api/rest/simple',
      [ short_url => $url ] )->content;
    if ($longurl) {
      $longurl = "longurl for ${nick}: $longurl";
    } else {
      $longurl = "${nick}: shortener timed out";
    }
    $core->send_event( 'send_message', $context, $channel, $longurl );
  }
}

1;
