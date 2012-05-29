package Bot::Cobalt::IRC::Message::Public;
our $VERSION = '0.005';

use 5.10.1;

use Bot::Cobalt;
use Bot::Cobalt::Common;

use Moo;

use Scalar::Util qw/blessed/;

extends 'Bot::Cobalt::IRC::Message';

has 'cmd' => ( is => 'rw', lazy => 1,
  predicate => 'has_cmd',
  builder   => '_build_cmd',
);

has 'highlight' => ( is => 'rw', isa => Bool, lazy => 1,
  predicate => 'has_highlight',
  builder   => '_build_highlight',
);

has 'myself' => ( is => 'rw', isa => Str, lazy => 1,
  default => sub {
    my ($self) = @_;
    
    require Bot::Cobalt::Core;
    return '' unless Bot::Cobalt::Core->has_instance;
    
    my $irc = irc_object( $self->context ) || return '';  
    blessed $irc ? $irc->nick_name : '';
  },
);

after 'message' => sub {
  my ($self, $value) = @_;
  
  if ($self->has_highlight) {
    $self->highlight( $self->_build_highlight );
  }
  
  if ($self->has_cmd) {
    $self->cmd( $self->_build_cmd );
  }
};

sub _build_highlight {
  my ($self) = @_;
  my $me  = $self->myself || return 0;
  my $txt = $self->stripped;
  $txt =~ /^${me}[,:;!-]?\s+/i
}

sub _build_cmd {
  my ($self) = @_;

  my $cmdchar;
  
  require Bot::Cobalt::Core;
  if ( Bot::Cobalt::Core->has_instance ) {
    my $cf_core = core->get_core_cfg;
    $cmdchar = $cf_core->{Opts}->{CmdChar} // '!' ;
  } else {
    $cmdchar = '!';
  }
  
  my $txt = $self->stripped;

  if ($txt =~ /^${cmdchar}([^\s]+)/) {
    my $message = $self->message_array;
    shift @$message;
    $self->message_array($message);

    return lc($1)
  }
  undef
}


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

This is a subclass of L<Bot::Cobalt::IRC::Message> -- most methods are 
documented there.

When an incoming message is a public (channel) message, the provided 
C<$msg> object has the following extra methods available:

=head2 myself

The 'myself' attribute can be tweaked to change how L</highlight> 
behaves. By default it will query the L<Bot::Cobalt::Core> instance for 
an IRC object that can return the bot's current nickname.

=head2 highlight

If the bot appears to have been highlighted (ie, the message is prefixed 
with L</myself>), this method will return boolean true.

Used to see if someone is "talking to" the bot.

=head2 cmd

If the message appears to actually be a command and some arguments, 
B<cmd> will return the specified command and automatically shift 
the B<message_array> leftwards to drop the command from 
B<message_array>. 

Normally this isn't used directly by plugins other 
than L<Cobalt::IRC>; a Message object handed off by a Bot_public_cmd_* 
event has this done for you already, for example.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

L<http://www.cobaltirc.org>

=cut
