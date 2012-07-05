package Bot::Cobalt::Core::Loader;
our $VERSION = '0.012';

use 5.12.1;
use strict;
use warnings FATAL => 'all';

use Carp;

use Scalar::Util qw/blessed/;

use Try::Tiny;

sub new { bless [], shift }

sub is_reloadable {
  my ($class, $obj) = @_;
  
  confess "is_reloadable() needs a plugin object"
    unless $obj and blessed $obj;
  
  return if $obj->can('NON_RELOADABLE') and $obj->NON_RELOADABLE;

  return 1
}

sub module_path {
  my ($class, $module) = @_;
  
  confess "module_path() needs a module name" unless defined $module;
  
  return join('/', split /::/, $module).".pm";
}

sub load {
  my ($class, $module, @newargs) = @_;
  
  confess "load() needs a module name" unless defined $module;

  my $modpath = $class->module_path($module);

  my $orig_err;
  unless (try { require $modpath;1 } catch { $orig_err = $_;0 }) {
    ## die informatively
    croak "Could not load $module: $orig_err"
  }

  my $obj;
  try {
    $obj = $module->new(@newargs)
  } catch {
    croak "new() failed for $module: $_"
  };
  
  $obj if blessed $obj
}

sub unload {
  my ($class, $module) = @_;
  
  confess "unload() needs a module name" unless defined $module;
  
  my $modpath = $class->module_path($module);
  
  delete $INC{$modpath};
  
  {
    no strict 'refs';
    @{$module.'::ISA'} = ();
    
    my $s_table = $module.'::';
    for my $symbol (keys %$s_table) {
      next if $symbol =~ /^[^:]+::$/;
      delete $s_table->{$symbol}
    }
  }
  
  ## Pretty much always returns success, on the theory that
  ## we did all we could from here.
  return 1
}

1;
__END__

=pod

=head1 NAME

Bot::Cobalt::Core::Loader - Object loader/unloader

=head1 SYNOPSIS

  use Try::Tiny;
  require Bot::Cobalt::Core::Loader;
  
  ## Attempt to import a module:
  my $plugin_obj = try {
    Bot::Cobalt::Core::Loader->load($module_name, @args)
  } catch {
    # . . . load failed, maybe die with an error . . .
  };

  ## Check reloadable status of a plugin object:
  if ( Bot::Cobalt::Core::Loader->is_reloadable($plugin_obj) ) {
   . . .
  }
  
  ## Clean up a module after dropping a plugin object:
  Bot::Cobalt::Core::Loader->unload($module_name);

=head1 DESCRIPTION

A small load/unload class for managing L<Bot::Cobalt> plugins.

=head2 load

Given a module name in the form of 'My::Module', tries to load and 
instantiate the specified module view C<new()>.

Optional arguments can be specified to be passed to C<new()>:

  $obj = Bot::Cobalt::Core::Loader->load($module_name, @args)

Throws an exception on error.

=head2 unload

Given a module name in the form of 'My::Module', tries to delete the 
module from %INC and clear relevant symbol table entries.

Always returns boolean true.

=head2 is_reloadable

Given a blessed object, checks to see if the plugin declares itself as 
NON_RELOADABLE. Returns boolean true if the object appears to be 
declared reloadable.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
