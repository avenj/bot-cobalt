package Bot::Cobalt::Plugin::Rehash;
our $VERSION = '0.012';

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

use 5.12.1;
use strictures 1;

use Bot::Cobalt;
use Bot::Cobalt::Common;
use Bot::Cobalt::Conf;
use Bot::Cobalt::Lang;

use File::Spec;
use Try::Tiny;

sub new { bless [], shift }

sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;

  register( $self, 'SERVER',
    'rehash', 'public_cmd_rehash'
  );

  logger->info("Registered, commands: !rehash");
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = splice @_, 0, 2;

  logger->info("Unregistered");
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

  my $auth_lev = core->auth->level($context, $nick);
  my $auth_usr = core->auth->username($context, $nick);

  my $pcfg = plugin_cfg($self) || {};
  my $required_lev = $pcfg->{LevelRequired} // 9999;

  unless ($auth_lev >= $required_lev) {
    my $resp = core->rpl( q{RPL_NO_ACCESS},
      nick => $nick
    );

    broadcast 'message', $context, $nick, $resp;

    return PLUGIN_EAT_ALL
  }
  
  my $type = lc($msg->message_array->[0] || 'all');

  my $channel = $msg->channel;

  ## FIXME split out to method dispatch
  ## <<<< FIXME <<<<
  my $resp;
  for ($type) {
    when ("all") {    ## (except langset)

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
      my $lang = $msg->message_array->[1];
      
      try {
        $self->_rehash_langset($lang);
        $resp = "Reloaded core language set ($lang)";
      } catch {
        $resp = "Rehash failure: $_"
      };

    }
    
    when ("channels") {

      if ($self->_rehash_channels_cf) {
        $resp = "Rehashed channels configuration.";
      } else {
        $resp = "Rehashing channels failed; administrator should check logs.";
      }

    }
    
    default {
      $resp = "Unknown config group, try: core, plugins, langset, channels";
    }
  }
  
  ## >>>> FIXME >>>>

  broadcast 'message', $context, $channel, $resp;

  return PLUGIN_EAT_ALL
}

sub _rehash_plugins_cf {
  my ($self) = @_;

  my $new_cfg_obj = try {
    require Bot::Cobalt::Conf::File::Plugins;

    Bot::Cobalt::Conf::File::Plugins->new(
      etcdir => core()->etc,
      path   => core()->cfg->plugins->path,
    )
  } catch {
    logger->error("Loading new Conf::File::Plugins failed: $_");
    undef
  } || return ;

  core()->cfg->set_plugins( $new_cfg_obj );
  
  logger->info("Reloaded plugins.conf");
  
  broadcast 'rehashed', 'plugins';
  
  return 1
}

sub _rehash_core_cf {
  my ($self) = @_;

  my $new_cfg_obj = try {
    require Bot::Cobalt::Conf::File::Core;
    
    Bot::Cobalt::Conf::File::Core->new(
      path => core()->cfg->core->path,
    )
  } catch {
    logger->error("Loading new Conf::File::Core failed: $_");
    undef
  } || return ;


  core()->cfg->set_core( $new_cfg_obj );
  
  logger->info("Reloaded core config.");
  
  ## Bot_rehash ($type) :
  broadcast 'rehashed', 'core';
  
  return 1
}

sub _rehash_channels_cf {
  my ($self) = @_;

  my $new_cfg_obj = try {
    require Bot::Cobalt::Conf::File::Channels;
    
    Bot::Cobalt::Conf::File::Channels->new(
      path => core()->cfg->channels->path,
    )
  } catch {
    logger->error("Loading new Conf::File::Channels failed: $_");
    undef
  } || return ;

  core()->cfg->set_channels( $new_cfg_obj );

  logger->info("Reloaded channels config.");

  broadcast 'rehashed', 'channels';

  return 1
}

sub _rehash_langset {
  my ($self, $langset) = @_;

  ## FIXME document that you should rehash core then rehash langset
  ##  for updated Language: directives

  my $lang = $langset || core()->cfg->core->language;
  
  my $lang_dir = File::Spec->catdir( core()->etc, 'langs' );

  my $lang_obj =  Bot::Cobalt::Lang->new(
    use_core => 1,
      
    lang_dir => $lang_dir,
    lang     => $lang,
  );

  ## Wrapped in a try{} in dispatcher
  die "Language set $lang has no RPLs"
    unless scalar keys %{ $lang_obj->rpls } ;

  core()->set_langset( $lang_obj );
  core()->set_lang( $lang_obj->rpls );
  
  logger->info("Reloaded core langset ($lang)");

  broadcast 'rehashed', 'langset';

  return 1
}


1;
__END__

=pod

=head1 NAME

Bot::Cobalt::Plugin::Rehash - Rehash config or langs on-the-fly

=head1 SYNOPSIS

  Rehash 'cobalt.conf':
   !rehash core
  
  Rehash 'channels.conf':
   !rehash channels
 
  Rehash 'plugins.conf':
   !rehash plugins
  
  All of the above:
   !rehash all

  Load a different language set:
   !rehash langset ebonics
   !rehash langset english

=head1 DESCRIPTION

Reloads configuration files or language sets on the fly.

Few guarantees regarding consequences are made as of this writing; 
playing with core configuration options might not necessarily always do 
what you expect. (Feel free to report as bugs via either RT or e-mail, 
of course.)

B<IMPORTANT:> The Rehash plugin does B<not> reload plugin-specific 
configs. For that, use a plugin manager's reload ability. See L<Bot::Cobalt::Plugin::PluginMgr>.

=head1 EMITTED EVENTS

Every rehash triggers a B<Bot_rehashed> event, informing the plugin pipeline 
of the newly reloaded configuration values.

The first event argument is the type of rehash that was performed; it 
will be one of I<core>, I<channels>, I<langset>, or I<plugins>.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
