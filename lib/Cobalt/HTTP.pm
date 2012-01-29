package Cobalt::HTTP;
our $VERSION = '0.04';

use strict;
use warnings;

use LWP::UserAgent;

use HTTP::Response;
use HTTP::Request;

use Storable qw/nfreeze thaw/;

use bytes;

sub worker {
  binmode(STDOUT);
  binmode(STDIN);

  STDOUT->autoflush(1);
  
  ## conceptually borrowed from PoCo::Resolver::Sidecar

  my $buf = '';
  my $read_bytes;

  while (1) {
    if (defined $read_bytes) {
      if (length($buf) >= $read_bytes) {
        ## we have a complete reference
        ## pull it out of the buffer:
        my $request = thaw( substr($buf, 0, $read_bytes, "") );
        $read_bytes = undef;

        ## expects named args:        
        my %req = @$request;
        
        my $http_req_str = $req{Request} || die "no HTTP::Request";
        my $tag = $req{Tag} || die "no request tag";
        $req{Timeout} ||= 60;

        my %lwp_opts = (
          agent => __PACKAGE__."/".$VERSION,
          timeout => $req{Timeout},
        );

        ## reconstitute request obj:
        my $http_req_obj = HTTP::Request->parse($http_req_str);

        ## spawn a UA:
        my $ua = LWP::UserAgent->new( %lwp_opts );
        $ua->proxy('http', $req{Proxy}) if $req{Proxy};
        $ua->local_address($req{BindAddr}) if $req{BindAddr};

        ## send blocking request, parse and freeze response:
        my $resp = $ua->request($http_req_obj);
        my $http_response_str = $resp->as_string;
        my $frozen = nfreeze( [ $http_response_str, $tag ] );

        ## prepend length to cooperate with ::Filter::Reference
        my $stream = length($frozen) . chr(0) . $frozen ;
        my $written = syswrite(STDOUT, $stream);
        die $! unless $written == length $stream;
        exit 0
      }
    } elsif ($buf =~ s/^(\d+)\0//) {  ## Filter::Reference gives us a length
      $read_bytes = $1;
      next
    }
  
    my $readb = sysread(STDIN, $buf, 4096, length($buf));
    last unless $readb; ## done when the buffer's empty
  }
  ## this worker's finished
  exit 0
}

1;
