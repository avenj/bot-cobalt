package Bot::Cobalt::Plugin::Extras::CPAN;
our $VERSION = 1;

use 5.10.1;
use strictures 1;

use Bot::Cobalt;
use Bot::Cobalt::Common;
use Bot::Cobalt::DB;
use Bot::Cobalt::Serializer;

use HTTP::Request;

sub new { bless {}, shift }

sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;
  
  register( $self, 'SERVER',
    'public_cmd_cpan',
  );
  
  ## FIXME set up cachedb
  
  logger->info("Loaded: !cpan");
  
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = splice @_, 0, 2;
  
  logger->info("Bye!");
  
  return PLUGIN_EAT_NONE
}

sub Bot_public_cmd_cpan {
  my ($self, $core) = splice @_, 0, 2;
  my $msg = ${ $_[0] };
  
  my $cmd  = $msg->message_array->[0];
  my $dist = $msg->message_array->[1];
  
  unless ($dist) {
    ## assume 'latest' if only one arg
    $dist = $cmd;
    $cmd  = 'latest';
  }
  
  $dist =~ s/::/-/g;
  
  my $url = "/release/$dist";

  my $hints = {
    Context => $msg->context,
    Channel => $msg->channel,
    Nick    => $msg->src_nick,
    Dist    => $dist,
  };
  
  given ( lc($cmd||'') ) {
  
    when ([qw/latest release/]) {
      ## Get latest vers / date and link
      $hints->{Type} = 'latest';
    }
    
    when ("dist") {
      ## Get download url      
      $hints->{Type} = 'dist';
    }
    
    when (/^tests?$/) {
      ## Get test reports
      $hints->{Type} = 'tests';
    }
    
    when ([qw/info abstract/]) {
      ## Get dist abstract
      $hints->{Type} = 'abstract';
    }
    
    when ("license") {
      ## Get license link
      $hints->{Type} = 'license';
    }
    
    default {
      ## FIXME bad syntax
    }
  
  }

  $self->_request($url, $hints)
    if defined $hints->{Type};
  
  return PLUGIN_EAT_ALL
}

sub _request {
  my ($self, $url, $hints) = @_;
  
  my $base_url = 'http://api.metacpan.org';
  my $this_url = $base_url . $url;
  
  logger->debug("metacpan request: $this_url");

  ## FIXME cachedb, check for recent cached result

  my $request = HTTP::Request->new(
    'GET', $this_url
  );
  
  broadcast( 'www_request',
    $request,
    'mcpan_plug_resp_recv',
    $hints
  );
}

sub Bot_mcpan_plug_resp_recv {
  my ($self, $core) = splice @_, 0, 2;
  my $response = ${ $_[1] };
  my $hints    = ${ $_[2] };

  my $dist = $hints->{Dist};
  my $type = $hints->{Type};
  
  unless ($response->is_success) {
    broadcast('message',
      $hints->{Context}, $hints->{Channel},
      "HTTP failure, cannot get release info for $dist"
    );
    return PLUGIN_EAT_ALL
  }

  my $json = $response->content;
  
  unless ($json) {
    broadcast('message',
      $hints->{Context}, $hints->{Channel},
      "Unknown failure -- no data received for $dist",
    );
    return PLUGIN_EAT_ALL
  }

  my $ser = Bot::Cobalt::Serializer->new('JSON');
  
  my $d_hash;
  {
    eval { $d_hash = $ser->thaw($json) };
    if ($@) {
      broadcast( 'message',
        $hints->{Context}, $hints->{Channel},
        "Decoder failure; err: $@",
      );
      return PLUGIN_EAT_ALL
    }
  }
  
  unless ($d_hash && ref $d_hash eq 'HASH') {
    broadcast( 'message',
      $hints->{Context}, $hints->{Channel},
      "Odd; no hash received after decode for $dist"
    );
    return PLUGIN_EAT_ALL
  }
  
  ## FIXME

}

1;
