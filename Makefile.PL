use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

unless ($ENV{APACHE}) {
  $ENV{APACHE} = "/usr/lib/httpd/httpd";
  local $|=1;
  print " Where is apache executable (for testing puposes only)?\n",
	" Hit enter to accept default, or type NONE to skip live-testing.\n",
	" APACHE=[$ENV{APACHE}] ";
  chomp (my $in = <STDIN>);
  $ENV{APACHE}=$in if $in;
}
print "APACHE=$ENV{APACHE}\n";


WriteMakefile(
    'NAME'	=> 'Apache::SSI',
    'VERSION_FROM' => 'SSI.pm', # finds $VERSION
    'dist' => { COMPRESS=>"gzip", SUFFIX=>"gz" },
    'PREREQ_PM' => {
        'Apache::Constants' => '1.00',
        'HTML::SimpleParse' => '0.06',
    }

);
