package Bot::Cobalt::Core::Role::Unloader;
our $VERSION = '0.001';

use 5.10.1;
use strict;
use warnings;

use Moo::Role;

use Scalar::Util qw/blessed/;

requires qw/
  log
  debug
  send_event
  State
/;


sub is_reloadable {
  my ($self, $alias, $obj) = @_;

  if ($obj and ref $obj) {
    ## passed an object
    ## see if the object is marked non-reloadable
    ## if it is, update State
    if ( $obj->{NON_RELOADABLE} ||
       ( $obj->can("NON_RELOADABLE") && $obj->NON_RELOADABLE() )
    ) {
      $self->log->debug("Marked plugin $alias non-reloadable");
      $self->State->{NonReloadable}->{$alias} = 1;
      ## not reloadable, return 0
      return 0
    } else {
      ## reloadable, return 1
      delete $self->State->{NonReloadable}->{$alias};
      return 1
    }
  }
  ## passed just an alias (or a bustedass object)
  ## return whether the alias is reloadable
  return 0 if $self->State->{NonReloadable}->{$alias};
  return 1
}

sub unloader_cleanup {
  ## clean up symbol table after a module load fails miserably
  ## (or when unloading)
  my ($self, $module) = @_;

  $self->log->debug("cleaning up after $module (unloader_cleanup)");

  my $included = join( '/', split /(?:'|::)/, $module ) . '.pm';

  $self->log->debug("removing from INC: $included");
  delete $INC{$included};

  { no strict 'refs';

    @{$module.'::ISA'} = ();
    my $s_table = $module.'::';
    for my $symbol (keys %$s_table) {
      next if $symbol =~ /\A[^:]+::\z/;
      delete $s_table->{$symbol};
    }

  }

  $self->log->debug("finished module cleanup");
  return 1
}


1;
__END__

=pod

=head1 NAME

Bot::Cobalt::Core::Role::Unloader - Plugin unload role for Bot::Cobalt

=head1 SYNOPSIS

  ## Check NON_RELOADABLE State of a plugin
  $core->is_reloadable($alias);

  ## Update NON_RELOADABLE State of a plugin
  ## (usually at load-time, via a plugin manager)
  $core->is_reloadable($alias, $obj)

  ## Clean a package from the symbol table
  $core->unloader_cleanup($package);

=head1 DESCRIPTION

This is a L<Moo::Role> consumed by L<Bot::Cobalt::Core>.

These methods are used by plugin managers such as 
L<Bot::Cobalt::Plugin::PluginMgr> to handle plugin reloads.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

L<http://www.cobaltirc.org>

=cut
