use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

my $default = $ENV{'APACHE'} || '/usr/lib/httpd/httpd';
$|=1;
print("\nFor testing purposes, please give the full path to an httpd with mod_perl.\n",
      "The path defaults to \$ENV{APACHE}, if present.\n",
     );

my %conf;

do {
  print "\n [$default]: ";
  chomp ($conf{httpd} = <STDIN>);
  $conf{httpd} ||= $default;
} until -e $conf{httpd} || !print("$conf{httpd} not found\n");

$default = getpwuid($<) || "nobody";
print "User to run tests under [$default]: ";
chomp ($conf{user} = <STDIN>);
$conf{user} ||= $default;

$default = getgrgid((getpwnam($conf{user}))[3]) || "nobody";
print "Group to run tests under [$default]: ";
chomp ($conf{group} = <STDIN>);
$conf{group} ||= $default;

$default = 8228;
print "Port to run tests under [$default]: ";
chomp ($conf{port} = <STDIN>);
$conf{port} ||= $default;


open LOC, ">t/httpd.loc" or die "can't write t/httpd.loc: $!";
print LOC map {"$_=$conf{$_}\n"} keys %conf;
close LOC;

WriteMakefile(
    'NAME'	=> 'Apache::SSI',
    'VERSION_FROM' => 'SSI.pm', # finds $VERSION
    'dist' => { COMPRESS=>"gzip", SUFFIX=>"gz" },
    'PREREQ_PM' => {
        'Apache::Constants' => '1.00',
        'HTML::SimpleParse' => '0.06',
    }

);
