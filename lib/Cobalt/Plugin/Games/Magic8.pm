package Cobalt::Plugin::Games::Magic8;
our $VERSION = '0.02';

use 5.12.1;
use strict;
use warnings;

sub new {
  my $class = shift;
  my $self = {};
  bless($self, $class);
  my %args = @_;
  $self->{core} = $args{core} if $args{core};
  @{ $self->{Responses} } = <DATA>;
  return $self
}

sub execute {
  my ($self, $msg) = @_;
  my $nick = $msg->{src_nick}//'' if ref $msg;
  my @responses = @{ $self->{Responses} };
  return $nick.': '.$responses[rand @responses]
}

1;

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
