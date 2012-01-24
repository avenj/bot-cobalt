package Cobalt::Plugin::Extras::Karma;
our $VERSION = '0.01';

## simple karma++/-- tracking

use 5.12.1;
use strict;
use warnings;

use Object::Pluggable::Constants qw/ :ALL /;

use Cobalt::Serializer;

sub new { bless {}, shift }

sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;
  $self->{core} = $core;
  $self->{Karma} = $self->_read_karma;
  $self->{karma_regex} = qr/^(\S+)(\+{2}|\-{2})$/;
  $core->plugin_register( $self, 'SERVER',
    [
      'public_msg',
      'public_cmd_karma',
    ],
  );
  $core->log->info("Registered");
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = splice @_, 0, 2;
  $core->log->debug("serializing karmadb to disk");
  $self->_write_karma;
  $core->log->info("Unregistering");
  return PLUGIN_EAT_NONE
}


sub Bot_public_msg {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${$_[0]};
  my $msg = ${$_[1]};
  return PLUGIN_EAT_NONE if $msg->{highlighted};
  return PLUGIN_EAT_NONE if $msg->{cmdprefix};

  my $first_word = $msg->{message_array}->[0] // return PLUGIN_EAT_NONE;
  if ($first_word =~ $self->{karma_regex}) {
    my ($karma_for, $karma) = (lc($1), $2);
    if      ($karma eq '--') {
      $self->{Karma}->{$karma_for}-- ;
    } elsif ($karma eq '++') {
      $self->{Karma}->{$karma_for}++ ;
    }
  }

  return PLUGIN_EAT_NONE
}

sub Bot_public_cmd_karma {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${$_[0]};
  my $msg = ${$_[1]};

  my @message = @{ $msg->{message_array} };
  my $karma_for = lc(shift @message || '');
  $karma_for = $msg->{src_nick} unless $karma_for;

  my $resp;

  if (exists $self->{Karma}->{$karma_for}) {
    my $karma = $self->{Karma}->{$karma_for};
    $resp = "Karma for $karma_for: $karma";
  } else {
    $resp = "$karma_for currently has no karma, good or bad.";
  }

  my $channel = $msg->{target};
  $core->send_event( 'send_message', $context, $channel, $resp );

  return PLUGIN_EAT_ALL
}

sub _read_karma {
  my ($self) = @_;
  my $core = $self->{core};
  my $path = $core->var ."/karma.json";
  unless (-e $path) {
    $core->log->info("No karmadb found, creating a new one");
    return { }
  }
  my $serializer = Cobalt::Serializer->new(Format => 'JSON');
  my $karma = $serializer->readfile( $path ) || { };
  return $karma
}

sub _write_karma {
  my ($self) = @_;
  my $core = $self->{core};
  my $path = $core->var ."/karma.json";
  my $serializer = Cobalt::Serializer->new(Format => 'JSON');
  my $karma = $self->{Karma};
  unless ( $serializer->writefile( $path, $karma ) ) {
    $core->log->warn("Serializer writefile called failed");
    return
  } else { return 1 }
}


1;
