package Bot::Cobalt::Plugin::Extras::Dict;
our $VERSION = 1;

use 5.10.1;
use strictures 1;

use Bot::Cobalt;
use Bot::Cobalt::Common;

use POE qw/Component::Client::TCP/;

sub new { bless {}, shift }

sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;

  register( $self, 'SERVER',
    'public_cmd_dict',
    'public_cmd_define',
  );
    
  logger->info("Dictionary client loaded.");
  
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = splice @_, 0, 2;
  
  logger->info("Bye!");
  
  return PLUGIN_EAT_NONE
}

sub Bot_public_cmd_define { Bot_public_cmd_dict(@_) }
sub Bot_public_cmd_dict {
  my ($self, $core) = splice @_, 0, 2;
  my $msg = ${ $_[0] };

  my $server  = plugin_cfg($self)->{PluginOpts}->{Server}  || 'dict.org';
  my $port    = plugin_cfg($self)->{PluginOpts}->{Port}    || 2628;
  my $timeout = plugin_cfg($self)->{PluginOpts}->{Timeout} || 60;

  ## FIXME grab BindAddress ?

  my $hintshash = {
    Context => $msg->context,
    Channel => $msg->channel,
    Nick    => $msg->src_nick,
    Word    => $msg->message_array->[0],
  };
  
  POE::Component::Client::TCP->new(
    RemoteAddress => $server,
    RemotePort    => $port,
    
    SessionParams => [
      heap => {
        Hints => $hintshash,
      },
    ],
        
    Connected    => \&dict_connected,
    ConnectError => \&dict_connect_err,
    ServerInput  => \&dict_serv_input,
  );

  return PLUGIN_EAT_NONE
}

sub dict_connected {
  my ($socket, $addr, $port) = @_[ARG0 .. ARG2];
  ## mm... should get a welcome banner when we connect.
  ## can send query there ... just log to debug here.
  logger->debug("established dict server connection");
};

sub dict_connect_err {
  my ($op, $errnum, $errstr) = @_[ARG0 .. ARG2];
  my $hints = $_[HEAP]->{Hints};
  ## connection failed. clean up, report back.

  logger->warn("Connection to server failed: $op ($errnum) $errstr");
  
  broadcast( 'message',
    $hints->{Context}, $hints->{Channel},
    "Connection to dictionary server failed ($op - $errstr)"
  );
  
  $_[KERNEL]->yield("shutdown");
}

sub dict_serv_input {
  my $input = $_[ARG0];

  my $hints = $_[HEAP]->{Hints};

  ## 'server' is the ::Wheel set up by the component.
  my $wheel = $_[HEAP]->{server};
  
  my $status;
  unless ( ($status) = $input =~ /^([0-9]{3})\s/) {
    ## FIXME unknown input, clean up
  }

  INPUT: {

   if ($status == 552) {
      ## FIXME
      ## No match
    
      last INPUT
    }
    
    ## FIXME match status handler here-ish

    if ( $status == 220
         && $input =~ /^220\s\S*\s(<.*?>)?\s+(<.+?>)\s*$/) {
      ## Welcome banner.
      my ($capabstr, $id) = ($1,$2);
      $_[HEAP]->{MsgID}  = $id;
      $_[HEAP]->{Capabs} = [ split /\./, $capabstr ] if $capabstr;
      
      ## FIXME send 'define' ?
      
      last INPUT
    }

    if ($status == 530 || $status == 531 || $status == 532) {
      ## FIXME
      ## Access denied
    
      last INPUT
    }
        
    if ($status == 420 || $status == 421) {
      ## FIXME
      ## temporary outage
      
      last INPUT
    }
    
    if (   $status == 500 || $status == 501
        || $status == 502 || $status == 503
    ) {
    
      ## FIXME
      ## bad cmd / syntax
      
      last INPUT
    }

    if ($status == 554 || $status == 555) {
      ## FIXME
      ## No DBs / no strategies
      
      last INPUT
    }

    ## FIXME fell thru

  }
}

1;
