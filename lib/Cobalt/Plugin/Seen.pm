package Cobalt::Plugin::Seen;
our $VERSION = '0.001';

use Cobalt::Common;
use Cobalt::DB;

use constant {
  TIME     => 0,
  ACTION   => 1,
  CHANNEL  => 2,
  USERNAME => 3,
  HOST     => 4,
};

sub new { bless {}, shift }

sub retrieve {
  my ($self, $context, $nickname) = @_;
  $nickname = $self->parse_nick($context, $nickname);

  my $thisbuf = $self->{Buf}->{$context} // {};

  my $core = $self->{core};

  ## attempt to get from internal hashes
  my($last_ts, $last_act, $last_chan, $last_user, $last_host);

  my $ref;

  if (exists $self->{Buf}->{$context}->{$nickname}) {
    $ref = $self->{Buf}->{$context}->{$nickname};
  } else {
    my $db = $self->{SDB};
    unless ($db->dbopen) {
      $core->log->warn("dbopen failed in retrieve; cannot open SeenDB");
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

  ## fetchable via constants
  ## TIME, ACTION, CHANNEL, USERNAME, HOST
  return($last_ts, $last_act, $last_chan, $last_user, $last_host)
}

sub update {
  my ($self) = @_;
  ## called by seendb_update timer
  ## update db from hashes and trim hashes appropriately
}

sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;
  $self->{core} = $core;
    
  my $pcfg = $core->get_plugin_cfg($self);
  my $seendb_path = $pcfg->{PluginOpts}->{SeenDB}
                    || "seen.db" ;
  $seendb_path = $core->var ."/". $seendb_path ;

  $core->log->debug("Opening SeenDB at $seendb_path");

  $self->{Buf} = { };
  
  $self->{SDB} = Cobalt::DB->new(
    File => $seendb_path,
  );
  
  my $rc = $self->{SDB}->dbopen;
  $self->{SDB}->dbclose;
  die "Unable to open SeenDB at $seendb_path"
    unless $rc;

  $core->plugin_register( $self, 'SERVER', 
    [ qw/
    
      public_cmd_seen
      
      user_joined
      user_left
      user_quit
      
      seendb_update
      
    / ],
  );
  
  $core->timer_set( 6,
    ## update seendb out of hash
    {
      Event => 'seendb_update',
    },
    'SEENDB_WRITE'
  );
  
  $core->log->info("Loaded ($VERSION)");
  
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = splice @_, 0, 2;
  $core->log->info("Unloaded");
  return PLUGIN_EAT_NONE
}

sub parse_nick {
  my ($self, $context, $nickname) = @_;
  my $core = $self->{core};
  my $casemap = $core->get_irc_casemap($context) || 'rfc1459';
  return lc_irc($nickname, $casemap)
}

sub Bot_user_joined {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${ $_[0] };
  my $join    = ${ $_[1] };

  my $nick = $join->{src_nick};
  my $user = $join->{src_user};
  my $host = $join->{src_host};
  my $chan = $join->{channel};
  
  ## FIXME buffer and write on a timer
  
  return PLUGIN_EAT_NONE
}

sub Bot_user_left {
  my ($self, $core) = splice @_, 0, 2;
  
  return PLUGIN_EAT_NONE
}

sub Bot_user_quit {
  my ($self, $core) = splice @_, 0, 2;
  
  return PLUGIN_EAT_NONE
}


1;
__END__
