#!/usr/local/bin/perl

# This test will start up a real httpd server with Apache::SSI loaded in
# it, and make several requests on that server.

# Change this to the path to a mod_perl-enabled Apache web server.
my $HTTPD = "/home/ken/http/httpd";
#my $HTTPD = "/path/to/httpd";

my $PORT = 8228;     # The port the server will run on
my $USER = 'http';   # The user the server will run as
my $GROUP = 'http';  # The group the server will run as

# You shouldn't have to change any of these, but you can if you want:
$ACONF = "/dev/null";
$CONF = "t/httpd.conf";
$SRM = "/dev/null";
$LOCK = "t/httpd.lock";
$PID = "t/httpd.pid";
$ELOG = "t/error_log";

######################################################################
################ Don't change anything below here ####################
######################################################################

#line 25 real.t

use vars qw(
     $ACONF   $CONF   $SRM   $LOCK   $PID   $ELOG
   $D_ACONF $D_CONF $D_SRM $D_LOCK $D_PID $D_ELOG
);
my $DIR = `pwd`;
chomp $DIR;
&dirify(qw(ACONF CONF SRM LOCK PID ELOG));


use strict;
use vars qw($TEST_NUM $BAD);
use LWP::UserAgent;
use Carp;

my %requests = (
	3  => 'bare.ssi',
	4  => 'file.ssi',
	5  => 'kid.ssik',
	6  => 'virtual.ssi',
	7  => 'incl_rel.ssi',
	8  => 'incl_rel2.ssi',
	9  => 'set_var.ssi',
);


print "1.." . (2 + keys %requests) . "\n";

&report( &create_conf() );
my $result = &start_httpd;
&report( $result );

if ($result) {
	local $SIG{'__DIE__'} = \&kill_httpd;
	
	foreach my $testnum (sort {$a<=>$b} keys %requests) {
		my $ua = new LWP::UserAgent;
		my $req = new HTTP::Request('GET', "http://localhost:$PORT/t/docs/$requests{$testnum}");
		my $response = $ua->request($req);
	
		&test_outcome($response->content, $testnum);
	}

	&kill_httpd();
	warn "\nSee $ELOG for failure details\n" if $BAD;
} else {
	warn "Aborting real.t";
}

&cleanup();

#############################

sub start_httpd {
	print STDERR "Starting http server... ";
	unless (-x $HTTPD) {
		warn("$HTTPD doesn't exist or isn't executable.  Edit real.t if you want to test with a real apache server.\n");
		return;
	}
	&do_system("cp /dev/null $ELOG");
	&do_system("$HTTPD -f $D_CONF") == 0
		or die "Can't start httpd: $!";
	print STDERR "ready. ";
	return 1;
}

sub kill_httpd {
	&do_system("kill -TERM `cat $PID`");
	&do_eval("unlink '$ELOG'") unless $BAD;
	return 1;
}

sub cleanup {
	&do_eval("unlink '$CONF'");
	return 1;
}

sub test_outcome {
	my $text = shift;
	my $i = shift;
	
	my $ok = ($text eq `cat t/docs.check/$i`);
	&report($ok);
	print "Result: $text" if ($ENV{TEST_VERBOSE} and not $ok);
}

sub report {
	my $ok = shift;
	$TEST_NUM++;
	print "not "x(!$ok), "ok $TEST_NUM\n";
	$BAD++ unless $ok;
}

sub do_system {
	my $cmd = shift;
	print "$cmd\n";
	return system $cmd;
}

sub do_eval {
	my $code = shift;
	print "$code\n";
	my $result = eval $code;
	if ($@ or !$result) { carp "WARNING: $@" }
	return $result;
}

sub dirify {
	no strict('refs');
	foreach (@_) {
		# Turn $VAR into $D_VAR, which has an absolute path
		${"D_$_"} = (${$_} =~ m,^/, ? ${$_} : "$DIR/${$_}");
	}
}

sub create_conf {
	my $file = $CONF;
	open (CONF, ">$file") or die "Can't create $file: $!" && return;
	print CONF <<EOF;

#This file is created by the $0 script.

Port $PORT
User $USER
Group $GROUP
ServerName localhost
DocumentRoot $DIR

ErrorLog $D_ELOG
PidFile $D_PID
AccessConfig $D_ACONF
ResourceConfig $D_SRM
LockFile $D_LOCK
TypesConfig /dev/null
TransferLog /dev/null
ScoreBoardFile /dev/null

AddType text/html .html

# Look in ./blib/lib
PerlModule ExtUtils::testlib
PerlModule Apache::SSI
PerlRequire $DIR/t/Kid.pm
PerlModule Apache::Status

<Files ~ "\\.ssi\$">
 SetHandler perl-script
 PerlHandler Apache::SSI
</Files>

<Files ~ "\\.ssik\$">
 SetHandler perl-script
 PerlHandler Apache::Kid
</Files>


<Location /perl-status>
 SetHandler perl-script
 PerlHandler Apache::Status
</Location>

EOF
	
	close CONF;
	
	chmod 0644, $file or warn "Couldn't 'chmod 0644 $file': $!";
	return 1;
}
