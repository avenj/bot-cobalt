package Cobalt::IRC::UserEvent;

## Base class for IRC events.

use 5.10.1;
use Cobalt::Common;
use Moo;

has 'core'    => ( is => 'rw', isa => Object, required => 1 );
has 'context' => ( is => 'rw', isa => Str, required => 1 );
has 'src'     => ( is => 'rw', isa => Str, required => 1 );

has 'src_nick' => (  is => 'rw', lazy => 1,
  default => sub { (parse_user($_[0]->src))[0] },
);

has 'src_user' => (  is => 'rw', lazy => 1,
  default => sub { (parse_user($_[0]->src))[1] },
);

has 'src_host' => (  is => 'rw', lazy => 1,
  default => sub { (parse_user($_[0]->src))[2] },
);

1;
__END__

=pod

=head1 NAME

Cobalt::IRC::UserEvent - Represent an IRC event

=head1 SYNOPSIS

  sub Bot_private_msg {
    my ($self, $core) = splice @_, 0, 2;
    my $msg = ${ $_[0] };
    
    my $context  = $msg->context;
    my $stripped = $msg->stripped;
    my $nickname = $msg->src_nick;
    . . . 
  }

=head1 DESCRIPTION

This is the base class for user-generated IRC events; Things Happening 
on IRC are generally turned into some subclass of this package.

=head1 METHODS

=head2 context

Returns the server context name.

=head2 src

Returns the full source of the message in the form of C<nick!user@host>

=head2 src_nick

The 'nick' portion of the message's L</src>.

=head2 src_user

The 'user' portion of the message's L</src>.

May be undefined if the message was "odd."

=head2 src_host

The 'host' portion of the message's L</src>.

May be undefined if the message was "odd."

=head1 SEE ALSO

L<Cobalt::IRC::Message> -- subclass for messages, notices, and actions

L<Cobalt::IRC::Message::Public> -- subclass for public messages

L<Cobalt::Manual::Plugins>

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

L<http://www.cobaltirc.org>

=end
