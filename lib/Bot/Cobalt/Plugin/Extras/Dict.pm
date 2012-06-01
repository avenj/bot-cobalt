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

  my $server  = plugin_cfg($self)->{PluginOpts}->{Server}  || 'dict.org';
  my $port    = plugin_cfg($self)->{PluginOpts}->{Port}    || 2628;
  my $timeout = plugin_cfg($self)->{PluginOpts}->{Timeout} || 60;

  ## FIXME grab BindAddress ?
  
  my $sessid = POE::Component::Client::TCP->new(
    RemoteAddress => $server,
    RemotePort    => $port,
    
    SessionParams => [
      heap => {
        Hints => $hintshash, ## FIXME
      },
    ],
        
    Connected => sub {
      my $input = $_[ARG0];
    },
    
    ConnectError => sub {
      ## FIXME
    },
    
    ServerInput => sub {
      ## FIXME
      my $input = $_[ARG0];
      my $hints = $_[HEAP]->{Hints};
      
      
    },
  );

  return PLUGIN_EAT_NONE
}


1;
