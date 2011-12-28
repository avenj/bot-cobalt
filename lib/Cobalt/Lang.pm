package Cobalt::Lang;

## Emitted events:
##  langset_loaded ($lang, $lang-specified, $path)

use 5.12.1;
use Moose;
use Carp;
use File::Slurp;
use YAML::Syck;
use namespace::autoclean;


sub load_langset {  ## load_langset(language)
  ## read specified language out of etc/langs/
  ## return hash suitable for core->lang
  my ($self) = shift;
  my $lang = shift || croak 'no language specified?';

  ## etc/langs/language.yml (lowercase expected)
  my $path = $self->cfg->{path} . "/langs/" . lc($lang) . ".yml";

  return unless -f $path;
  my $cf_lang = read_file($path);
  utf8::encode($cf_lang);
  my $langset = Load $cf_lang;

  ## FIXME langset validation

  $self->send_event( 'langset_loaded', lc($lang), $lang, $path );

  return $langset->{RPL}
}

__PACKAGE__->meta->make_immutable;
no Moose; 1;
