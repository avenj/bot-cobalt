package Cobalt::Lang;
our $VERSION = "0.002";

## Emitted events:
##  langset_loaded ($lang, $lang-specified, $path)

use 5.12.1;
use Moose;
use Carp;
use File::Slurp;
use YAML::Syck;
use namespace::autoclean;

sub langset_load { load_langset(@_) }
sub load_langset {  ## load_langset(language)
  ## read specified language out of etc/langs/
  ## return hash suitable for core->lang
  my ($self) = shift;
  my $lang = shift || croak 'no language specified?';
  ## you can specify a prefix
  ## f.ex: load_langset('english', '/some/dir/langs/plugin-')
  ## results in: $path = "/some/dir/langs/plugin-". lc($lang) .".yml"
  my $prefix = shift || $self->cfg->{path} . "/langs/";

  ## etc/langs/language.yml (lowercase expected)
  my $path = $prefix . lc($lang) . ".yml";

  unless (-f $path) {
    $self->send_event( 'langset_error', "not found: ($lang) $path" )
      if $self->can('send_event');
    $self->log->debug("langset not found: $lang ($path)")
      if $self->can('log');
    return { }
  }

  $self->log->info("Loading language set: $lang");
  my $cf_lang = read_file($path);
  utf8::encode($cf_lang);
  my $langset = Load $cf_lang;

  ## FIXME langset validation ?

  unless (scalar keys %{ $langset }) {
    $self->send_event( 'langset_error', "empty langset? $lang ($path)" )
      if $self->can('send_event');

    $self->log->debug("empty language set? no keys for $lang ($path)")
      if $self->can('log');
    return { }
  }

  $self->send_event( 'langset_loaded', lc($lang), $path )
    if $self->can('send_event');

  return $langset->{RPL}
}


__PACKAGE__->meta->make_immutable;
no Moose; 1;
__END__


=pod

=head1 NAME

Cobalt::Lang -- read cobalt2 langsets

=head1 SYNOPSIS

  ## Load an initial langset out of $etcdir/langs/ :
  $core->lang( $core->load_langset('english') );

=head1 DESCRIPTION

Provides language set loading for the Cobalt core.

Langsets should be in a YAML format readable by L<YAML::Syck>.

B<IMPORTANT>: 
Langset names are automatically lowercased. 
Bear this in mind when naming langsets for plugins. 
They should always be lowercase.

Responses are expected to be found in the YAML langset's 'RPL:' key.
(The corresponding hash is what is actually returned when loading a set.)

Typically the keys of the 'RPL' hash contain values which are strings 
formattable by sprintf.

Inspect C<etc/langs/english.yml> for an example.


=head1 METHODS

=head2 load_langset

Used by the core to load a specified language set.

If passed a single argument, loads the specified .yml file 
out of $etcdir/langs/:

  ## done by cobalt core to (re)load the ->lang hash:
  $core->lang( $core->load_langset('english') );

If passed two arguments, the second argument is considered to be a 
path prefix.

Plugins can use this to read in a langset file, if they like:

  require Cobalt::Lang;
  my $lang = Cobalt::Lang->new;
  my $etc = $core->cfg->{path};  ## location of our etc/
  ## read in etc/langs/plugin/myplugin-english.yml:
  my $prefix = $etc . "/langs/plugin/myplugin-";
  my $rpl_hash = $lang->load_langset('english', $prefix);

It is generally advisable that plugins don't modify the $core->lang 
hash unless they are also part of the core distribution.

That being said, if you do so, you may want to check for rehashes 
(if the core reloads ->lang, your changes will go missing).


=head1 EMITTED EVENTS

=head2 langset_loaded

Syndicated when a language set is loaded.

$$_[0] is the (lowercased) langset name.

$$_[1] is the path to the set that was loaded.

=head2 langset_error

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

L<http://www.cobaltirc.org>


=cut
