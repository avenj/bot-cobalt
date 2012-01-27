package Cobalt::Plugin::Extras::Shorten;
our $VERSION = '0.02';

use 5.12.1;
use strict;
use warnings;

use Object::Pluggable::Constants qw/ :ALL /;

use HTTP::Request;
use URI::Escape;

sub new { bless {}, shift }

sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;
  $self->{core} = $core;
  $core->log->info("Loaded, cmds: !short / !long <url>");
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = splice @_, 0, 2;
  $core->log->info("Unregistered");
  return PLUGIN_EAT_NONE
}

sub Cobalt_public_cmd_short {
  my ($self, $core) = splice @_, 0, 2;
  my ($context, $msg) = (${$_[0]}, ${$_[1]});
  my $nick    = $msg->{src_nick};
  my $channel = $msg->{channel};
  my @message = @{ $msg->{message_array} };
  my $url = shift @message if @message;
  $url = uri_escape($url); ## FIXME utf8 escapes ?
  $self->_request_shorturl($url, $context, $channel, $nick);
  return PLUGIN_EAT_NONE
}

sub Cobalt_public_cmd_shorten {
 Cobalt_public_cmd_short(@_);
}

sub Cobalt_public_cmd_long {
  my ($self, $core) = splice @_, 0, 2;
  ## FIXME
  return PLUGIN_EAT_NONE
}

sub Cobalt_public_cmd_lengthen {
  Cobalt_public_cmd_long(@_);
}


sub Bot_shorten_response_recv {
  my ($self, $core) = splice @_, 0, 2;
  ## handler for received shorturls
  my $shorturl = ${ $_[0] }; 
  my $args = ${ $_[2] };
  my ($context, $channel, $nick) = @$args;

  $core->send_event( 'send_message', $context, $channel,
    "shorturl for ${nick}: ${shorturl}",
  );
  
  return PLUGIN_EAT_ALL
}


sub _request_shorturl {
  my ($self, $url, $context, $channel, $nick) = @_;
  my $core = $self->{core};
  my $request = HTTP::Request->new(
  'POST', "http://metamark.net/api/rest/simple",
    [ 'long_url' => $url ]
  );
  $core->send_event( 'www_request',
    $request,
    'shorten_response_recv',
    [ $context, $channel, $nick ],
  );
}

1;
