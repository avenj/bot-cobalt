package Cobalt::IRC::Public;

use 5.10.1;
use Cobalt::Common;

use Moo;
use Sub::Quote;

extends 'Cobalt::IRC::Message';

has 'channel' => ( is => 'rw', isa => Str, lazy => 1,
  default => quote_sub q{ $_[0]->target },
);

has is_cmd => ( is => 'rw', isa => Bool,
  trigger => quote_sub q{
    my ($self, $value) = @_;
    if ($value) {
      ## Modify message_array
      ## message_array_sp is left alone
      my $message = $self->message_array;
      shift @$message;
      $self->message_array($message);
    }
  },
);

has 'cmd' => ( is => 'rw', lazy => 1,
  default => quote_sub q{
    my ($self) = @_;
    my $cf_core = $self->core->get_core_cfg;
    my $cmdchar = $cf_core->{Opts}->{CmdChar} // '!' ;
    my $txt = $self->stripped;
    $txt =~ /^${cmdchar}([^\s]+)/ ? lc($1) : undef
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
