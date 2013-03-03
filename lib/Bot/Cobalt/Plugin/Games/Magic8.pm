package Bot::Cobalt::Plugin::Games::Magic8;
our $VERSION = '0.016001';

use 5.10.1;
use strict;
use warnings;

my @responses;

sub new { bless [], shift }

sub execute {
  my ($self, $msg) = @_;
  my $nick = $msg->src_nick//'' if ref $msg;
  @responses = <DATA> unless @responses;
  my $selected = $responses[rand @responses];
  chomp($selected);
  return $nick.': '.$selected
}

1;

=pod

=head1 NAME

Bot::Cobalt::Plugin::Games::Magic8 - Ask the Magic 8-ball

=head1 SYNOPSIS

  !magic8 Will today be a good day?

=head1 DESCRIPTION

Ask the magic 8-ball; it knows the answer to all the big questions in 
life.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut

__DATA__
Outlook is grim.
It seems unlikely.
About as likely as a winning Powerball ticket
Hell no!
Well... it's hazy... but maybe... not!
Outlook is uncertain
Chance is in your favor.
Reply hazy, ask again later
Can't you see I'm busy?
Maybe so.
Quite possibly.
Absolutely yes!
It is certain.
Most definitely.
Probably.
Probably not.
Yes.
I think you already know..
Are you sure you want to know?
That could be...
Most likely, yes.
Most likely not.
For sure!
