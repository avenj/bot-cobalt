#!/usr/bin/env perl
use strict;
use warnings;
use Module::Build;

my $class = Module::Build->subclass(
  class => 'Cobalt::Builder',
  code => q{

    sub ACTION_release {
      my $self = shift;
      $self->dispatch('buildinst');
      $self->dispatch('wikidocs');
      ## FIXME target to pod2textify doc/ ?
      ## FIXME dispatch dist ?
    }

    sub ACTION_wikidocs {
      my $self = shift;
      my $base = $self->base_dir;
      my $remote = 'eris.cobaltirc.org';
      chdir($base."/tools/release/docs");
      $self->do_system(qw{"./pod2doku"});
      $self->do_system(
        'rsync',
        '-rv',
        '--stats',
        '--progress',
        'wikidoc/',
        $remote.
         ':public_html/docs/wiki/data/pages/bots/cobalt/docs',
      );
      chdir($base);
    }

    sub ACTION_buildinst {
      my $self = shift;
      $self->do_system(qw{tools/release/create_installer});
    }

  },
);

my $build = $class->new(
  dist_name => 'Cobalt',
  dist_abstract => 'Pluggable IRC bot (cobalt2)',
  dist_author => 'Jon Portnoy <avenj@cobaltirc.org>',
  dist_version_from => 'lib/Cobalt/Core.pm',
  license => 'perl',

  ## A passthru-to-build makefile:
  create_makefile_pl => 'small',

  requires => {
   ### Core set ###
      'perl' => '5.12.1',
      'Carp' => 0,
      'Data::Dumper' => 0,
      'File::Basename' => 0,
      'File::Find' => 0,
      'File::Path' => '2.00',
      'File::Spec' => 0,
      'Getopt::Long' => 0,

   ### Cobalt set ###
     # Crypt
      'Crypt::Eksblowfish' => '0.003',

     # Files
      'File::Slurp' => '9999',

     # Utils
      'DateTime'    => 0,
      'IRC::Utils'  => '0.12',

     # Serialization
      'JSON'        => '2.00',
      'YAML::Syck'  => '1.18',

     # Logging
      'Log::Handler' => '0.71',

     # Moose + related
      'Moose'                => '2.00',
      'MooseX::NonMoose'     => '0.18',
      'namespace::autoclean' => '0.12',

     # POE::
      'POE'            => '1.311',

      # pocoirc6.75 contained bugfix fixing use of LocalAddr
      'POE::Component::IRC'        => '6.75',
      'POE::Component::Syndicator' => '0.06',
      'Object::Pluggable'          => '1.27',

     # Process mgmt
      'Proc::PID::File' => '1.26',
  },

  recommends => {
    ### POE::
      'POE::Component::SSLify' => '1.006',

    ### Utils / misc
      # terminal interaction
      'Term::ReadKey' => 0,
      
      # http
      'HTTP::Request'  => 0,
      'HTTP::Response' => 0,
      'URI::Escape'    => 0,
      'LWP::UserAgent' => 0,

    ### Storage / serialization
      'DB_File'  => 0,
      'YAML::XS' => '0.34',
      'JSON::XS' => 0,

    ### Release tools, commented for now
     # templating (cpodconv/release tools)
#      'Template' => 0,
     # POD conversion
#      'Pod::Find' => 0,
#      'Pod::Simple::Wiki' => 0,
     

  },
);

$build->add_to_cleanup("lib/Cobalt/Lang.pm");
$build->create_build_script;
