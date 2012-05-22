package Bot::Cobalt::Plugin::Seen;
our $VERSION = '0.003';

use 5.10.1;

use Bot::Cobalt;
use Bot::Cobalt::Common;
use Bot::Cobalt::DB;

use File::Spec;

use constant {
  TIME     => 0,
  ACTION   => 1,
  CHANNEL  => 2,
  USERNAME => 3,
  HOST     => 4,
  META     => 5,
};

sub new { bless {}, shift }

sub parse_nick {
  my ($self, $context, $nickname) = @_;
  my $casemap = core->get_irc_casemap($context) || 'rfc1459';
  return lc_irc($nickname, $casemap)
}

## FIXME method to retrieve users w/ similar hosts
## !seen search ... ?

sub retrieve {
  my ($self, $context, $nickname) = @_;
  $nickname = $self->parse_nick($context, $nickname);

  my $thisbuf = $self->{Buf}->{$context} // {};

  ## attempt to get from internal hashes
  my($last_ts, $last_act, $last_chan, $last_user, $last_host);

  my $ref;

  if (exists $thisbuf->{$nickname}) {
    $ref = $thisbuf->{$nickname};
  } else {
    my $db = $self->{SDB};
    unless ($db->dbopen) {
      logger->warn("dbopen failed in retrieve; cannot open SeenDB");
      return
    }
    ## context%nickname
    my $thiskey = $context .'%'. $nickname;
    $ref = $db->get($thiskey);
    $db->dbclose;
  }

  return unless defined $ref and ref $ref;

  $last_ts   = $ref->{TS};
  $last_act  = $ref->{Action};
  $last_chan = $ref->{Channel};
  $last_user = $ref->{Username};
  $last_host = $ref->{Host};
  my $meta = $ref->{Meta} // {};

  ## fetchable via constants
  ## TIME, ACTION, CHANNEL, USERNAME, HOST
  return($last_ts, $last_act, $last_chan, $last_user, $last_host, $meta)
}

sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;
    
  my $pcfg = $core->get_plugin_cfg($self);
  my $seendb_path = $pcfg->{PluginOpts}->{SeenDB}
                    || "seen.db" ;
  
  $seendb_path = File::Spec->catfile( $core->var, $seendb_path );
  
  logger->debug("Opening SeenDB at $seendb_path");

  $self->{Buf} = { };
  
  $self->{SDB} = Bot::Cobalt::DB->new(
    File => $seendb_path,
  );
  
  my $rc = $self->{SDB}->dbopen;
  $self->{SDB}->dbclose;
  die "Unable to open SeenDB at $seendb_path"
    unless $rc;

  register( $self, 'SERVER', 
    [ qw/
    
      public_cmd_seen
      
      nick_changed      
      chan_sync
      user_joined
      user_left
      user_quit
      
      seendb_update
      
      seenplug_deferred_list
      
    / ],
  );
  
  core->timer_set( 6,
    ## update seendb out of hash
    {
      Event => 'seendb_update',
    },
    'SEENDB_WRITE'
  );
  
  logger->info("Loaded");
  
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = splice @_, 0, 2;
  $core->log->info("Unloaded");
  return PLUGIN_EAT_NONE
}

sub Bot_seendb_update {
  my ($self, $core) = splice @_, 0, 2;

  my $buf = $self->{Buf};
  my $db  = $self->{SDB};

  unless (keys %$buf) {
    ## Check again later.
    $core->timer_set( 3, { Event => 'seendb_update' } );
    return PLUGIN_EAT_ALL
  }

  CONTEXT: for my $context (keys %$buf) {
    unless ($db->dbopen) {
      logger->warn("dbopen failed in update; cannot update SeenDB");
      $core->timer_set( 3, { Event => 'seendb_update' } );
      return PLUGIN_EAT_ALL
    }

    my $writes;
    NICK: for my $nickname (keys %{ $buf->{$context} }) {
      ## if we've done a lot of writes, yield back.
      if ($writes && $writes % 50 == 0) {
        $db->dbclose;
        broadcast( 'seendb_update' );
        return PLUGIN_EAT_ALL
      }
    
      ## pull this one out:
      my $thisbuf = delete $buf->{$context}->{$nickname};
      
      ## write it to db:
      my $thiskey = $context .'%'. $nickname;
      $db->put($thiskey, $thisbuf);
      ++$writes;
    } ## NICK
    $db->dbclose;
    
    delete $buf->{$context} unless keys %{ $buf->{$context} };
  
  } ## CONTEXT
  
  $core->timer_set( 3,
    { Event => 'seendb_update' }
  );  
  return PLUGIN_EAT_ALL
}

sub Bot_user_joined {
  my ($self, $core) = splice @_, 0, 2;
  my $join    = ${ $_[0] };
  my $context = $join->context;

  my $nick = $join->src_nick;
  my $user = $join->src_user;
  my $host = $join->src_host;
  my $chan = $join->channel;

  $nick = $self->parse_nick($context, $nick);
  $self->{Buf}->{$context}->{$nick} = {
    TS => time(),
    Action   => 'join',
    Channel  => $chan,
    Username => $user,
    Host     => $host,
  };
  
  return PLUGIN_EAT_NONE
}

sub Bot_chan_sync {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${$_[0]};
  my $channel = ${$_[1]};

  broadcast( 'seenplug_deferred_list', $context, $channel );

  return PLUGIN_EAT_NONE
}

sub Bot_seenplug_deferred_list {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${$_[0]};
  my $channel = ${$_[1]};
    
  my $irc = $core->get_irc_object($context);
  
  my @nicks = $irc->channel_list($channel);

  for my $nick (@nicks) {
    $nick = $self->parse_nick($context, $nick);
    
    $self->{Buf}->{$context}->{$nick} = {
      TS => time(),
      Action   => 'present',
      Channel  => $channel,
      Username => '',
      Host     => '',
    };
  }
  
  return PLUGIN_EAT_ALL
}

sub Bot_user_left {
  my ($self, $core) = splice @_, 0, 2;
  my $part    = ${ $_[0] };
  my $context = $part->context;
  
  my $nick = $part->src_nick;
  my $user = $part->src_user;
  my $host = $part->src_host;
  my $chan = $part->channel;

  $nick = $self->parse_nick($context, $nick);
  $self->{Buf}->{$context}->{$nick} = {
    TS => time(),
    Action   => 'part',
    Channel  => $chan,
    Username => $user,
    Host     => $host,
  };

  return PLUGIN_EAT_NONE
}

sub Bot_user_quit {
  my ($self, $core) = splice @_, 0, 2;
  my $quit    = ${ $_[0] };
  my $context = $quit->context;
  
  my $nick = $quit->src_nick;
  my $user = $quit->src_user;
  my $host = $quit->src_host;
  my $common = $quit->common;

  $nick = $self->parse_nick($context, $nick);
  $self->{Buf}->{$context}->{$nick} = {
    TS => time(),
    Action   => 'quit',
    Channel  => $common->[0],
    Username => $user,
    Host     => $host,
  };
  
  return PLUGIN_EAT_NONE
}

sub Bot_nick_changed {
  my ($self, $core) = splice @_, 0, 2;
  my $nchange = ${ $_[0] };
  my $context = $nchange->context;
  return PLUGIN_EAT_NONE if $nchange->equal;
  
  my $old = $nchange->old_nick;
  my $new = $nchange->new_nick;
  
  my $irc = $core->get_irc_obj($context);
  my $src = $irc->nick_long_form($new) || $new;
  my ($nick, $user, $host) = parse_user($src);
  
  my $first_common = $nchange->channels->[0];

  $self->{Buf}->{$context}->{$old} = {
    TS => time(),
    Action   => 'nchange',
    Channel  => $first_common,
    Username => $user || 'unknown',
    Host     => $host || 'unknown',
    Meta     => { To => $new },
  };
  
  $self->{Buf}->{$context}->{$new} = {
    TS => time(),
    Action   => 'nchange',
    Channel  => $first_common,
    Username => $user || 'unknown',
    Host     => $host || 'unknown',
    Meta     => { From => $old },
  };
  
  return PLUGIN_EAT_NONE
}

sub Bot_public_cmd_seen {
  my ($self, $core) = splice @_, 0, 2;
  my $msg     = ${ $_[0] };
  my $context = $msg->context;
  
  my $channel = $msg->channel;
  my $nick    = $msg->src_nick;
  
  my $targetnick = $msg->message_array->[0];
  
  unless ($targetnick) {
    broadcast( 'message', 
      $context,
      $channel,
      "Need a nickname to look for, $nick"
    );
    return PLUGIN_EAT_NONE
  }
  
  my @ret = $self->retrieve($context, $targetnick);
  
  unless (@ret) {
    broadcast( 'message',
      $context,
      $channel,
      "${nick}: I don't know anything about $targetnick"
    );
    return PLUGIN_EAT_NONE
  }
  
  my ($last_ts, $last_act, $last_user, $last_host, $last_chan, $meta) = 
    @ret[TIME, ACTION, USERNAME, HOST, CHANNEL, META];

  my $ts_delta = time() - $last_ts ;
  my $ts_str   = secs_to_str($ts_delta);

  my $resp;
  given ($last_act) {
    when ("quit") {
      $resp = 
        "$targetnick was last seen quitting IRC $ts_str ago";
    }
    
    when ("join") {
      $resp =
        "$targetnick was last seen joining $last_chan $ts_str ago";
    }
    
    when ("part") {
      $resp =
        "$targetnick was last seen leaving $last_chan $ts_str ago";
    }
    
    when ("present") {
      $resp =
        "$targetnick was last seen when I joined $last_chan $ts_str ago";
    }
    
    when ("nchange") {
      if      ($meta->{From}) {
        $resp = 
          "$targetnick was last seen changing nicknames from "
          .$meta->{From}.
          " $ts_str ago";
      } elsif ($meta->{To}) {
        $resp = 
          "$targetnick was last seen changing nicknames to "
          .$meta->{To}.
          " $ts_str ago";
      }
    }
  }  

  broadcast( 'message', 
    $context,
    $channel,
    $resp
  );  
  
  return PLUGIN_EAT_NONE
}

1;
__END__

=pod

=head1 NAME

Bot::Cobalt::Plugin::Seen - IRC 'seen' plugin

=head1 SYNOPSIS

  !seen SomeNickname

=head1 DESCRIPTION

A fairly basic 'seen' command; tracks users joining, leaving, and 
changing nicknames.

Uses L<Bot::Cobalt::DB> for storage.

The path to the SeenDB can be specified via C<plugins.conf>:

  Seen:
    Module: Bot::Cobalt::Plugin::Seen
    Opts:
      SeenDB: path/relative/to/var/seen.db

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

L<http://www.cobaltirc.org>

=cut
