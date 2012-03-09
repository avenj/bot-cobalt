package Cobalt::Plugin::Extras::Karma;
our $VERSION = '0.131';

## simple karma++/-- tracking

use 5.12.1;
use strict;
use warnings;

use Object::Pluggable::Constants qw/ :ALL /;

use Cobalt::DB;

use IRC::Utils qw/decode_irc/;

sub new { bless {}, shift }

sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;
  $self->{core} = $core;

  my $dbpath = $core->var ."/karma.db";
  $self->{karmadb} = Cobalt::DB->new(
    File => $dbpath,
  );

  $self->{karma_regex} = qr/^(\S+)(\+{2}|\-{2})$/;

  $core->plugin_register( $self, 'SERVER',
    [
      'public_msg',
      'public_cmd_karma',
      'public_cmd_resetkarma',
    ],
  );
  $core->log->info("Registered");
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = splice @_, 0, 2;
  $core->log->info("Unregistering");
  return PLUGIN_EAT_NONE
}


sub Bot_public_msg {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${$_[0]};
  my $msg     = ${$_[1]};
  return PLUGIN_EAT_NONE if $msg->{highlighted}
                         or $msg->{cmdprefix};

  my $first_word = $msg->{message_array}->[0] // return PLUGIN_EAT_NONE;
  $first_word = decode_irc($first_word);

  if ($first_word =~ $self->{karma_regex}) {
    
    unless ( $self->{karmadb}->dbopen ) {
      $core->log->warn("dbopen failure for karmadb");
      return PLUGIN_EAT_NONE
    }
    
    my ($karma_for, $karma) = (lc($1), $2);

    my $current = $self->{karmadb}->get($karma_for) // 0;

    if      ($karma eq '--') {
      --$current;
    } elsif ($karma eq '++') {
      ++$current;
    }

    $self->{karmadb}->put($karma_for, $current);

    $self->{karmadb}->dbclose;
  }

  return PLUGIN_EAT_NONE
}

sub Bot_public_cmd_resetkarma {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${$_[0]};
  my $msg     = ${$_[1]};
  my $nick    = $msg->{src_nick};
  
  my $usr_lev = $core->auth_level($context, $nick)
                || return PLUGIN_EAT_ALL;
  my $pcfg = $core->get_plugin_cfg($self);
  my $req_lev = $pcfg->{PluginOpts}->{LevelRequired} || 9999;
  return PLUGIN_EAT_ALL unless $usr_lev >= $req_lev;

  my $channel = $msg->{target};
  my @message = @{ $msg->{message_array} };
  my $karma_for = lc(shift @message || return PLUGIN_EAT_ALL);

  unless ( $self->{karmadb}->dbopen ) {
    $core->log->warn("dbopen failure for karmadb");
    $core->send_event( 'send_message', $context, $channel, 
      "Failed to open karmadb",
    );
    return PLUGIN_EAT_ALL
  }

  unless ( $self->{karmadb}->get($karma_for) ) {
    $core->send_event( 'send_message', $context, $channel,
      "That user has no karmadb entry.",
    );
    $self->{karmadb}->dbclose;
    return PLUGIN_EAT_ALL
  }
  
  if ( $self->{karmadb}->del($karma_for) ) {
    $core->send_event( 'send_message', $context, $channel,
      "Cleared karma for $karma_for",
    );
  } else {
    $core->send_event( 'send_message', $context, $channel,
      "Failed to clear karma for $karma_for",
    );
  }

  $self->{karmadb}->dbclose;  
  
  return PLUGIN_EAT_ALL
}

sub Bot_public_cmd_karma {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${$_[0]};
  my $msg     = ${$_[1]};

  my $channel = $msg->{target};
  my @message = @{ $msg->{message_array} };
  my $karma_for = lc(shift @message || $msg->{src_nick});

  my $resp;

  unless ( $self->{karmadb}->dbopen ) {
    $core->log->warn("dbopen failure for karmadb");
    $core->send_event( 'send_message', $context, $channel, 
      "Failed to open karmadb",
    );
    return PLUGIN_EAT_ALL
  }

  if ( my $karma = $self->{karmadb}->get($karma_for) ) {
    $resp = "Karma for $karma_for: $karma";
  } else {
    $resp = "$karma_for currently has no karma, good or bad.";
  }

  $self->{karmadb}->dbclose;

  $core->send_event( 'send_message', $context, $channel, $resp );

  return PLUGIN_EAT_ALL
}


1;
__END__

=pod

=head1 NAME

Cobalt::Plugin::Extras::Karma - simple karma bot plugin

=head1 SYNOPSIS

  ## Retrieve karma:
  !karma
  !karma <word>

  ## Add or subtract karma:
  <JoeUser> someone++
  <JoeUser> someone--
  
  ## Superusers can clear karma:
  <JoeUser> !resetkarma someone

=head1 DESCRIPTION

A simple 'karma bot' plugin for Cobalt.

Uses L<Cobalt::DB> for storage, saving to B<karma.db> in the instance's 
C<var/> directory.

If an B<< Opts->LevelRequired >> directive is specified via plugins.conf, 
the specified level will be permitted to clear karmadb entries. Defaults to 
superusers (level 9999).

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
