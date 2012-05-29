package Bot::Cobalt::Plugin::Extras::Shorten;
our $VERSION = '0.005';

use 5.10.1;
use strict;
use warnings;

use Bot::Cobalt;
use Object::Pluggable::Constants qw/ :ALL /;

use HTTP::Request;
use URI::Escape;

sub new { bless {}, shift }

sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;

  register( $self, 'SERVER',
    [
      'public_cmd_shorturl',
      'public_cmd_shorten',
      'public_cmd_longurl',
      'public_cmd_lengthen',
      'shorten_response_recv',
    ],
  );

  logger->info("Loaded, cmds: !shorten / !lengthen <url>");

  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = splice @_, 0, 2;
  logger->info("Unregistered");
  return PLUGIN_EAT_NONE
}

sub Bot_public_cmd_shorturl {
  my ($self, $core) = splice @_, 0, 2;
  my $msg = ${ $_[0] };

  my $context = $msg->context;
  my $nick    = $msg->src_nick;
  my $channel = $msg->channel;
  my $url = $msg->message_array->[0] || return PLUGIN_EAT_ALL;
  $url = uri_escape($url);

  $self->_request_shorturl($url, $context, $channel, $nick);

  return PLUGIN_EAT_ALL
}

sub Bot_public_cmd_shorten {
 Bot_public_cmd_shorturl(@_);
}

sub Bot_public_cmd_longurl {
  my ($self, $core) = splice @_, 0, 2;
  my $msg = ${ $_[0] };
  
  my $context = $msg->context;
  my $nick    = $msg->src_nick;
  my $channel = $msg->channel;
  my $url = $msg->message_array->[0] || return PLUGIN_EAT_ALL;
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
  my $url  = ${ $_[0] }; 
  my $args = ${ $_[2] };
  my ($context, $channel, $nick) = @$args;

  logger->debug("url; $url");

  broadcast( 'message', $context, $channel,
    "url for ${nick}: $url",
  );
  
  return PLUGIN_EAT_ALL
}

sub _request_shorturl {
  my ($self, $url, $context, $channel, $nick) = @_;
  
  if ( core()->Provided->{www_request} ) {
    my $request = HTTP::Request->new(
      'GET',
      "http://metamark.net/api/rest/simple?long_url=".$url,
    );

    broadcast( 'www_request',
      $request,
      'shorten_response_recv',
      [ $context, $channel, $nick ],
    );

  } else {
    broadcast( 'message', $context, $channel,
      "No async HTTP available, try loading Bot::Cobalt::Plugin::WWW"
    );
  }
}

sub _request_longurl {
  my ($self, $url, $context, $channel, $nick) = @_;
  
  if ( core()->Provided->{www_request} ) {
    my $request = HTTP::Request->new(
      'GET',
      "http://metamark.net/api/rest/simple?short_url=".$url,
    );

    broadcast( 'www_request',
      $request,
      'shorten_response_recv',
      [ $context, $channel, $nick ],
    );

  } else {
    broadcast( 'message', $context, $channel,
      "No async HTTP available, try loading Bot::Cobalt::Plugin::WWW"
    );
  }
}

1;
__END__

=pod

=head1 NAME

Bot::Cobalt::Plugin::Extras::Shorten - Shorten URLs via Metamark

=head1 SYNOPSIS

  !shorten http://some/long/url
    
  !lengthen http://xrl.us/<id>

=head1 DESCRIPTION

Provides a simple IRC interface to the http://xrl.us URL shortener.

Requires L<Bot::Cobalt::Plugin::WWW>

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

L<http://www.cobaltirc.org>

=cut
