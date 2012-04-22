package Cobalt::IRC::Message;

## Message superclass.
## Subclasses: Private, Public, Action, Notice

## Required input: context, message (unstripped), src (full)

use 5.10.1;
use Cobalt::Common;
use Moo;
use Sub::Quote;

has 'context' => ( is => 'rw', isa => Str, required => 1 );
has 'src'     => ( is => 'rw', isa => Str, required => 1 );

has 'message' => ( is => 'rw', isa => Str, required => 1,
  trigger => quote_sub q{
    my ($self, $value) = @_;
    $self->stripped( strip_color( strip_formatting($value) ) );    
  },
);

has 'targets' => ( is => 'rw', isa => ArrayRef, required => 1 );

has 'target'  => ( is => 'rw', isa => Str, lazy => 1,
  default => quote_sub q{ $_[0]->targets->[0] }, 
);

## Message source.
has 'src_nick' => (  is => 'rw', lazy => 1,
  default => quote_sub q{ (parse_user($_[0]->src))[0] },
);

has 'src_user' => (  is => 'rw', lazy => 1,
  default => quote_sub q{ (parse_user($_[0]->src))[1] },
);

has 'src_host' => (  is => 'rw', lazy => 1,
  default => quote_sub q{ (parse_user($_[0]->src))[2] },
);


## Message content.
has 'stripped' => ( is => 'rw', isa => Str );

has 'message_array' => ( is => 'rw', lazy => 1,
  default => quote_sub q{ split ' ', $self->stripped },
);

has 'message_array_sp' => ( is => 'rw', lazy => 1,
  default => quote_sub q{ split / /, $self->stripped },
);

1;
__END__

=pod

=head1 NAME

Cobalt::IRC::Message - IRC Message base class

=head1 SYNOPSIS

  ## In a message handler:
  sub Bot_public_msg {
    my ($self, $core) = splice @_, 0, 2;
    my $msg = ${ $_[0] };
    
    my $context  = $msg->context;
    my $stripped = $msg->stripped;
    . . . 
  }

=head1 DESCRIPTION

FIXME

=head1 METHODS

=head2 context

=head2 message

=head2 stripped

=head2 FIXME

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

L<http://www.cobaltirc.org>

=end
