use 5.006;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Hash::Server',
    VERSION_FROM      => 'lib/Hash/Server.pm', # finds $VERSION
    PREREQ_PM         => {
			'Net::Daemon' => 0.39,
			'Cache::Memcached' => 1.0,
			'Socket' => 1.0,
		},
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/Hash/Server.pm', # retrieve abstract from module
       AUTHOR         => 'Daniel Rench <citric@cubicone.tmetic.com>') : ()),
);
