package Cobalt::Plugin::Rehash;
our $VERSION = '0.10';

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

use Cobalt::Common;
use Cobalt::Conf;

sub new { bless {}, shift }

sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;
  $self->{core} = $core;
  $core->plugin_register( $self, 'SERVER',
    [ 'public_cmd_rehash' ]
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

sub Bot_public_cmd_rehash {
  my ($self, $core) = splice @_, 0, 2;

  ## FIXME
  ##  use Cobalt::Conf to grab and reload _core_confs for channels/plugin.conf
  ##  replace $core->cfg->{channels}/{plugins}
  ##  same for langs?

  ## issue event to indicate we've rehashed

  return PLUGIN_EAT_ALL
}


sub _rehash_all_plugins {
  ## FIXME
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
  
  $core->cfg->{plugins} = $newcfg->{plugins};
  $core->log->info("Reloaded plugins.conf");
  $core->send_event( 'rehash', 'plugins' );
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

  $core->cfg->{core} = $newcfg->{core};
  $core->log->info("Reloaded core config.");
  ## Bot_rehash ($type) :
  $core->send_event( 'rehash', 'core' );
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
  
  $core->cfg->{channels} = $newcfg->{channels};
  $core->log->info("Reloaded channels config.");
  $core->send_event( 'rehash', 'channels' );
  return 1
}

sub _get_new_cfg {
  my ($self) = @_;
  my $core = $self->{core};
  my $etcdir = $core->etc;
  my $ccf = Cobalt::Conf->new(etc=>$etcdir);
  my $newcfg = $ccf->read_cfg;
  
  unless (ref $newcfg eq 'HASH') {
    $core->log->warn("_get_new_cfg; Cobalt::Conf did not return a hash");
    $core->log->warn("(Path to etc/: $etcdir)");
    return
  }
  return $newcfg
}


1;
