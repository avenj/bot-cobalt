package Cobalt::Plugin::Extras::Shorten;
our $VERSION = '0.01';

use LWP::Simple qw/$ua get/;
use URI::Escape qw/uri_escape/;

sub new { bless {}, shift }

sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;
  $self->{core} = $core;
  $ua->agent("cobalt2 shorten plugin");
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
  my $channel = $msg->{channel};
  my @message = @{ $msg->{message_array} };
  my $url = shift @message if @message;
  my $short = $self->_shorturl($url) if $url;
  $core->send_event('send_message', $context, $channel,
    "- short url: $url") if $short;
  return PLUGIN_EAT_NONE
}

sub Cobalt_public_cmd_shorten {
 Cobalt_public_cmd_short(@_);
}

sub Cobalt_public_cmd_long {
  my ($self, $core) = splice @_, 0, 2;
  my ($context, $msg) = (${$_[0]}, ${$_[1]});
  my $channel = $msg->{channel};
  my @message = @{ $msg->{message_array} };
  my $url = shift @message if @message;
  my $long = $self->_longurl($url) if $url;
  $core->send_event('send_message', $context, $channel,
    "- long url: $url") if $long;
  return PLUGIN_EAT_NONE
}

sub Cobalt_public_cmd_lengthen {
  Cobalt_public_cmd_long(@_);
}


sub _shorturl {
  my ($self, $url) = @_;
  $url = uri_escape($url);
  my $short = $ua->post("http://metamark.net/api/rest/simple",
    { long_url => $url })->content;
  return $short
}

sub _longurl {
  my ($self, $url) = @_;
  my $long = get("http://metamark.net/api/rest/simple?short_url=$url"), "\n";
  return $long
}

1;
