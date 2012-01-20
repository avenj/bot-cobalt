package Cobalt::Plugin::PluginMgr;
our $VERSION = '0.10';

## handles and eats: !plugin

use 5.12.1;
use strict;
use warnings;

use Object::Pluggable::Constants qw/ :ALL /;

use Cobalt::Utils qw/ rplprintf /;

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

  unless ($alias) {
    $resp = "Bad syntax; no plugin alias specified";
  } elsif (! $core->plugin_get($alias) ) {
    $resp = rplprintf( $core->lang->{RPL_PLUGIN_UNLOAD_ERR},
            { 
              plugin => $alias,
              err => 'No such plugin found, is it loaded?' 
            }
    );
  } else {
    $core->log->info('Attempting to unload $alias per request');
    $resp = $core->plugin_del($alias) ?
                  rplprintf( $core->lang->{RPL_PLUGIN_UNLOAD}, 
                             { plugin => $alias } )
                  :
                  rplprintf( $core->lang->{RPL_PLUGIN_UNLOAD_ERR},
                             { plugin => $alias, err => 'Unknown failure' ) ;
  }

  return $resp
}


sub Bot_public_cmd_plugin {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${$_[0]};
  my $msg = ${$_[1]};

  my $chan = $msg->{channel};
  my $nick = $msg->{src_nick};
  my $cfg = $core->get_plugin_cfg( __PACKAGE__ );

  ## default to superuser-only:
  my $required_lev = $cfg->{PluginOpts}->{LevelRequired} // 9999;

  my $resp;

  my $operation = $msg->{message_array}->[0];

  unless ( $core->auth_level($context, $nick) > $required_lev ) {
    $resp = rplprintf( $core->lang->{RPL_NO_ACCESS}, { nick => $nick } );
  } else {
    given (lc $operation) {
      when ('load') {
        ## syntax: !plugin load <alias>, !plugin load <alias> <module>
        ## if found in plugins conf, load plugin + opts + rehash cfg
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
           ## call _load on our alias and plug_obj
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
