package Cobalt::IRC::Action;

use 5.10.1;
use Cobalt::Common;

use Moo;
use Sub::Quote;

extends 'Cobalt::IRC::Message';

has 'channel' => ( is => 'rw', isa => Str, lazy => 1,
  default => quote_sub q{
    $_[0]->target =~ /^[#&+]/ ? $_[0]->target : ''
  },
);


1;
__END__

=pod

=cut
