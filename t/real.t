#!/usr/bin/perl

# This test will start up a real httpd server with Apache::SSI loaded in
# it, and make several requests on that server.

use strict;
use lib 'lib', 't/lib';
use Apache::test qw(test);

my %requests = (
	3  => '/docs/bare.ssi',
	4  => '/docs/file.ssi',
	5  => '/docs/kid.ssik',
	6  => '/docs/virtual.ssi',
	7  => '/docs/incl_rel.ssi',
	8  => '/docs/incl_rel2.ssi',
	9  => '/docs/set_var.ssi',
	10 => '/docs/xssi.ssi',
	11 => '/docs/include_cgi.ssi/path?query',
	12 => '/docs/if.ssi',
	13 => '/docs/if2.ssi',
	14 => '/docs/escape.ssi',
	15 => '/docs/exec_cmd.ssi',
	16 => '/docs/kid2.ssik',
	17 => '/docs/flastmod.ssi',
	18 => '/docs/virtual.ssif',
);
my %special_tests = (
	17 => sub {my $year = (localtime)[5]+1900; shift->content =~ /Year: $year/},
);

use vars qw($TEST_NUM);
print "1.." . (2 + keys %requests) . "\n";

test ++$TEST_NUM, 1;
test ++$TEST_NUM, 1;  # For backward numerical compatibility

foreach my $testnum (sort {$a<=>$b} keys %requests) {
  &test_outcome(Apache::test->fetch($requests{$testnum}), $testnum);
}

sub test_outcome {
  my ($response, $i) = @_;
  my $content = $response->content;
  #warn "($content, $response, $i)\n";
  
  my $expected;
  my $ok = ($special_tests{$i} ?
            $special_tests{$i}->($response) :
            ($content eq ($expected = `cat t/docs.check/$i`)) );
  Apache::test->test(++$TEST_NUM, $ok);
  my $headers = $response->headers_as_string();
  print "$i Result:\n$content\n$i Expected: $expected\n" if ($ENV{TEST_VERBOSE} and not $ok);
}

