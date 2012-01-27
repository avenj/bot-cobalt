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

use Object::Pluggable::Constants qw/: ALL /;

use POE;
use POE::Component::Client::HTTP;

use HTTP::Request;
use HTTP::Response;

use URI::Escape;

sub new {
  my $self = {};
  my $class = shift;
  $self->{ActiveReqs} = { };
  bless $self, $class;
  return $self
}

sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;
  $core->log->info("Creating HTTP client session . . .");
  POE::Session->create(
    object_states => [
      $self => [
        on_response => '_handle_response',
      ],
    ],
  );

  ## Client::HTTP exists as an external session
  ## spawn one called 'httpUA'
  POE::Component::Client::HTTP->spawn(
    Alias => 'httpUA',
    Agent => 'Cobalt2 IRC bot '.$core->version,
    ## FIXME configurable bindaddr?
    ## FIXME followredirects ?
    ## FIXME proxy?
    ## FIXME timeout?
  );
  
  $core->log->info("Registered");
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = splice @_, 0, 2;
  ## FIXME cancel pending requests?
  ##  post shutdown to httpUA?
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
  $poe_kernel->post( 'httpUA', 'request', 'on_response', $request, $req_id );

  return PLUGIN_EAT_NONE
}


## our session's handlers

sub _handle_response {
  my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];
  my ($req, $resp) = @_[ARG0, ARG1];
  my $req_obj  = $req->[0];
  my $req_tag  = $req->[1];  ## $req_id passed in www_request's httpUA post
  my $resp_obj = $resp->[0];
  
  my $core = $self->{core};
  
  ## this request is done, get its state hash
  my $stored_req = delete $self->{ActiveReqs}->{$req_tag};

  my $plugin_ev   = $stored_req->{Event};
  my $plugin_args = $stored_req->{EventArgs};
  
  ## FIXME broadcast response back to plugin pipeline appropriately? 
  ## use http::request's decoded_content ?
  ## check X-PCCH-Errmsg for client errors to log ?

}


1;
