package Bot::Cobalt::IRC::Message::Public;
our $VERSION = '0.200_48';

use 5.10.1;

use Bot::Cobalt;
use Bot::Cobalt::Common;

use Moo;

extends 'Bot::Cobalt::IRC::Message';

has 'cmd' => ( is => 'rw', lazy => 1,
  default => sub {
    my ($self) = @_;
    my $cf_core = core->get_core_cfg;
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

has 'highlight' => ( is => 'rw', isa => Bool, lazy => 1,
  default => sub {
    my ($self) = @_;
    my $irc = core->get_irc_obj( $self->context );
    my $me = $irc->nick_name;
    my $txt = $self->stripped;
    $txt =~ /^${me}.?\s+/i
  },  
);


1;
__END__

=pod

=head1 NAME

Bot::Cobalt::IRC::Message::Public - Public message subclass

=head1 SYNOPSIS

  sub Bot_public_msg {
    my ($self, $core) = splice @_, 0, 2;
    my $msg = ${ $_[0] };
    
    if ($msg->highlight) {
      . . . 
    }
  }

=head1 DESCRIPTION

This is a subclass of L<Bot::Cobalt::IRC::Message> -- almost everything you 
might need is documented there.

When an incoming message is a public (channel) message, the provided 
C<$msg> object has the following extra methods available:

=head2 highlight

If the bot appears to have been highlighted (ie, the message is prefixed 
with the bot's nickname), this method will return boolean true.

Used to see if someone is "talking to" the bot.

=head2 cmd

If the message appears to actually be a command and some arguments, 
B<cmd> will return the specified command and automatically shift 
the B<message_array> leftwards to drop the command from 
B<message_array>.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

L<http://www.cobaltirc.org>

=cut
