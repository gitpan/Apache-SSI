package Apache::SSI;

use strict;
use vars qw($VERSION @ISA);
use HTML::SimpleParse;
use Apache::Constants qw(:common OPT_EXECCGI);
use File::Basename;

$VERSION = '1.91';
@ISA = qw(HTML::SimpleParse);

sub handler {
	my($r) = @_;
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
	Apache::SSI->new( join('', <IN>), $r )->output;
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
		return $self->$method( { $self->parse_args($text)} );
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
	my($self, $args) = @_;
	local $_ = $args->{sub};
	my $arg = $args->{arg};

	my $sub;
	if ( /^\s*sub[^\w:]/ ) {     # for <!--#perl sub="sub {print ++$Access::Cnt }" -->
		$sub = eval();
	} else {             # for <!--#perl sub="package::subr" -->
		$sub = (/::/ ? $_ : "main::$_");
	}
	no strict('refs');
	return scalar &{ $sub }($arg);
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

wherever you choose:

<Files *.phtml>
SetHandler perl-script
PerlHandler Apache::SSI
</Files>

You may wish to subclass Apache::SSI for your own extentions

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

I need to write a few tests that run under "make test".

=head1 BUGS

The only xssi directives currently supported are 'set' and 'echo'.

<!--#perl--> directives can only take one argument.

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
