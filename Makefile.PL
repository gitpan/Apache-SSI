use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'	=> 'Apache::SSI',
    'VERSION_FROM' => 'SSI.pm', # finds $VERSION
    'dist' => { COMPRESS=>"gzip", SUFFIX=>"gz" },
    'PREREQ_PM' => {
       'HTML::SimpleParse' => '0.01',
    }

);
