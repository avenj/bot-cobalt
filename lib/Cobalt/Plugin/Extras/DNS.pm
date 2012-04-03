package Cobalt::Plugin::Extras::DNS;
our $VERSION = '0.001';

use 5.12.1;
use Cobalt::Common;

use POE::Component::Client::DNS;

sub new { bless {}, shift }

sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;

  POE::Session->create(
    object_states => [
      $self => [
        '_start',
        '_dns_resp_recv',
      ],
    ],
  );

  $core->plugin_register( $self, 'SERVER',
    [ 'public_cmd_dns', ],
  );
  
  $core->log->info("Loaded - $VERSION");
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = splice @_, 0, 2;
  $core->log->info("Unloaded");
  return PLUGIN_EAT_NONE  
}

sub Bot_public_cmd_dns {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${ $_[0] };
  my $msg     = ${ $_[1] };
  
  
  return PLUGIN_EAT_ALL
}

sub _start {
  my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];
  $self->{Resolver} = POE::Component::Client::DNS->spawn;
}

sub _dns_resp_recv {
  my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];

}

sub _run_query {
  my ($self, $context, $channel, $host, $type) = @_;
  
  $type = 'A' unless $type 
    and $type =~ /^(A|CNAME|NS|MX|PTR|TXT|AAAA|SRV|SOA)$/i;
  
  $type = 'PTR' if ip_is_ipv4( $query );
  ## FIXME v6 rr lookup?
  
  my $resp = $self->{Resolver}->resolve(
    event => '_dns_resp_recv',
    host  => $host,
    type  => $type,
    context => { Context => $context, Channel => $channel },
  );
  POE::Kernel->yield('_dns_resp_recv', $resp) if $resp;
  return 1
}

1;
