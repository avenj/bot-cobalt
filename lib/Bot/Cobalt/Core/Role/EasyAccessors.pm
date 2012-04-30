package Bot::Cobalt::Core::Role::EasyAccessors;

use strictures 1;
use Moo::Role;

requires qw/
  cfg
  log
  PluginObjects
/;

use Storable qw/dclone/;

use Scalar::Util qw/blessed/;

sub get_plugin_alias {
  my ($self, $plugobj) = @_;
  return unless blessed $plugobj;
  my $alias = $self->PluginObjects->{$plugobj} || undef;
  return $alias
}

sub get_core_cfg {
  my ($self) = @_;
  my $corecfg = dclone( $self->cfg->{core} );
  return $corecfg
}

sub get_channels_cfg {
  my ($self, $context) = @_;
  unless ($context) {
    $self->log->warn(
      "get_channels_cfg called with no context at "
       .join ' ', (caller)[0,2]
    );
    return
  }
  ## Returns empty hash if there's no conf for this channel:
  my $chcfg = dclone( $self->cfg->{channels}->{$context} // {} );
  return $chcfg
}

sub get_plugin_cfg {
  my ($self, $plugin) = @_;
  ## my $plugcf = $core->get_plugin_cfg( $self )
  ## Returns undef if no cfg was found

  my $alias;

  if (blessed $plugin) {
    ## plugin obj (theoretically) specified
    $alias = $self->PluginObjects->{$plugin};
    unless ($alias) {
      $self->log->error("No alias for $plugin");
      return
    }
  } else {
    ## string alias specified
    $alias = $plugin;
  }

  unless ($alias) {
    $self->log->error("get_plugin_cfg: no plugin alias? ".scalar 
caller);
    return
  }

  ## Return empty hash if there is no loaded config for this alias
  my $plugin_cf = $self->cfg->{plugin_cf}->{$alias} // return {};

  unless (ref $plugin_cf eq 'HASH') {
    $self->log->debug("get_plugin_cfg; $alias cfg not a HASH");
    return
  }

  ## return a copy, not a ref to the original.
  ## that way we can worry less about stupid plugins breaking things
  my $cloned = dclone($plugin_cf);
  return $cloned
}


1;
__END__

=pod

FIXME

=cut
