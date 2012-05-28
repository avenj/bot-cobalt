package Bot::Cobalt::Plugin::Games::Roulette;
our $VERSION = '0.004';

use 5.10.1;
use strict;
use warnings;

use Bot::Cobalt;
use Bot::Cobalt::Utils qw/color/;

sub new { bless {}, shift }

sub execute {
  my ($self, $msg, $str) = @_;
  my $cyls = 6;

  my $context = $msg->context;
  my $nick    = $msg->src_nick;

  if ( $str && index(lc($str), 'spin') == 0 ) {
    ## clear loaded
    delete $self->{Cylinder}->{$context}->{$nick};
    return "Spun cylinders for ${nick}."
  }

  my $loaded = $self->{Cylinder}->{$context}->{$nick}->{Loaded}
               //= int rand($cyls);

  if ($loaded == 0) {
    delete $self->{Cylinder}->{$context}->{$nick};
    
    my $irc  = core->get_irc_obj($context);
    my $bot  = $irc->nick_name;
    my $chan = $msg->channel;

    if ( $irc->is_channel_operator($chan, $bot)
          ## support silly +q/+a modes also
          ## (because I feel sorry for the unrealircd kids)
          ##  - avenj
         || $irc->is_channel_admin($chan, $bot)
         || $irc->is_channel_owner($chan, $bot) )
    {
      broadcast( 'kick', $context, $chan, $nick,
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

=pod

=head1 NAME

Bot::Cobalt::Plugin::Games::Roulette - IRC Russian Roulette

=head1 SYNOPSIS

  !rr      # Pull the trigger
  !rr spin # Spin the cylinders

=head1 DESCRIPTION

IRC Russian Roulette.

Each user gets their own gun; multiple users can play at the same time 
without interfering with each other.

If the bot has operator status, a losing try will result in a kick.

Cylinders are automatically reloaded after losing; they can also be 
manually reset via I<spin>.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

Significant assistance from I<Schroedingers_hat> @ B<irc.cobaltirc.org>

=cut
