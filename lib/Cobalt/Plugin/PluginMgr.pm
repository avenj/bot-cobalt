package Cobalt::Plugin::PluginMgr;
our $VERSION = '1.0';

## handles and eats: !plugin

use 5.12.1;
use strict;
use warnings;

use Object::Pluggable::Constants qw/ :ALL /;

use Cobalt::Utils qw/ rplprintf /;
use Cobalt::Conf;

sub new { bless {}, shift }

sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;
  $self->{core} = $core;
  $core->plugin_register( $self, 'SERVER',
    'public_cmd_plugin',
  );
  $core->log->info("Registered");
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = splice @_, 0, 2;
  $core->log->info("Unregistered");
  return PLUGIN_EAT_NONE
}

sub _unload {
  my ($self, $alias) = @_;
  my $core = $self->{core};
  my $resp;
  my $plug_obj = $core->plugin_get($alias);
  my $plugisa = ref $plug_obj || return "_unload broken, no PLUGISA?";

  unless ($alias) {
    $resp = "Bad syntax; no plugin alias specified";
  } elsif (! $plug_obj ) {
    $resp = rplprintf( $core->lang->{RPL_PLUGIN_UNLOAD_ERR},
            { 
              plugin => $alias,
              err => 'No such plugin found, is it loaded?' 
            }
    );
  } else {
    $core->log->info("Attempting to unload $alias ($plugisa) per request");
    if ( $core->plugin_del($alias) ) {

      ## shamelessly borrowed from Class::Unload

      ## clear from %INC:
      my $included = join( '/', split /(?:'|::)/, $plugisa ) . '.pm';
      $core->log->debug("removing from INC: $included");
      delete $INC{$included};

      ## clean up symbol table
      no strict 'refs';
      @{$plugisa.'::ISA'} = ();
      my $s_table = $plugisa.'::';
      for my $symbol (keys %$s_table) {
        next if $symbol =~ /\A[^:]+::\z/;
        delete $s_table->{$symbol};
      }
      use strict;

      ## also cleanup our config if there is one:
      delete $core->cfg->{plugin_cf}->{$plugisa};
      
      $resp = rplprintf( $core->lang->{RPL_PLUGIN_UNLOAD}, 
        { plugin => $alias } 
      );
    } else {
      $resp = rplprintf( $core->lang->{RPL_PLUGIN_UNLOAD_ERR},
        { plugin => $alias, err => 'Unknown failure' }
      );
    }

  }

  return $resp
}

sub _load_module {
  ## _load_module( 'Auth', 'Cobalt::Plugin::Auth' ) f.ex
  ## returns a response string for irc
  my ($self, $alias, $module) = @_;
  my $core = $self->{core};

  eval "require $module";
  if ($@) {
    ## 'require' failed
    my $err = $@;
    $core->log->warn("Plugin load failure; $err");
    my $included = join( '/', split /(?:'|::)/, $module ) . '.pm';
    $core->log->debug("removing from INC: $included");
    delete $INC{$included};
    no strict 'refs';
    @{$module.'::ISA'} = ();
    my $s_table = $module.'::';
    for my $symbol (keys %$s_table) {
      next if $symbol =~ /\A[^:]+::\z/;
      delete $s_table->{$symbol};
    }
    use strict;

    return rplprintf( $core->lang->{RPL_PLUGIN_ERR},
        {
          plugin => $alias,
          err => "Module $module cannot be found/loaded: $err",
        }      
    );
  } else {
    ## module found, attempt to load it
    unless ( $module->can('new') ) {
      return rplprintf( $core->lang->{RPL_PLUGIN_ERR},
          {
            plugin => $alias,
            err => "Module $module doesn't appear to have new()",
          }
      );
    }

  }
  my $obj = $module->new();
  unless ($obj && ref $obj) {
      return rplprintf(
          {
            plugin => $alias,
            err => "Constructor for $module returned junk",
          }
      );
  }

  ## plugin_add returns # of plugins in pipeline on success:
  my $loaded = $core->plugin_add( $alias, $obj );
  if ($loaded) {
      return rplprintf( $core->lang->{RPL_PLUGIN_LOAD},
          {
            plugin => $alias,
            module => $module,
          }
      );
  } else {
      return rplprintf( $core->lang->{RPL_PLUGIN_ERR},
          {
            plugin => $alias,
            err => "Unknown plugin_add failure",
          }
      );
  }

}

sub _load {
  my ($self, $alias, $module, $reload) = @_;
  my $core = $self->{core};

  return "Bad syntax; usage: load <alias> [module]"
    unless $alias;

  ## check list to see if alias is already loaded
  my $pluglist = $core->plugin_list();
  return "Plugin already loaded: $alias"
    if $alias ~~ [ keys %$pluglist ] ;

  my $pluginscf = $core->cfg->{plugins};  # plugins.conf

  if ($module) {
    ## user (or 'reload') specified a module for this alias
    ## it could still have conf opts specified:
    $self->_load_conf($alias, $module, $pluginscf);
    return $self->_load_module($alias, $module);

  } else {

    unless (exists $pluginscf->{$alias}
            && ref $pluginscf->{$alias} eq 'HASH') {
      return rplprintf( $core->lang->{RPL_PLUGIN_ERR},
        {
          plugin => $alias,
          err => "No '${alias}' plugin found in plugins.conf",
        }
      );
    }

    my $pkgname = $pluginscf->{$alias}->{Module};
    unless ($pkgname) {
      return rplprintf( $core->lang->{RPL_PLUGIN_ERR},
        {
          plugin => $alias,
          err => "No Module specified in plugins.conf for plugin '${alias}'",
        }
      );
    }

    ## read conf into core:
    $self->_load_conf($alias, $pkgname, $pluginscf);

    ## load the plugin:
    return $self->_load_module($alias, $pkgname);
  }

}

sub _load_conf {
  my ($self, $alias, $pkgname, $pluginscf) = @_;
  my $core = $self->{core};

  $pluginscf = $self->_read_core_plugins_conf unless $pluginscf;

  ## (re)load this plugin's configuration before loadtime
  my $etcdir = $core->cfg->{path};
  my $cconf = Cobalt::Conf->new(etc => $etcdir);
  ## use our current plugins.conf (not a rehash)
  my $thisplugcf = $cconf->_read_plugin_conf($alias, $pluginscf);
  $thisplugcf = {} unless ref $thisplugcf;
  ## directly fuck with core's cfg hash:
  $core->cfg->{plugin_cf}->{$pkgname} = $thisplugcf;
}


sub Bot_public_cmd_plugin {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${$_[0]};
  my $msg = ${$_[1]};

  my $chan = $msg->{channel};
  my $nick = $msg->{src_nick};
  my $pcfg = $core->get_plugin_cfg( __PACKAGE__ );

  ## default to superuser-only:
  my $required_lev = $pcfg->{PluginOpts}->{LevelRequired} // 9999;

  my $resp;

  my $operation = $msg->{message_array}->[0];

  unless ( $core->auth_level($context, $nick) >= $required_lev ) {
    $resp = rplprintf( $core->lang->{RPL_NO_ACCESS}, { nick => $nick } );
  } else {
    given ( lc($operation || '') ) {
      when ('load') {
        ## syntax: !plugin load <alias>, !plugin load <alias> <module>
        my $alias = $msg->{message_array}->[1];
        my $module = $msg->{message_array}->[2];
        $resp = $self->_load($alias, $module);
      }

      when ('unload') {
        ## syntax: !plugin unload <alias>
        my $alias = $msg->{message_array}->[1];
        $resp = $self->_unload($alias) || "Strange, no reply from _unload?";
      }

      when ('reload') {
        ## syntax: !plugin reload <alias>
        my $alias = $msg->{message_array}->[1];
        my $plug_obj = $core->plugin_get($alias);
        unless ($alias) {
          $resp = "Bad syntax; no plugin alias specified";
        } elsif (! $plug_obj ) {
          $resp = rplprintf( $core->lang->{RPL_PLUGIN_UNLOAD_ERR},
            { 
              plugin => $alias,
              err => 'No such plugin found, is it loaded?' 
            }
          );
         } else {
           ## call _unload and send any response from there
           my $unload_resp = $self->_unload($alias);
           $core->send_event( 'send_message', $context, $chan, $unload_resp );
           ## call _load on our alias and plug_obj, send that in $resp
           my $pkgisa = ref $plug_obj;
           $resp = $self->_load($alias, $pkgisa);
         }
      }

      when ('list') {
        ## don't set a resp, just build and send a list
        my $pluglist = $core->plugin_list();
        push(my @loaded, sort keys %$pluglist);
        my $str = "Plugins:";
        while (my $plugin_alias = shift @loaded) {
          $str .= ' ' . $plugin_alias;
          if ($str && (length($str) > 300 || !@loaded) ) {
            ## either this string has gotten long or we're done
            $core->send_event( 'send_message', $context, $chan, $str );
            $str = '';
          }
        }
      }

      ## shouldfix; reordering via ::Pipeline?

      default { $resp = "Valid PluginMgr commands: list / load / unload / reload" }
    }
  }

  $core->send_event('send_message', $context, $chan, $resp) if $resp;

  return PLUGIN_EAT_ALL
}

1;
