package Bot::Cobalt::Plugin::Rehash;
our $VERSION = '0.200_48';

## HANDLES AND EATS:
##  !rehash
##
##  Rehash langs + channels.conf & plugins.conf
##
##  Does NOT rehash plugin confs
##  Plugins often do some initialization after a conf load
##  Reload them using PluginMgr's !reload function instead.
##
## Also doesn't make very many guarantees regarding consequences ...

use 5.10.1;
use Bot::Cobalt;
use Bot::Cobalt::Common;
use Bot::Cobalt::Conf;

## dclone used so we can easily throw away unwanted Bot::Cobalt::Conf hashes:
use Storable qw/dclone/;

require Bot::Cobalt::Lang;

sub new { bless {}, shift }

sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;
  $self->{core} = $core;
  $core->plugin_register( $self, 'SERVER',
    [ 'rehash', 'public_cmd_rehash' ]
  );
  $core->log->info("Registered, commands: !rehash");
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = splice @_, 0, 2;
  $self->{core} = $core;
  $core->log->info("Unregistered");
  return PLUGIN_EAT_NONE
}

sub Bot_rehash {
  my ($self, $core) = splice @_, 0, 2;
  $self->_rehash_core_cf;
  $self->_rehash_channels_cf;
  $self->_rehash_plugins_cf;
  return PLUGIN_EAT_NONE
}

sub Bot_public_cmd_rehash {
  my ($self, $core) = splice @_, 0, 2;
  my $msg     = ${$_[0]};
  my $context = $msg->context;

  my $nick = $msg->src_nick;
  my $auth_lev = $core->auth->level($context, $nick);
  my $auth_usr = $core->auth->username($context, $nick);

  my $pcfg = $core->get_plugin_cfg($self);
  my $required_lev = $pcfg->{PluginOpts}->{LevelRequired} // 9999;

  unless ($auth_lev >= $required_lev) {
    my $resp = rplprintf( $core->lang->{RPL_NO_ACCESS},
      { nick => $nick }
    );
    broadcast( 'message', $context, $nick, $resp );
    return PLUGIN_EAT_ALL
  }
  
  my $type = lc($msg->message_array->[0] || 'all');

  my $channel = $msg->channel;
  
  my $resp;
  given ($type) {
    when ("all") {
      if ( 
        $self->_rehash_core_cf  
        && $self->_rehash_channels_cf
        && $self->_rehash_plugins_cf
      ) {
        $resp = "Rehashed configuration files.";
      } else {
        $resp = "Could not rehash some confs; admin should check logs.";
      }
    }

    when ("core") {
      if ($self->_rehash_core_cf) {
        $resp = "Rehashed core configuration.";
      } else {
        $resp = "Rehash failed; administrator should check logs.";
      }
    }
    
    when ("plugins") {
      if ($self->_rehash_plugins_cf) {
        $resp = "Rehashed plugins.conf.";
      } else {
        $resp = "Rehashing plugins.conf failed; admin should check logs.";
      }
      
    }
    
    when ("langset") {
      if ($self->_rehash_langset) {
        $resp = "Reloaded core language set.";
      } else {
        $resp = "Rehashing langset failed; administrator should check logs.";
      }
    }
    
    when ("channels") {
      if ($self->_rehash_channels_cf) {
        $resp = "Rehashed channels configuration.";
        ## FIXME catch rehash event in ::IRC so we can unload and reload AutoJoin plugin w/ new 
        ##  channels
      } else {
        $resp = "Rehashing channels failed; administrator should check logs.";
      }
    }
    
    ## FIXME langsets
  }

  broadcast( 'message', $context, $channel, $resp ) if $resp;

  return PLUGIN_EAT_ALL
}


sub _rehash_all_plugins {
  ## the code is here, but specifically disabled for now.
  ## plugins should be reloaded specifically instead.
  my ($self) = @_;
  my $core = $self->{core};
  
  my $newcfg = $self->_get_new_cfg || return;
  
  unless ($newcfg->{plugin_cf} and ref $newcfg->{plugins} eq 'HASH') {
    $core->log->warn(
      "Rehashed conf appears to be missing plugin-specific confs"
    );
    $core->log->warn("Are you missing plugins/ conf files?");
    return
  }

  $core->cfg->{plugin_cf} = dclone($newcfg->{plugin_cf});
}

sub _rehash_plugins_cf {
  my ($self) = @_;
  my $core = $self->{core};
  
  my $newcfg = $self->_get_new_cfg || return;
  
  unless ($newcfg->{plugins} and ref $newcfg->{plugins} eq 'HASH') {
    $core->log->warn("Rehashed conf appears to be missing plugins conf");
    $core->log->warn("Is your plugins.conf broken?");
    my $etcdir = $core->etc;
    $core->log->warn("(Path to etc/: $etcdir)");
    return
  }
  
  $core->cfg->{plugins} = dclone($newcfg->{plugins});
  $core->log->info("Reloaded plugins.conf");
  broadcast( 'rehashed', 'plugins' );
  return 1
}

sub _rehash_core_cf {
  my ($self) = @_;
  my $core = $self->{core};

  my $newcfg = $self->_get_new_cfg || return;
  
  unless ($newcfg->{core} and ref $newcfg->{core} eq 'HASH') {
    $core->log->warn("Rehashed conf appears to be missing core conf");
    $core->log->warn("Is your cobalt.conf broken?");
    my $etcdir = $core->etc;
    $core->log->warn("(Path to etc/: $etcdir)");
    return
  }

  $core->cfg->{core} = dclone($newcfg->{core});
  $core->log->info("Reloaded core config.");
  ## Bot_rehash ($type) :
  broadcast( 'rehashed', 'core' );
  return 1
}

sub _rehash_channels_cf {
  my ($self) = @_;
  my $core = $self->{core};
  
  my $newcfg = $self->_get_new_cfg || return;
  
  unless ($newcfg->{channels} and ref $newcfg->{channels} eq 'HASH') {
    $core->log->warn("Rehashed conf appears to be missing channels conf");
    $core->log->warn("Is your channels.conf broken?");
    my $etcdir = $core->etc;
    $core->log->warn("(Path to etc/: $etcdir)");
    return
  }

  $core->cfg->{channels} = dclone($newcfg->{channels});
  $core->log->info("Reloaded channels config.");
  broadcast( 'rehashed', 'channels' );
  return 1
}

sub _rehash_langset {
  my ($self) = @_;
  my $core = $self->{core};
  
  my $newcfg  = $self->_get_new_cfg || return;
  my $lang = $newcfg->{core}->{Language} // 'english' ;
  my $prefix = $core->etc ."/langs/" ;
  
  my $new_rpl = Bot::Cobalt::Lang->load_langset($lang, $prefix);
  
  unless ($new_rpl && ref $new_rpl eq 'HASH') {
    $core->log->warn("Bot::Cobalt::Lang did not return a hash.");
    $core->log->warn("Failed to load langset $lang from $prefix");
    return
  }
  
  unless (scalar keys %$new_rpl) {
    $core->log->warn("Bot::Cobalt::Lang returned a hash with no keys.");
    $core->log->warn("Failed to load langset $lang from $prefix");
    return
  }
  
  for my $this_rpl (keys %$new_rpl) {
    $core->log->debug("Updated: $this_rpl")
      if $core->debug > 2;
    $core->lang->{$this_rpl} = $new_rpl->{$this_rpl};
  }
  $core->log->info("Reloaded core langset ($lang)");
  broadcast( 'rehashed', 'langset' );
  return 1
}

sub _get_new_cfg {
  my ($self) = @_;
  my $core = $self->{core};
  my $etcdir = $core->etc;
  my $ccf = Bot::Cobalt::Conf->new(etc=>$etcdir);
  my $newcfg = $ccf->read_cfg;
  
  unless (ref $newcfg eq 'HASH') {
    $core->log->warn("_get_new_cfg; Bot::Cobalt::Conf did not return a hash");
    $core->log->warn("(Path to etc/: $etcdir)");
    return
  }
  return $newcfg
}


1;
__END__

=pod

=head1 NAME

Bot::Cobalt::Plugin::Rehash - rehash configuration on-the-fly

=head1 SYNOPSIS

  Rehash 'cobalt.conf':
   !rehash core
  
  Rehash 'channels.conf':
   !rehash channels
 
  Rehash 'plugins.conf':
   !rehash plugins
  
  All of the above:
   !rehash all

=head1 DESCRIPTION

Reloads configuration files on the fly.

B<IMPORTANT:> The Rehash plugin does B<not> reload plugin-specific configs.

For that, use a plugin manager's reload ability. See L<Bot::Cobalt::Plugin::PluginMgr>.

=head1 EMITTED EVENTS

Every rehash triggers a B<Bot_rehashed> event, informing the plugin pipeline 
of the newly reloaded configuration values.

The first event argument is the type of rehash that was performed; it 
will be one of I<core>, I<channels>, I<langset>, or I<plugins>.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

L<http://www.cobaltirc.org>

=cut
