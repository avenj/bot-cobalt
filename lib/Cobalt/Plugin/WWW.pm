package Cobalt::Plugin::WWW;
our $VERSION = '0.01';

## async http with responses pushed to plugin pipeline
## set event to trigger and some args on spawn?
## send response to pipeline via that event with args attached?
##
## rather simplistic, could use improvement

use 5.12.1;
use strict;
use warnings;

use Object::Pluggable::Constants qw/:ALL/;

use POE;
use POE::Component::Client::HTTP;

use HTTP::Request;
use HTTP::Response;

use URI::Escape;

sub new { bless {}, shift }

sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;
  $core->log->info("Creating HTTP client session . . .");

  $self->{ActiveReqs} = { };
  
  POE::Session->create(
    object_states => [
      $self => [
        on_response => '_handle_response',
      ],
    ],
  );

  my $pcfg = $core->get_plugin_cfg( __PACKAGE__ );

  my %htopts = (
    Alias => 'httpUA',
    Agent => 'Cobalt2 IRC bot '.$core->version,
    Timeout => $pcfg->{Opts}->{Timeout} // 60,
  );
  
  ## FIXME should we handle 302s and build a response chain ... ?
  
  $htopts{Proxy} = $pcfg->{Opts}->{Proxy} if $pcfg->{Opts}->{Proxy};
  $htopts{BindAddr} = $pcfg->{Opts}->{BindAddr}
    if $pcfg->{Opts}->{BindAddr};

  ## Client::HTTP exists as an external session
  ## spawn one called 'httpUA'
  POE::Component::Client::HTTP->spawn(
    %htopts
  );
  
  $core->log->info("Registered");
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = splice @_, 0, 2;
  ## FIXME cancel pending requests?
  ## post shutdown to httpUA:
  $poe_kernel->post( 'httpUA', 'shutdown' );
  $core->log->info("Unregistered");
  return PLUGIN_EAT_NONE
}

sub Bot_www_request {
  my ($self, $core) = splice @_, 0, 2;

  ## SERVER event:
  ##  'www_request', $method, $uri, $event, $args
  ## build HTTP::Request obj and post to httpUA

  my $method = ${ $_[0] };  ## POST, GET, ...
  my $uri    = ${ $_[1] };  ## URI, will be uri_escape'd
  my $event  = ${ $_[2] };  ## pipeline event to send
  my $ev_arg = ${ $_[3] };  ## arrayref to attach as args, optional
  my $req_id = ${ $_[4] };  ## ID for this job, optional
  
  return PLUGIN_EAT_NONE unless $method and $uri;
  
  $ev_arg = [ ] unless $ev_arg;
  
  unless ($req_id) {
    my @p = ('a' .. 'z', 'A' .. 'Z', 0 .. 9);
    do {
      $req_id = join '', map { $p[rand@p] } 1 .. 5;
    } while exists $self->{ActiveReqs}->{$req_id};
  } ## FIXME cancel existing job if req_id already exists

  $uri = uri_escape($uri);

  my $request = HTTP::Request->new($method, $uri);

  ## FIXME throttle jobs ?

  $self->{ActiveReqs}->{$req_id} = {
    String => $request->as_string,
    Object => $request,
    Event  => $event || undef,
    EventArgs => $ev_arg,
  };

  ## post to httpUA, tagged with our id
  $poe_kernel->post( 'httpUA',
    'request', 'on_response', $request, $req_id
  );

  return PLUGIN_EAT_NONE
}


## our session's handlers

sub _handle_response {
  ## Sends event back in the format:
  ##  $event, $resp_content, $resp_obj, $specified_args
  my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];
  my ($req, $resp) = @_[ARG0, ARG1];
  my $req_obj  = $req->[0];
  my $req_tag  = $req->[1];  ## $req_id passed in www_request's httpUA post
  my $response = $resp->[0];
  
  my $core = $self->{core};
  
  ## this request is done, get its state hash
  my $stored_req = delete $self->{ActiveReqs}->{$req_tag};
  
  my $ht_content;
  
  if ($response->is_success) {
    $ht_content = $response->decoded_content;
  } else {
    $core->log->warn("HTTP failure; ".$response->status_line);
  }
  
  my $pcch_err = $response->header('X-PCCH-Errmsg');
  if ($pcch_err) {
    $core->log->warn("HTTP component reported an error; ".$pcch_err);  
  }
  
  if ($ht_content) { 
    my $plugin_ev   = $stored_req->{Event};
    my $plugin_args = $stored_req->{EventArgs};
    ## throw event back at the plugin pipeline:
    $core->send_event( $plugin_ev, $ht_content, $response, $plugin_args );
  }
  

}


1;
