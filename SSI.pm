package Apache::SSI;

use strict;
use vars qw($VERSION @ISA);
use HTML::SimpleParse;
use Apache::Constants qw(:common OPT_EXECCGI);
use File::Basename;

$VERSION = '1.94';
@ISA = qw(HTML::SimpleParse);
my $debug = 0;

sub handler($$) {
	my($pack,$r_orig) = @_;  # Handles subclassing via PerlMethodHandler
	my $r;
	if ($r_orig) {
		$r = $r_orig;
	} else {
		$r = $pack;
		$pack = __PACKAGE__;
	}
	
	%ENV = $r->cgi_env; #for exec
	$r->content_type("text/html");
	my $file = $r->filename;

	unless (-e $file) {
		$r->log_error("$file not found");
		return NOT_FOUND;	
	}

	local *IN;
	unless (open IN, $file) {
		$r->log_error("$file: $!");
		return FORBIDDEN;
	}
	
	$r->send_http_header;
	$pack->new( join('', <IN>), $r )->output;
	return OK;
}

sub new {
	my $self = $_[0]->SUPER::new($_[1]);
	$self->{_r} = $_[2];
	return $self;
}

sub lastmod {
	return scalar localtime( (stat $_[0])[9] );
}


# Method called by HTML::SimpleParse::output, overrides
# HTML::SimpleParse::output_ssi.
sub output_ssi {
	my $self = shift;
	my $text = shift;
	
	if ($text =~ s/^!--#(\w+)\s*//) {
		my $method = lc "ssi_$1";
		$text =~ s/--$//;
		no strict('refs');
		warn "returning \$self->$method(...)" if $debug;
		my $args = [ $self->parse_args($text) ];
		return $self->$method( {@$args}, $args );
	}
	return;
}

sub ssi_include {
	my ($self, $args) = @_;
	my $r = $self->{_r};

	my $subr = (length $args->{file} ? 
					$r->lookup_file($args->{file}) : 
					$r->lookup_uri($args->{virtual}) );
	$subr->run == OK or $r->log_error("include failed");
	return;
}

sub ssi_fsize { 
	my ($self, $args) = @_;
	return -s $self->find_file(@{$args}{'file', 'virtual'});  # $ for BBEdit
}

sub ssi_flastmod {
	my($self, $args) = @_;
	return &lastmod($args->{file} || $self->{_r}->filename);
}

sub ssi_printenv {
	return join "", map( {"$_: $ENV{$_}<br>\n"} keys %ENV );
}

sub ssi_exec {
	my($self, $args) = @_;
	#XXX did we check enough?
	my $r = $self->{_r};
	my $filename = $r->filename;
	unless($r->allow_options & OPT_EXECCGI) {
		$r->log_error("httpd: exec used but not allowed in $filename");
		return "";
	}
	return scalar `$args->{cmd}`;
}

sub ssi_perl {
	my($self, $args, $margs) = @_;
	local $_;
	my (@arg1, @arg2);
	{
		my @a;
		while (@a = splice(@$margs, 0, 2)) {
			if ($a[0] eq 'sub') {
				$_ = $a[1];
			} elsif ($a[0] eq 'arg') {
				push @arg1, $a[1];
			} elsif ($a[0] eq 'args') {
				push @arg1, split(/,/, $a[1]);
			} else {
				push @arg2, @a;
			}
		}
	}

	my $sub;
	if ( /^\s*sub[^\w:]/ ) {     # for <!--#perl sub="sub {print ++$Access::Cnt }" -->
		$sub = eval();
	} else {             # for <!--#perl sub="package::subr" -->
		$sub = (/::/ ? $_ : "main::$_");
	}
	warn "sub is $sub, args are @arg1 & @arg2" if $debug;
	no strict('refs');
	return scalar &{ $sub }(@arg1, @arg2);
}

sub multi_args {
	shift;  # Get rid of $self
	my $arg = shift; # What arg to look for
	my @list = @{shift()};
	my (@returns, @pair);
	while (@pair = splice(@list, 0, 2)) {
		push(@returns, $pair[1]) if $pair[0] eq $arg;
	}
	return @returns;
}

sub ssi_set {
	my ($self, $args) = @_;
	
	# Work around a bug in mod_perl 1.12 that happens when calling
	# subprocess_env in a void context
	my $trash = $self->{_r}->subprocess_env( $args->{var}, $args->{value} );
	return;
}

sub ssi_config {
	warn "*** 'config' directive not implemented by Apache::SSI";
	return "<$_[1]>";
}

sub ssi_echo {
	my($self, $args) = @_;
	my $var = $args->{var};
	my $value;
	no strict('refs');
	
	if (exists $ENV{$var}) {
		return $ENV{$var};
	} elsif ( defined ($value = $self->{_r}->subprocess_env($var)) ) {
		return $value;
	} elsif (defined &{"echo_$var"}) {
		return &{"echo_$var"}($self->{_r});
	}
	return '';
}

sub echo_DATE_GMT { scalar gmtime; }
sub echo_DATE_LOCAL { scalar localtime; }
sub echo_DOCUMENT_NAME { basename $_[0]->filename; }
sub echo_DOCUMENT_URI { $_[0]->uri; }
sub echo_LAST_MODIFIED { &lastmod($_[0]->filename); }

1;

__END__

=head1 NAME

Apache::SSI - Implement Server Side Includes in Perl

=head1 SYNOPSIS

In httpd.conf:

    <Files *.phtml>  # or whatever
    SetHandler perl-script
    PerlHandler Apache::SSI
    </Files>

You may wish to subclass Apache::SSI for your own extensions.  If so,
compile mod_perl with PERL_METHOD_HANDLERS=1 (so you can use object-oriented
inheritance), and create a module like this:

    package MySSI;
    use Apache::SSI ();
    @ISA = qw(Apache::SSI);

    #embedded syntax:
    #<!--#something param=value -->
    sub ssi_something {
       my($self, $attr) = @_;
       my $cmd = $attr->{param};
       ...
       return $a_string;   
    }
 
 Then in httpd.conf:
 
    <Files *.phtml>
     SetHandler perl-script
     PerlHandler MySSI
    </Files>

=head1 DESCRIPTION

Apache::SSI implements the functionality of mod_include for handling
server-parsed html documents.  It runs under Apache's mod_perl.

In my mind, there are two main reasons you might want to use this module:
you can sub-class it to implement your own custom SSI directives, and/or you
can use an OutputChain to get the SSI output first, then send it through
another PerlHandler.

Each SSI directive is handled by an Apache::SSI method with the prefix
"ssi_".  For example, <!--#printenv--> is handled by the ssi_printenv method.
attribute=value pairs inside the SSI tags are parsed and passed to the
method in an anonymous hash.

=head2 SSI Directives

This module supports the same directives as mod_include.  At least, that's
the goal. =)  For methods listed below but not documented, please see
mod_include's online documentation at http://www.apache.org/ .

=over 4

=item * echo

=item * exec

=item * fsize

=item * flastmod

=item * include

=item * printenv

=item * set

=item * perl

There are two ways to call a Perl function, and two ways to supply it with
arguments.  The function can be specified either as an anonymous subroutine
reference, or as the name of a function defined elsewhere:

 <!--#perl sub="sub { localtime() }"-->
 <!--#perl sub="time::now"-->

If the 'sub' argument matches the regular expression /^\s*sub[^\w:]/, it is
assumed to be a subroutine reference.  Otherwise it's assumed to be the name
of a function.  In the latter case, the string "::" will be prepended to the
function name if the name doesn't contain "::" (this forces the function to
be in the main package, or a package you specify).

If you want to supply a list of arguments to the function, you use either
the "arg" or the "args" parameter:

 <!--#perl sub="sub {$_[0] * 7}" arg=7-->
 <!--#perl sub=holy::matrimony arg=Hi arg=Lois-->
 <!--#perl sub=holy::matrimony args=Hi,Lois-->

The "args" parameter will simply split on commas, meaning that currently
there's no way to embed a comma in arguments passed via the "args"
parameter.  Use the "arg" parameter for this.

See C<http://perl.apache.org/src/mod_perl.html> for more details on this.

=item * config

Not supported yet.

=back

=head1 CAVEATS

I haven't tried using Apache::OutputChain myself, so if this module doesn't
work with OutputChain, please let me know and I'll try to fix it (do modules
have to be "OutputChain-friendly?").

The date output formats are different from mod_include's format.  Anyone know
a nice way to get the same format without resorting to HTTP::Date?  [update:
Byron Brummer suggests that I check out the POSIX::strftime() function,
included in the standard distribution.]

Currently, the way <!--#echo var=whatever--> looks for variables is
to first try $r->subprocess_env, then try %ENV, then the five extra environment
variables mod_include supplies.  Is this the correct order?

=head1 TO DO

It would be nice to have a "PerlSetVar ASSI_Subrequests 0|1" option that
would let you choose between executing a full-blown subrequest when
including a file, or just opening it and printing it.

It would also be nice to mix & match the "arg" and "args" parameters to
<!--#perl--> sections, like so:

 <!--#perl sub=something arg="Hi, Ken" args=5,12,13 arg="Bye, Ken"-->

I'd like to know how to use Apache::test for the real.t test.

=head1 BUGS

The only xssi directives currently supported are 'set' and 'echo'.


=head1 SEE ALSO

mod_include, mod_perl(3), Apache(3), HTML::Embperl(3), Apache::ePerl(3),
Apache::OutputChain(3)

=head1 AUTHOR

Ken Williams ken@forum.swarthmore.edu

Based on original version by Doug MacEachern dougm@osf.org

=head1 COPYRIGHT

Copyright 1998 Swarthmore College.  All rights reserved.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.


=cut
