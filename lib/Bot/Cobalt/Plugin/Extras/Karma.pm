package Bot::Cobalt::Plugin::Extras::Karma;
our $VERSION = '0.008';

## simple karma++/-- tracking

use 5.10.1;
use strict;
use warnings;

use Object::Pluggable::Constants qw/ :ALL /;

use Bot::Cobalt;
use Bot::Cobalt::DB;

use File::Spec;

use IRC::Utils qw/decode_irc/;

sub new { bless {}, shift }

sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;
  
  $self->{Cache} = {};

  my $dbpath = File::Spec->catfile( $core->var, 'karma.db' );
  
  $self->{karmadb} = Bot::Cobalt::DB->new(
    File => $dbpath,
  );

  $self->{karma_regex} = qr/^(\S+)(\+{2}|\-{2})$/;

  $core->plugin_register( $self, 'SERVER',
    [
      'public_msg',
      'public_cmd_karma',
      'public_cmd_resetkarma',
      'karmaplug_sync_db',
    ],
  );

  $core->timer_set( 5,
    { Event => 'karmaplug_sync_db' },
    'KARMAPLUG_SYNC_DB',
  );

  $core->log->info("Registered");

  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = splice @_, 0, 2;
  $core->log->info("Unregistering");
  $self->_sync();
  return PLUGIN_EAT_NONE
}


sub _sync {
  my ($self) = @_;
  my $db   = $self->{karmadb};
  
  return unless keys %{ $self->{Cache} };
  
  unless ($db->dbopen) {
    logger->warn("dbopen failure for karmadb in _sync");
    return
  }
  
  for my $karma_for (keys %{ $self->{Cache} }) {
    my $current = $self->{Cache}->{$karma_for};
    $db->put($karma_for, $current);
  }
  
  $db->dbclose;
  return 1
}

sub _get {
  my ($self, $karma_for) = @_;
  my $db = $self->{karmadb};
  
  return $self->{Cache}->{$karma_for}
    if exists $self->{Cache}->{$karma_for};
  
  unless ($db->dbopen) {
    logger->warn("dbopen failure for karmadb in _get");
    return
  }
  
  my $current = $db->get($karma_for) || 0;
  $self->{Cache}->{$karma_for} = $current;  
  $db->dbclose;
  
  return $current
}

sub Bot_karmaplug_sync_db {
  my ($self, $core) = splice @_, 0, 2;
  
  $self->_sync();

  $core->timer_set( 5,
    { Event => 'karmaplug_sync_db' },
    'KARMAPLUG_SYNC_DB',
  );
  return PLUGIN_EAT_NONE  
}

sub Bot_public_msg {
  my ($self, $core) = splice @_, 0, 2;
  my $msg     = ${$_[0]};
  my $context = $msg->context;
  return PLUGIN_EAT_NONE if $msg->highlight
                         or $msg->cmd;

  my $first_word = $msg->message_array->[0] // return PLUGIN_EAT_NONE;
  $first_word = decode_irc($first_word);

  if ($first_word =~ $self->{karma_regex}) {
    
    my ($karma_for, $karma) = (lc($1), $2);

    my $current = $self->_get($karma_for);

    if      ($karma eq '--') {
      --$current;
    } elsif ($karma eq '++') {
      ++$current;
    }

    $self->{Cache}->{$karma_for} = $current;
  }

  return PLUGIN_EAT_NONE
}

sub Bot_public_cmd_resetkarma {
  my ($self, $core) = splice @_, 0, 2;
  my $msg     = ${$_[0]};
  my $context = $msg->context;
  
  my $nick    = $msg->src_nick;
  
  my $usr_lev = $core->auth->level($context, $nick)
                || return PLUGIN_EAT_ALL;

  my $pcfg = $core->get_plugin_cfg($self);
  my $req_lev = $pcfg->{PluginOpts}->{LevelRequired} || 9999;
  return PLUGIN_EAT_ALL unless $usr_lev >= $req_lev;

  my $channel = $msg->target;

  my $karma_for = lc($msg->message_array->[0] || return PLUGIN_EAT_ALL);
  $karma_for = decode_irc($karma_for);

  unless ( $self->_get($karma_for) ) {
    $core->send_event( 'message', $context, $channel,
      "That user has no karma as it is.",
    );
    return PLUGIN_EAT_ALL
  }
  
  $self->{Cached}->{$karma_for} = 0;
  
  $core->send_event( 'message', $context, $channel,
    "Cleared karma for $karma_for",
  );
  
  return PLUGIN_EAT_ALL
}

sub Bot_public_cmd_karma {
  my ($self, $core) = splice @_, 0, 2;
  my $msg     = ${$_[0]};
  my $context = $msg->context;

  my $channel = $msg->target;
  my $karma_for = $msg->message_array->[0];
  $karma_for = lc($karma_for || $msg->src_nick);
  $karma_for = decode_irc($karma_for);

  my $resp;

  if ( my $karma = $self->_get($karma_for) ) {
    $resp = "Karma for $karma_for: $karma";
  } else {
    $resp = "$karma_for currently has no karma, good or bad.";
  }

  $core->send_event( 'message', $context, $channel, $resp );

  return PLUGIN_EAT_ALL
}


1;
__END__

=pod

=head1 NAME

Bot::Cobalt::Plugin::Extras::Karma - Simple karma bot plugin

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

Uses L<Bot::Cobalt::DB> for storage, saving to B<karma.db> in the instance's 
C<var/> directory.

If an B<< Opts->LevelRequired >> directive is specified via plugins.conf, 
the specified level will be permitted to clear karmadb entries. Defaults to 
superusers (level 9999).

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
