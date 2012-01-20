package Cobalt::Plugin::PluginMgr;
our $VERSION = '0.10';

## handles and eats: !plugin

use 5.12.1;
use strict;
use warnings;

use Object::Pluggable::Constants qw/ :ALL /;

use Cobalt::Utils qw/ rplprintf /;

BEGIN { $^P |= 0x10; }

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
  my $plugisa = ref $plug_obj;

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
    $core->log->info('Attempting to unload $alias per request');
    if ( $core->plugin_del($alias) ) {
      my $module = $plugisa;
      $module .= '.pm' if $module !~ /\.pm$/;
      $module =~ s/::/\//g;
      delete $INC{$module};
      undef $plug_obj;
      ## shamelessly 'adapted' from PocoIRC's Plugin::PlugMan
      ## clean up symbol table
      for my $sym (grep { index($_, "$plugisa:") == 0 } keys %DB::sub) {
        eval { undef &$sym };
        $core->log->warn("cleanup: $sym: $@") if $@;
        delete $DB::sub{$sym};
      }
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
    ## 'require' failed, probably because we can't find it
    return rplprintf( $core->lang->{RPL_PLUGIN_ERR},
        {
          plugin => $alias,
          err => "Module $module cannot be found/loaded",
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
  my ($self, $alias, $module) = @_;
  my $core = $self->{core};

  return "Bad syntax; usage: load <alias> [module]"
    unless $alias;

  if ($module) {
    ## user specified a module for this alias
    ## (should only be used for plugins without a conf)
    return $self->_load_module($alias, $module);
  } else {
    my $cfg = $core->get_core_cfg;
    my $pluginscf = $cfg->{plugins};  # plugins.conf

    unless (exists $pluginscf->{$alias}
            && ref $pluginscf->{$alias} eq 'HASH') {
      return rplprintf( $core->lang->{RPL_PLUGIN_ERR},
        {
          plugin => $alias,
          err => "No '$alias' plugin found in plugins.conf",
        }
      );
    }

    unless ($pluginscf->{$alias}->{Module}) {
      return rplprintf( $core->lang->{RPL_PLUGIN_ERR},
        {
          plugin => $alias,
          err => "No Module specified in plugins.conf for plugin '$alias'",
        }
      );
    }

    my $module = $pluginscf->{$alias}->{Module};
    # $self->_load_module($alias, $module);
    ## FIXME
    ## if found in plugins conf, load plugin + opts + load/rehash cfg
  }

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
    given (lc $operation) {
      when ('load') {
        ## syntax: !plugin load <alias>, !plugin load <alias> <module>
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
        my @loaded;  ## array of arrays, 'Alias', 'Version'
        my $pluglist = $core->plugin_list;
        for my $plugin_alias ( %$pluglist ) {
          my $plug_obj = $pluglist->{$plugin_alias};
          my $plug_vers = $plug_obj->VERSION // '0' ;
          push(@loaded, [ $plugin_alias, $plug_vers ] );
        }

        my $str = "Plugins:";
        while (@loaded) {
          my $plugin_info = shift @loaded;
          ## Alias-Version:
          $str .= ' ' . $plugin_info->[0] .'-'. $plugin_info->[1];
          if ($str && (length($str) > 300 || !@loaded) ) {
            ## either this string has gotten long or we're done
            $core->send_event( 'send_message', $context, $chan, $str );
            $str = '';
          }
        }
      }

      ## FIXME reordering via ::Pipeline?

      default { $resp = "Valid PluginMgr commands: list / load / unload / reload" }
    }
  }

  $core->send_event('send_message', $context, $chan, $resp) if $resp;

  return PLUGIN_EAT_ALL
}

1;
