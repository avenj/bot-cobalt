package Cobalt::Plugin::Extras::Money;
our $VERSION = '0.04';

use Cobalt::Common;

use URI::Escape;
use HTTP::Request;

sub new { bless {}, shift }

sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;
  $self->{core} = $core;
  $core->plugin_register( $self, 'SERVER',
    [
      'public_cmd_currency',
      'public_cmd_cc',
      'public_cmd_money',
      
      'currencyconv_rate_recv',
    ],
  );
  $core->log->info("$VERSION loaded");
  return PLUGIN_EAT_NONE 
}

sub Cobalt_unregister {
  my ($self, $core) = splice @_, 0, 2;
  $core->log->info("Unloaded");
  return PLUGIN_EAT_NONE
}

sub Bot_public_cmd_currency {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${ $_[0] };
  my $msg     = ${ $_[1] };
  
  my $channel = $msg->{channel};

  my @message = @{ $msg->{message_array} };
  my ($value, $from, undef, $to) = @message;
  
  unless ($value && $from && $to) {
    $core->send_event( 'send_message', $context, $channel,
      "Syntax: !cc <value> <abbrev> TO <abbrev>"
    );
    return PLUGIN_EAT_ALL
  }
  
  my $valid_val    = qr/^(\d+)?\.?(\d+)?$/;
  my $valid_abbrev = qr/^[A-Z]{3}$/;

  unless ($value =~ $valid_val) {
    $core->send_event( 'send_message', $context, $channel,
      "$value is not a valid quantity."
    );  
    return PLUGIN_EAT_ALL
  }
  
  unless ($from =~ $valid_abbrev && $to =~ $valid_abbrev) {
    $core->send_event( 'send_message', $context, $channel,
      "Currency codes must be three-letter abbreviations."
    );
    return PLUGIN_EAT_ALL
  }

  $self->_request_conversion_rate(
    $from, $to, $value, $context, $channel
  );
  
  return PLUGIN_EAT_ALL
}

sub Bot_public_cmd_cc    { Bot_public_cmd_currency(@_) }
sub Bot_public_cmd_money { Bot_public_cmd_currency(@_) }

sub Bot_currencyconv_rate_recv {
  my ($self, $core) = splice @_, 0, 2;
  my $response = ${ $_[1] };
  my $args     = ${ $_[2] };
  my ($value, $context, $channel, $from, $to) = @$args;
  
  unless ($response->is_success) {
    $core->send_event( 'send_message', $context, $channel,
      "HTTP response failed: ".$response->code
    );
    return PLUGIN_EAT_ALL
  }

  my $content = $response->content;
  
  my($rate,$converted);
  if ( $content =~ /<double.*>(.*)<\/double>/i ) {
    $rate = $1||1;
    $converted = $value * $rate ;
  } else {
    $core->send_event( 'send_message', $context, $channel,
      "Failed to retrieve currency conversion ($from -> $to)"
    );
    return PLUGIN_EAT_ALL
  }
  
  $core->send_event( 'send_message', $context, $channel,
    "$value $from == $converted $to"
  );
  
  return PLUGIN_EAT_ALL
}

sub _request_conversion_rate {
  my ($self, $from, $to, $value, $context, $channel) = @_;
  return unless $from and $to;

  my $core = $self->{core};

  my $uri = 
     "http://www.webservicex.net/CurrencyConvertor.asmx"
    ."/ConversionRate?FromCurrency=${from}&ToCurrency=${to}";
  
  if ($core->Provided->{www_request}) {
    my $req = HTTP::Request->new( 'GET', $uri ) || return undef;
    $core->send_event( 'www_request',
      $req,
      'currencyconv_rate_recv',
      [ $value, $context, $channel, $from, $to ],
    );
  } else {
    require LWP::UserAgent;
    my $ua = LWP::UserAgent->new(
      timeout => 3,
      max_redirect => 0,
      agent => 'cobalt2',
    );
    my $resp = $ua->get($uri);
    $core->send_event( 'currencyconv_rate_recv', 
      $resp->decoded_content || undef,
      $resp, 
      [ $value, $context, $channel, $from, $to ] 
    );
  }
}

1;
__END__
