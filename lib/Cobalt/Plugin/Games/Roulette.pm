package Cobalt::Plugin::Games::Roulette;
our $VERSION = '0.004';

use 5.12.1;
use strict;
use warnings;

use Cobalt::Utils qw/color/;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;
  my %args = @_;
  $self->{core} = $args{core} if ref $args{core};
  return $self
}

sub execute {
  my ($self, $msg) = @_;
  my $cyls = 6;

  my $context = $msg->{context};
  my $nick = $msg->{src_nick};

  my $loaded = $self->{Cylinder}->{$context}->{$nick}->{Loaded}
               //= int rand($cyls);

  if ($loaded == 0) {
    delete $self->{Cylinder}->{$context}->{$nick};
    
    my $core = $self->{core};
    my $irc  = $core->get_irc_obj($context);
    my $chan = $msg->{channel};
    my $bot  = $msg->{myself};
    if ( $irc->is_channel_operator($chan, $bot)
          ## support silly +q/+a modes also
          ## (because I feel sorry for the unrealircd kids)
          ##  - avenj
         || $irc->is_channel_admin($chan, $bot)
         || $irc->is_channel_owner($chan, $bot) )
    {
      $core->send_event( 'kick', $context, $chan, $nick,
        "BANG!"
      );
      return color('bold', "$nick did themselves in!")
    } else {
      return color('bold', 'BANG!')." -- seeya $nick!"
    }
  }
  --$self->{Cylinder}->{$context}->{$nick}->{Loaded};
  return 'Click . . .'
}

1;
__END__
