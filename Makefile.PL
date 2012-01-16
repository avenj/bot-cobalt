use 5.010001;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME              => 'Cobalt',
    LICENSE           => 'perl',
    VERSION_FROM      => 'lib/Cobalt/Core.pm', # finds $VERSION
    MIN_PERL_VERSION  => '5.12.1',
    PREREQ_PM         => {
      'Crypt::Eksblowfish' => 0,

      'File::Slurp' => 0,

      'IRC::Utils' => 0,

      'JSON'        => 0,

      'Log::Handler' => 0,

      'Moose' => 0,
      'namespace::autoclean' => 0,
      'MooseX::NonMoose' => 0,

      'POE::Component::IRC'        => 0,
      'POE::Component::Syndicator' => 0,

      'Proc::PID::File' => 0,

      'YAML::Syck'  => 0,      
    },

    ($] >= 5.005 ?
      (ABSTRACT       => 'Cobalt2 pluggable IRC bot',
       AUTHOR         => 'Jon Portnoy <irc@cobaltirc.org>') : ()),
);

