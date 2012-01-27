package Cobalt::Plugin::WWW;
our $VERSION = '0.04';

## async http with responses pushed to plugin pipeline
## send response to pipeline via that event with args attached
##
## rather simplistic, could use improvement

use 5.12.1;
use strict;
use warnings;

use Object::Pluggable::Constants qw/:ALL/;

use POE;
use POE::Session;
use POE::Component::Client::keepalive;
use POE::Component::Client::HTTP;

use HTTP::Request;
use HTTP::Response;

sub new { bless {}, shift }

sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;
  $self->{core} = $core;
  $core->log->info("Creating HTTP client session . . .");
  $self->{ActiveReqs} = { };
  $core->plugin_register( $self, 'SERVER',
    [ 'www_request' ],
  );  

  POE::Session->create(
    object_states => [
      $self => {
        '_start' => '_start',
        '_stop'  => '_shutdown',
        'on_response' => '_handle_response',
      },
    ],
  );
  
  $core->log->info("Registered");
  return PLUGIN_EAT_NONE
}

sub _shutdown {
  $_[OBJECT]->{core}->log->info("Session shutdown.");
  $_[KERNEL]->post('httpUA' => 'shutdown');
  $_[KERNEL]->alias_remove('WWW');
  $_[OBJECT]->{core}->log->debug("cleanup finished");
}

sub _start {
  my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];
  $kernel->alias_set('WWW');
  my $core = $self->{core};
  $core->log->debug("POE session spawned.");

  my $pcfg = $core->get_plugin_cfg( __PACKAGE__ );

  my %htopts = (
    Alias => 'httpUA',
    Agent => 'Cobalt2 IRC bot',
    Timeout => $pcfg->{Opts}->{Timeout} // 60,
  );
  
  ## FIXME should we handle 302s and build a response chain ... ?
  
  $htopts{Proxy} = $pcfg->{Opts}->{Proxy} if $pcfg->{Opts}->{Proxy};
  $htopts{BindAddr} = $pcfg->{Opts}->{BindAddr}
    if $pcfg->{Opts}->{BindAddr};

  my $pool = POE::Component::Client::Keepalive->new(
    keep_alive = 1,
  );

  ## Client::HTTP exists as an external session
  ## spawn one called 'httpUA'
  POE::Component::Client::HTTP->spawn(
    ConnectionManager => $pool,
    %htopts
  );
  
  $core->log->info("Asynchronous HTTP user agent spawned.");
}

sub Cobalt_unregister {
  my ($self, $core) = splice @_, 0, 2;
  ## post shutdown to httpUA:
#  $poe_kernel->post( 'httpUA', 'shutdown' );
  $poe_kernel->post( 'WWW', '_stop' );
  ## FIXME refcount_decrement our own session ... ?
  ## probably not necessary.
  $core->log->info("Unregistered");
  return PLUGIN_EAT_NONE
}

sub Bot_www_request {
  my ($self, $core) = splice @_, 0, 2;

  ## SERVER event:
  ##  'www_request', $request, $event, $args
  ## $request should be a HTTP::Request
  ## bridges async http and our plugin pipeline

  my $request = ${ $_[0] };  ## HTTP::Request obj
  my $event  = ${ $_[1] };  ## pipeline event to send
  my $ev_arg = ${ $_[2] };  ## arrayref to attach as args, optional
  my $req_id = ${ $_[3] };  ## ID for this job, optional
  
  return PLUGIN_EAT_NONE unless $request;
  
  unless (ref $request) {
    ## passed a string request?
    ## try to create a request, no promises:
    $request = HTTP::Request->parse($request);
    ## FIXME catch errors?
  }
  
  $ev_arg = [ ] unless $ev_arg;
  
  unless ($req_id) {
    my @p = ('a' .. 'z', 'A' .. 'Z', 0 .. 9);
    do {
      $req_id = join '', map { $p[rand@p] } 1 .. 5;
    } while exists $self->{ActiveReqs}->{$req_id};
  } ## FIXME cancel existing job if req_id already exists?

  $core->log->debug("httpUA req; $req_id -> $event");

  $self->{ActiveReqs}->{$req_id} = {
    String => $request->as_string,
    Object => $request,
    Event  => $event || undef,
    EventArgs => $ev_arg,
  };

  ## post to httpUA, tagged with our id
  $poe_kernel->post( 'httpUA' =>
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

  $core->log->debug("handling httpUA response for $req_tag");
  
  ## this request is done, get its state hash
  my $stored_req = delete $self->{ActiveReqs}->{$req_tag};
  
  my $ht_content;
  
  if ($response->is_success) {
    $core->log->debug("successful httpUA request");
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
  } else {
    $core->log->debug("handled response for $req_tag but no content");
  }

}

1;
__END__

=pod

=head1 NAME

Cobalt::Plugin::WWW - asynchronous HTTP plugin

=head1 SYNOPSIS

  ## (inside a command handler, perhaps)
  ## send off a HTTP request:
  $core->send_event( 'www_request', $request, $event, $args );
  ## f.ex:
  my $request = HTTP::Request->new('POST', $url);
  ## Note that content() should be BYTES
  ## (see perldoc Encode)
  $request->content("key => value");
  $core->send_event( 'www_request', 
    $request,
    'myplugin_resp',
    [ $some_arg, $some_other_arg ] 
  );
  
  ## handle event myplugin_got_resp:
  sub Bot_myplugin_got_resp {
    my ($self, $core) = splice @_, 0, 2;
    ## First arg is decoded content:
    my $decoded_content = ${ $_[0] };
    ## Second arg is the HTTP::Response object:
    my $response_obj = ${ $_[1] };
    ## Third arg is usually arguments in an arrayref:
    my $argref = ${ $_[2] };

    return PLUGIN_EAT_ALL
  }

=head1 DESCRIPTION

The B<WWW> plugin provides an asynchronous HTTP interface that is 
automatically connected to the plugin event pipeline.

That is to say, a plugin can fire off a B<www_request> event:

  my $request = HTTP::Request->new('GET', $url);
  $core->send_event( 'www_request',
    $request, 'myplugin_got_resp',
    [ $context, $channel, $user ]
  );

The request will be handled asynchronously via L<POE::Component::Client::HTTP>.

When a response is ready, it'll be relayed to the plugin pipeline so your 
plugin can register to receive and handle it. See the sample code in the 
SYNOPSIS for a simple handler. The first argument is the decoded content; 
the second argument is the L<HTTP::Response> object itself, which you may 
need for more complicated processing.

An reference containing arguments can be passed to B<www_request>. 
The arguments will be relayed as arguments to the "handler" event that is 
broadcast upon successful completion. This can be convenient for attaching 
some kind of context information to responses, so you can relay them back to 
IRC or similar..

Check out the B<Extras::Shorten> plugin to see how this works in action.

As of this writing, this plugin is fairly simplistic and does not fail 
especially well -- it'll log the failure and broadcast nothing. Look into 
using the POE component directly for more complicated applications.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

Part of the core Cobalt2 plugin set.

http://www.cobaltirc.org

=cut
