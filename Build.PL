#!/usr/bin/env perl

use Module::Build;

my $build = Module::Build->new(
  module_name => 'Cobalt',
  author => 'Jon Portnoy <avenj@cobaltirc.org>',
  license => 'perl',

  ## A passthru-to-build makefile:
  create_makefile_pl => 'small',

  requires => {
   ### Core set ###
      'perl' => '5.12.1',
      'Carp' => 0,
      'File::Find' => 0,
      'File::Spec' => 0,
      'File::Basename' => 0,
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
     # Object fuckery
      'Object::Pluggable' => 0,

     # POE::
      'POE' => '1.311',
      'POE::Session' => 0,
      # pocoirc6.75 contained bugfix fixing use of LocalAddr
      'POE::Component::IRC'        => '6.75',
      'POE::Component::Syndicator' => 0,

     # Process mgmt
      'Proc::PID::File' => 0,
  },

  recommends => {
    ### DBs
      'DBM::Deep' => '2.00',

    ### POE::
      'POE::Component::SSLify' => 0,

    ### Utils / misc
      # templating
      'Template' => 0,
      # terminal interaction
      'Term::ReadKey' => 0,
  },
);


$build->create_build_script;
