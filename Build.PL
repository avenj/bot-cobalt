#!/usr/bin/env perl

use Module::Build;

my $build = Module::Build->new(
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
      'File::Path' => 0,
      'File::Spec' => 0,
      'Getopt::Long' => 0,

   ### Cobalt set ###
     # Crypt
      'Crypt::Eksblowfish' => 0,
     # Files
      'File::Slurp' => 0,
     # Utils
      'IRC::Utils' => '0.12',
     # Serialization
      'JSON'        => 0,
      'YAML::Syck'  => 0,
     # Logging
      'Log::Handler' => 0,
     # Moose + related
      'Moose' => 0,
      'MooseX::NonMoose' => 0,
      'namespace::autoclean' => 0,
     # POE::
      'POE' => '1.311',
      'POE::Session' => 0,
      # pocoirc6.75 contained bugfix fixing use of LocalAddr
      'POE::Component::IRC'        => '6.75',
      'POE::Component::Syndicator' => 0,
      'Object::Pluggable::Constants' => 0,
     # Process mgmt
      'Proc::PID::File' => 0,
  },

  recommends => {
    ### DBs
      'DBM::Deep' => '2.00',
    ### POE::
      'POE::Component::SSLify' => 0,
    ### Utils / misc
     # templating (cpodconv/release tools)
      'Template' => 0,
      # terminal interaction
      'Term::ReadKey' => 0,
  },
);


$build->create_build_script;
