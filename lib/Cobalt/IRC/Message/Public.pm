package Cobalt::IRC::Message::Public;

use 5.10.1;
use Cobalt::Common;

use Moo;
use Sub::Quote;

extends 'Cobalt::IRC::Message';

has 'channel' => ( is => 'rw', isa => Str, lazy => 1,
  default => quote_sub q{ $_[0]->target },
);

has 'cmd' => ( is => 'rw', lazy => 1,
  default => quote_sub q{
    my ($self) = @_;
    my $cf_core = $self->core->get_core_cfg;
    my $cmdchar = $cf_core->{Opts}->{CmdChar} // '!' ;
    my $txt = $self->stripped;
    if ($txt =~ /^${cmdchar}([^\s]+)/) {
      my $message = $self->message_array;
      shift @$message;
      $self->message_array($message);
      return lc($1)
    }
    undef
  },
);

has 'cmdprefix' => ( is => 'ro', isa => Bool, lazy => 1,
  default => quote_sub q{ defined $_[0]->cmd ? 1 : 0 },
);

has 'highlight' => ( is => 'rw', isa => Bool, lazy => 1,
  default => quote_sub q{
    my ($self) = @_;
    my $irc = $self->core->get_irc_obj( $self->context );
    my $me = $irc->nick_name;
    my $txt = $self->stripped;
    $txt =~ /^${me}.?\s+/i
  },  
);


1;
__END__

=pod

=cut
