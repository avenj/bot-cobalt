package Bot::Cobalt::Plugin::Extras::CPAN;
our $VERSION = 1;

use 5.10.1;
use strictures 1;

use Bot::Cobalt;
use Bot::Cobalt::Common;
use Bot::Cobalt::DB;
use Bot::Cobalt::Serializer;

use HTTP::Request;

use Try::Tiny;

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
  
    ## Get latest vers / date and link
    $hints->{Type} = 'latest'   when [qw/latest release/];
    ## Download URL
    $hints->{Type} = 'dist'     when "dist";
    $hints->{Type} = 'tests'    when /^tests?$/;
    $hints->{Type} = 'abstract' when [qw/info abstract/];
    $hints->{Type} = 'license'  when "license";
    
    default {
      broadcast( 'message',
        $msg->context, $msg->channel,
        "Unknown query; try: dist, latest, tests, abstract, license",
      );
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
    my $status = $response->code;
    
    if ($status == 404) {
      broadcast( 'message',
        $hints->{Context}, $hints->{Channel},
        "No such distribution: $dist"
      );
    } else {
      broadcast( 'message',
        $hints->{Context}, $hints->{Channel},
        "Could not get release info for $dist ($status)"
      );
    }

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
    try { 
      $d_hash = $ser->thaw($json) 
    } catch {
      broadcast( 'message',
        $hints->{Context}, $hints->{Channel},
        "Decoder failure; err: $_",
      );
      return PLUGIN_EAT_ALL
    };
  }
  
  unless ($d_hash && ref $d_hash eq 'HASH') {
    broadcast( 'message',
      $hints->{Context}, $hints->{Channel},
      "Odd; no hash received after decode for $dist"
    );
    return PLUGIN_EAT_ALL
  }
  
  my $resp;
  
  given ($type) {
    
    when ("abstract") {
      my $abs = $d_hash->{abstract} || 'No abstract available.';
      $resp = "mCPAN: $dist: $abs";
    }
    
    when ("dist") {
      my $dl = $d_hash->{download_url} || 'No download link available.';
      $resp = "mCPAN: ($dist) $dl";
    }
    
    when ("latest") {
      my $vers = $d_hash->{version};
      my $arc  = $d_hash->{archive};
      $resp = "mCPAN: $dist: Latest version is $vers ($arc)";
    }
    
    when ("license") {
      my $name = $d_hash->{name};
      my $lic  = join ' ', @{ $d_hash->{license} };
      $resp = "mCPAN: License terms for $name: $lic";
    }
    
    when ("tests") {
      my %tests = %{$d_hash->{tests}};
      $resp = sprintf("mCPAN: (%s) %d PASS, %d FAIL, %d NA, %d UNKNOWN",
        $dist, $tests{pass}, $tests{fail}, $tests{na}, $tests{unknown}
      );
    }
  
  }
  
  broadcast( 'message',
    $hints->{Context}, $hints->{Channel}, 
    $resp
  );

  return PLUGIN_EAT_ALL
}

1;
