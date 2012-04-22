package Cobalt::IRC::Message;

use 5.10.1;

use Cobalt::Common;

use Moo;
use MooX::Types::MooseLike;

has 'context' => ( is => 'rw' );


__PACKAGE__->meta->make_immutable;
1;
__END__
