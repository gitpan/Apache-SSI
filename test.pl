# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $| = 1; print "1..2\n"; }
END {print "not ok 1\n" unless $loaded;}
use Apache::SSI;
$loaded = 1;
print "ok 1\n";

######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):

sub report_result {
	$TEST_NUM ||= 2;
	print "not " unless $_[0];
	print "ok $TEST_NUM\n";
	
	print $_[1] if (not $_[0] and $ENV{TEST_VERBOSE});
	$TEST_NUM++;
}

# 2
{
	my $p = new Apache::SSI( "<!--#echo var=TERM -->" );
	&report_result(($p->get_output() eq $ENV{TERM}),
	               $p->get_output() . " eq $ENV{TERM}");

}
