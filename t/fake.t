# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $| = 1; print "1..7\n"; }
END {print "not ok 1\n" unless $loaded;}
use Apache::SSI;
$loaded = 1;
print "ok 1\n";

######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):

$TEST_NUM = 2;
sub report_result {
	my $bad = !shift;
	print "not "x$bad, "ok $TEST_NUM\n";
	
	print $_[0] if ($bad and $ENV{TEST_VERBOSE});
	$TEST_NUM++;
}

# 2
&quick_test("<!--#echo var=TERM -->", $ENV{TERM});

# 3
&quick_test('<!--#perl sub="sub {$_[0]*2}" arg=5 pass_request=no -->', 10);

# 4
&quick_test('<!--#perl sub="sub {$_[0]*2+$_[1]}" arg=5 arg=7 pass_request=no-->', 17);

# 5
&quick_test('<!--#perl sub="sub {$_[0]*2+$_[1]}" args=5,7 pass_request=no-->', 17);

# 6
&quick_test('<!--#perl sub="sub {length \"1234\"}"-->', 4);

# 7
&quick_test( qq[<!--#perl\n sub="sub {return 6;\n}"-->], 6);

sub quick_test {
	my $ssi = shift;
	my $expected = shift;
	my $p = new Apache::SSI($ssi);
	&report_result(($p->get_output() eq $expected),
						$p->get_output() . " eq '$expected'");
}
