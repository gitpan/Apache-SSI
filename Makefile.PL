use ExtUtils::MakeMaker;
use lib 't/lib';
use Apache::test;

my %params = Apache::test->get_test_params();
chomp (my $cwd = `pwd`);
Apache::test->write_httpd_conf
    (%params, 
     include => join '', <DATA>);
*MY::test = sub { Apache::test->MM_test(%params) };


my $module = 'Apache::SSI';
my ($name, $dir);
($name = $module) =~ s/.*::(\w+)/$1.pm/;
($dir  = $module) =~ s/::/-/g;

WriteMakefile
  (
   'NAME'       => $module,
   'VERSION_FROM' => $name, # finds $VERSION
   'dist' => { COMPRESS=>"gzip",
               SUFFIX=>"gz",
               PREOP=>('rm -f README; '.
                       "pod2text -80 < $name > README; ".
                       "cp -f README $dir-\$(VERSION); "
                      ),
             },
   'clean' => {FILES => "t/httpd.conf t/error_log t/httpd"},
   'PREREQ_PM' => {
		   'Apache::Constants' => '1.00',
		   'HTML::SimpleParse' => '0.06',
		  }
  );


__DATA__
AddType text/html .html

PerlModule Apache::SSI
PerlModule Apache::FakeSSI
PerlModule Apache::Kid
PerlModule Apache::Status

<Files ~ "\.ssi$">
 SetHandler perl-script
 PerlHandler Apache::SSI
</Files>

<Files ~ "\.ssif$">
 SetHandler perl-script
 PerlHandler Apache::FakeSSI
</Files>

<Files ~ "\.ssik$">
 SetHandler perl-script
 PerlHandler Apache::Kid
</Files>

<Location /perl-status>
 SetHandler perl-script
 PerlHandler Apache::Status
</Location>
