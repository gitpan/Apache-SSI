package Apache::SSI;

use strict;
use vars qw($VERSION);
use Apache::Constants qw(:common OPT_EXECCGI);
use File::Basename;
use HTML::SimpleParse;
use Symbol;

$VERSION = '1.99';
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
	
	my $fh;
	if ($r->can('filter_input')) {
		my ($status);
		($fh, $status) = $r->filter_input();
		return $status unless $status == OK;
		
	} else {
		my $file = $r->filename;

		unless (-e $r->finfo()) {
			$r->log_error("$file not found");
			return NOT_FOUND;
		}

		$fh = gensym;
		unless (open *{$fh}, $file) {
			$r->log_error("$file: $!");
			return FORBIDDEN;
		}
		$r->send_http_header;
	}
	
	$pack->new( join('', <$fh>), $r )->output;
	return OK;
}

sub new {
	my ($pack, $text, $r) = @_;
	return bless {
		'text' => $text,
		'_r'   => $r,
	}, $pack;
}

sub text {
	my $self = shift;
	if (@_) {
		$self->{'text'} = shift;
	}
	return $self->{'text'};
}

sub get_output($) {
	my $self = shift;
	
	my $out = '';
#	my @parts = split m/(<!--#(?:[^-]|-+[^>-])*-*-->)/s, $self->{'text'};
	my @parts = split m/(<!--#.*?-->)/s, $self->{'text'};
	while (@parts) {
		$out .= shift @parts;
		last unless @parts;
		my $ssi = shift @parts;
		if ($ssi =~ m/^<(!--#.*--)>$/) {
			$out .= $self->output_ssi($1);
		} else { die 'Parse error' }
	}
	return $out;
}


sub output($) {
	my $self = shift;
	
	my @parts = split m/(<!--#.*?-->)/s, $self->{'text'};
	while (@parts) {
		print shift @parts;
		last unless @parts;
		my $ssi = shift @parts;
		if ($ssi =~ m/^<(!--#.*--)>$/) {
			print $self->output_ssi($1);
		} else { die 'Parse error' }
	}
}

sub output_ssi($$) {
	my ($self, $text) = @_;
	
	if ($text =~ s/^!--#(\w+)\s*//) {
		my $method = lc "ssi_$1";
		$text =~ s/--$//;
		warn "returning \$self->$method($text)" if $debug;
		my $args = [ HTML::SimpleParse->parse_args($text) ];
		warn ("args are " . join (',', @{$args})) if $debug;
		return $self->$method( {@$args}, $args );
	}
	return;
}

sub ssi_include($$) {
	my ($self, $args) = @_;
	my $r = $self->{_r};

	my $subr = (length $args->{file} ? 
					$r->lookup_file($args->{file}) : 
					$r->lookup_uri($args->{virtual}) );
	$subr->run == OK or $r->log_error("include failed");
	return;
}

sub ssi_fsize($$) { 
	my ($self, $args) = @_;
	return -s $self->find_file(@{$args}{'file', 'virtual'});  # $ for BBEdit
}

sub ssi_flastmod($$) {
	my($self, $args) = @_;
	my $req;
	if (exists $args->{file}) {
		$req = $self->{_r}->lookup_file( $args->{file} );
	} elsif (exists $args->{virtual}) {
		$req = $self->{_r}->lookup_uri($args->{virtual});
	} else {
		$req = $self->{_r};
	}
	return &_lastmod( $req->filename() );
}

sub ssi_printenv() {
	return join "", map( {"$_: $ENV{$_}<br>\n"} keys %ENV );
}

sub ssi_exec($$) {
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

sub ssi_perl($$$) {
	my($self, $args, $margs) = @_;

	my ($pass_r, @arg1, @arg2, $sub) = (1);
	{
		my @a;
		while (@a = splice(@$margs, 0, 2)) {
			$a[1] =~ s/\\(.)/$1/gs;
			if ($a[0] eq 'sub') {
				$sub = $a[1];
			} elsif ($a[0] eq 'arg') {
				push @arg1, $a[1];
			} elsif ($a[0] eq 'args') {
				push @arg1, split(/,/, $a[1]);
			} elsif (lc $a[0] eq 'pass_request') {
				$pass_r = 0 if lc $a[1] eq 'no';
			} elsif ($a[0] =~ s/^-//) {
				push @arg2, @a;
			} else { Any unknown get passed as key-value pairs
				push @arg2, @a;
			}
		}
	}

	warn "sub is $sub, args are @arg1 & @arg2" if $debug;
	my $subref;
	if ( $sub =~ /^\s*sub[^\w:]/ ) {     # for <!--#perl sub="sub {print ++$Access::Cnt }" -->
		$subref = eval($sub);
		if ($@) {
			$self->{_r}->log_error("Perl eval of '$sub' failed: $@") if $self->{_r};
			warn("Perl eval of '$sub' failed: $@") unless $self->{_r};
		}
		return '[A Perl error occurred while parsing this directive]' unless ref $subref;
	} else {             # for <!--#perl sub="package::subr" -->
		$subref = "main::$_" unless $sub =~ /::/;
	}
	
	$pass_r = 0 if $self->{_r} and lc $self->{_r}->dir_config('SSIPerlPass_Request') eq 'no';
	unshift @arg1, $self->{_r} if $pass_r;
	warn "sub is $subref, args are @arg1 & @arg2" if $debug;
	no strict('refs');
	return scalar &{ $subref }(@arg1, @arg2);
}

sub ssi_set($$) {
	my ($self, $args) = @_;
	
	# Work around a bug in mod_perl 1.12 that happens when calling
	# subprocess_env in a void context
	#my $trash = $self->{_r}->subprocess_env( $args->{var}, $args->{value} );
	$self->{_r}->subprocess_env( $args->{var}, $args->{value} );
	return;
}

sub ssi_config() {
	warn "*** 'config' directive not implemented by Apache::SSI";
	return "<$_[1]>";
}

sub ssi_echo($$) {
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

sub echo_DATE_GMT() { scalar gmtime; }
sub echo_DATE_LOCAL() { scalar localtime; }
sub echo_DOCUMENT_NAME($) {
    my $r = _2main(shift);
    return &_set_VAR($r, 'DOCUMENT_NAME', basename $r->filename);
}
sub echo_DOCUMENT_URI($) {
    my $r = _2main(shift);
    return &_set_VAR($r, 'DOCUMENT_URI', $r->uri);
}
sub echo_LAST_MODIFIED($) {
    my $r = _2main(shift);
    return &_set_VAR($r, 'LAST_MODIFIED', &_lastmod($r->filename));
}

sub _set_VAR($$$) {
    $_[0]->subprocess_env($_[1], $_[2]);
    return $_[2];
}

sub _2main { $_[0]->is_main() ? $_[0] : $_[0]->main() }

sub _lastmod($) { scalar localtime( (stat $_[0])[9] ) }

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
can parse the output of other mod_perl handlers, or send the SSI output
through another handler (use Apache::Filter or Apache::OutputChain to 
do these).

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

If you give a key-value pair and the key is not 'sub', 'arg', 'args', or 
'pass_request' (see below), then your routine will be passed B<both> the 
key and the value.  This lets you pass a hash of key-value pairs to your 
function:

 <!--#perl sub=holy::matrimony groom=Hi bride=Lois-->
 Will call &holy::matrimony('groom', 'Hi', 'bride', 'Lois');

As of version 1.95, we pass the current Apache request object ($r) as the
first argument to the function.  To turn off this behavior, give the key-value
pair 'pass_request=no', or put 'PerlSetVar SSIPerlPass_Request no' in your
server's config file.

See C<http://perl.apache.org/src/mod_perl.html> for more information on Perl
SSI calls.

=item * config

Not supported yet.

=back

=head1 CHAINING HANDLERS

There are two fairly simple ways for this module to exist in a stacked handler
chain.  The first uses C<Apache::Filter>, and your httpd.conf would look something
like this:

 PerlModule Apache::Filter
 PerlModule Apache::SSI
 PerlModule My::BeforeSSI
 PerlModule My::AfterSSI
 <Files ~ "\.ssi$">
  SetHandler perl-script
  PerlHandler My::BeforeSSI Apache::SSI My::AfterSSI
 </Files>

The second uses C<Apache::OutputChain>, and your httpd.conf would look something
like this:

 PerlModule Apache::OutputChain
 PerlModule Apache::SSIChain
 PerlModule My::BeforeSSI
 PerlModule My::AfterSSI
 <Files ~ "\.ssi$">
  SetHandler perl-script
  PerlHandler Apache::OutputChain My::AfterSSI Apache::SSIChain My::BeforeSSI
 </Files>

Note that the order of handlers is reversed in the two different methods.  One 
reason I wrote C<Apache::Filter> is to get the order to be more intuitive.  
Another reason is that C<Apache::SSI> itself can be used in a handler stack using
C<Apache::Filter>, whereas it needs to be wrapped in C<Apache::SSIChain> to 
be used with C<Apache::OutputChain>.

Please see the documentation for C<Apache::OutputChain> and C<Apache::Filter>
for more specific information.
 

=head1 CAVEATS

The date output formats are different from mod_include's format.  Anyone know
a nice way to get the same format without resorting to HTTP::Date?  [update:
Byron Brummer suggests that I check out the POSIX::strftime() function,
included in the standard distribution.]

Currently, the way <!--#echo var=whatever--> looks for variables is
to first try $r->subprocess_env, then try %ENV, then the five extra environment
variables mod_include supplies.  Is this the correct order?

=head1 TO DO

#if .. #else should be possible now, I'll take a stab it implementing it.

Revisit http://www.apache.org/docs/mod/mod_include.html and see what else
there I can implement.

It would be nice to have a "PerlSetVar ASSI_Subrequests 0|1" option that
would let you choose between executing a full-blown subrequest when
including a file, or just opening it and printing it.

I'd like to know how to use Apache::test for the real.t test.

=head1 BUGS

The only xssi directives currently supported are 'set' and 'echo'.


=head1 SEE ALSO

mod_include, mod_perl(3), Apache(3), HTML::Embperl(3), Apache::ePerl(3),
Apache::OutputChain(3)

=head1 AUTHOR

Ken Williams ken@forum.swarthmore.edu

Concept based on original version by Doug MacEachern dougm@osf.org .
Implementation different.

=head1 COPYRIGHT

Copyright 1998 Swarthmore College.  All rights reserved.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.


=cut
