package Cpanel::HelpfulScript;

# cpanel - Cpanel/HelpfulScript.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::HelpfulScript - boilerplate for built-in help in scripts

=head1 SYNOPSIS

    package scripts::my_cool_script;

    =encoding utf-8

    =head1 NAME

    ... This POD will print when the “--help” parameter is passed,
    in the same manner as how Pod::Usage does it.

    =cut

    use parent qw( Cpanel::HelpfulScript );

    #NB: Specify array and hash values using '=s@' and '=s%', #respectively.
    use constant _OPTIONS => ( 'opt1', 'opt2=s' );

    __PACKAGE__->new(@ARGV)->run() if !caller;

    sub run {
        my ($self) = @_;

        my $opt2 = $self->getopt('opt2');

        #...

        die $self->help();  #e.g., if the args are bad
    }

This base class simplifies the work of making scripts give out helper text.
This is implemented using C<Pod::Usage>.

Modulino scripts that subclass this class will behave as follows:

=over 4

=item * If C<--help> is passed (or any parameter that C<Getopt::Long>
recognizes as its alias), the program prints the help text and exits in success.

=item * If extra parameters are passed, by default the program prints an error
message about the extra parameters, prints the help text, and exits in failure.
(See below for how to change this behavior.)

=item * The instance object has a C<getopt()> method that accesses the
parameters as C<Getopt::Long> collected them from the command line.

=back

If standard output is a terminal, the help text will be formatted using
ANSI escape sequences.

=head1 COMPILED SCRIPTS

Compilation via C<perlcc> clobbers any inline POD, so part of the build process
now includes extracing the POD from any listed scripts and saving them in a
location that this base class knows to check when we’re running compiled.

B<To have a compiled script work with this base class,>
B<you must add the script to the relevant target in the base Makefile.>

=head1 ARBITRARY (EXTRA) PARAMETERS

As stated above, we normally consider extra arguments to be invalid input.
This is because, for clarity, we normally want all arguments to be named.
(If you need a single named option to accept arbitrarily many values,
L<Getopt::Long> gives you the C<{,}> syntax.)

However, if you really want to accept arbitrary inputs--e.g., if your
script’s purpose in life is to accept a single list of things, and to name
that list would just clutter things--you can define this constant:

    use constant _ACCEPT_UNNAMED => 1;

… and the C<getopt_unnamed()> method will return these values as a list.
Note that this method will C<die()> if C<_ACCEPT_UNNAMED()> does not return
a truthy value.

=head1 METHODS: ARGUMENTS AND USAGE

You’ll probably want at least one of these in every script.

=cut

use cPstrict;

use Try::Tiny;

use Getopt::Long ();

use Cpanel::Binary    ();
use Cpanel::Context   ();
use Cpanel::Exception ();

#overridden in tests
use constant BINPOD_DIR => '/usr/local/cpanel/etc/binpod';

#Default value; subclasses can override
use constant _ACCEPT_UNNAMED => 0;

#Make all subclasses define this, even if it’s just an empty return.
sub _OPTIONS { ... }

=head2 I<CLASS>->new( ARG1, ARG2, .. )

Instantiate this class, including argument parsing. This will throw
errors on invalid inputs.

If the special parameter C<--help> is given, then this method
wil print the C<full_help()> and C<exit()>.

=cut

sub new {
    my ( $class, @argv ) = @_;

    Getopt::Long::Configure('pass_through');

    my %opts;
    Getopt::Long::GetOptionsFromArray(
        \@argv,
        \%opts,
        'help',
        $class->_OPTIONS(),
    );

    if ( $opts{'help'} ) {
        print "\n" . $class->full_help();
        exit;
    }

    my $unnamed_ar;

    if ( @argv && grep { $_ eq '--zxcvbnm' } @argv ) {
        my $msg = $class->locale()->maketext( 'This script does not recognize the following [numerate,_1,parameter,parameters]: [join, ,_2]', 0 + @argv, \@argv );
        die "\n" . $class->help($msg);
    }

    if ( $class->_ACCEPT_UNNAMED() ) {
        $unnamed_ar = \@argv;
    }
    elsif (@argv) {
        $class->_check_args_for_non_matching_usage(@argv);

        my $msg = $class->locale()->maketext( 'This script does not recognize the following [numerate,_1,parameter,parameters]: [join, ,_2]', 0 + @argv, \@argv );
        die "\n" . $class->help($msg);
    }

    return bless { _getopt => \%opts, _unnamed => $unnamed_ar }, $class;
}

=head2 I<OBJ>->getopt( NAME )

Returns the value of the given parameter.

=cut

sub getopt {
    my ( $self, $key ) = @_;

    return $self->{'_getopt'}{$key};
}

=head2 I<OBJ>->getopt_unnamed()

Returns the list of unnamed parameters given to C<new()>.

=cut

sub getopt_unnamed {
    my ($self) = @_;

    if ( !defined $self->{'_unnamed'} ) {
        my $func_name = ( caller 0 )[3];
        die "Invalid call to $func_name: class does not accept unnamed arguments!";
    }

    Cpanel::Context::must_be_list();

    return @{ $self->{'_unnamed'} };
}

=head2 I<OBJ>->help( $MESSAGE )

Returns the usage instructions as L<Pod::Usage> formats them.

$MESSAGE is given to Pod::Usage as its C<-message>.

=cut

sub help {
    my ( $self, $msg ) = @_;

    return $self->_help( $msg, 1 );
}

=head2 I<OBJ>->full_help( $MESSAGE )

Returns the full L<Pod::Usage> output (not just usage).

$MESSAGE is treated as in C<help()>.

=cut

sub full_help {
    my ( $self, $msg ) = @_;

    return $self->_help( $msg, 2 );
}

=head2 I<OBJ>->ensure_root()

Creates a L<Cpanel::Exception> if the script is not called by root.

=cut

sub ensure_root {
    my ($self) = @_;

    die Cpanel::Exception::create('RootRequired')->to_string_no_id() . "\n" unless ( $> == 0 && $< == 0 );
    return;
}

=head1 METHODS: REPORTING

These are useful for reporting to the human being who calls the script.

=head2 $output = I<OBJ>->get_output_object()

=cut

sub get_output_object ($self) {
    require Cpanel::HelpfulScript::Output;
    return $self->{'_output_obj'} ||= Cpanel::HelpfulScript::Output->new( script_obj => $self );
}

=head2 I<OBJ>->say( STRING )  I<OBJ>->say_makeZ<>text( MAKETEXT_STRING, ARG1, ARG2, … )

These parallel Perl’s built-in C<say()> function. C<say()> is useful
because it uses the test interface described below. C<say_makeZ<>text()> is
a handy shortcut for printing localizable strings.

=cut

sub say {
    my ( $self, @args ) = @_;

    return $self->_print( @args, "\n" );
}

sub say_maketext {
    my ( $self, $phrase, @args ) = @_;

    my $str = $self->locale()->makevar( $phrase, @args );

    return $self->say($str);
}

=head2 I<OBJ>->bold( STRING )

Applies terminal bold/reset escape sequences so that terminals will boldface
the given text when it’s printed.

=cut

sub bold {
    my ( $self, $str ) = @_;

    require Term::ANSIColor;
    return join( q<>, Term::ANSIColor::BOLD(), $str, Term::ANSIColor::RESET() );
}

=head2 I<OBJ>->locale()

Returns a L<Cpanel::Locale> instance.

=cut

my $locale;

sub locale {
    return $locale if $locale;
    require Cpanel::Locale;
    return ( $locale = Cpanel::Locale->get_handle() );
}

=head1 METHODS: PROMPTING

Useful for querying the user.

=head2 I<OBJ>->prompt_yn_makeZ<>text( MAKETEXT_STRING, ARG1, ARG2, … )

Asks the user a yes/no question (with proper formatting) and returns
a boolean to indicate the answer.

B<NOTE:> In unit tests you’ll want to override this.

=cut

sub prompt_yn_maketext {
    my ( $self, @mt_args ) = @_;

    require IO::Prompt;

    return IO::Prompt::prompt(
        '-one_char',
        '-yes_no',
        $self->locale()->makevar(@mt_args) . ' [y/n]: ',
    );
}

=head1 METHODS: TEST INTERFACE

The following methods are meant only for use in testing:

=head2 I<OBJ>->_print( ARG1, ARG2, … )

The built-in function is a wrapper around Perl’s C<print()> built-in.
In testing this is useful to override with something that appends to
a buffer so you can verify the script’s output.

=cut

sub _print { shift; return print @_ }

#----------------------------------------------------------------------

#For testing this (particular) module.
sub _reset_locale { undef $locale; return }

sub _help {
    my ( $class, $msg, $verbosity ) = @_;

    my $val;
    open my $wfh, '>', \$val or die "Failed to open to a scalar: $!";

    $msg .= "\n" if $msg;

    local $Pod::Usage::Formatter = 'Pod::Text::Termcap' if _stdout_is_terminal();

    #We have to defer loading Pod::Usage in order to control
    #how it formats output.
    require 'Pod/Usage.pm';    ##no critic qw(RequireBarewordIncludes)

    my $pod_path = $class->_determine_pod_path();

    'Pod::Usage'->can('pod2usage')->(
        -exitval   => 'NOEXIT',
        -message   => $msg,
        -verbose   => $verbosity,
        -noperldoc => 1,
        -output    => $wfh,
        -input     => $pod_path,
    );

    warn "No POD for “$class” in “$pod_path”!" if !$val;

    return $val;
}

sub _check_args_for_non_matching_usage {
    my ( $class, @args ) = @_;

    return if !@args;

    my @input_opts = grep { index( $_, '=' ) > -1 } map { split( /\|/, $_ ) } $class->_OPTIONS();
    return if !@input_opts;

    # user=s|u becomes "( 'user=s', 'u' )", then 'user'
    @input_opts = map { ( split( /=/, $_ ) )[0] } @input_opts;

    my @input_required_args = ();
    for my $arg (@args) {
        my $copy_arg = $arg;
        $copy_arg =~ s/^-+//g;
        for my $input_opt (@input_opts) {
            if ( index( $copy_arg, $input_opt ) == 0 ) {
                push @input_required_args, $arg;
            }
        }
    }

    if (@input_required_args) {
        my $msg = $class->locale()->maketext( 'The following [numerate,_1,parameter requires,parameters require] additional input: [join, ,_2]', scalar @input_required_args, \@input_required_args );
        die "\n" . $class->help($msg);
    }

    return;
}

sub _determine_pod_path {
    my ($self_or_class) = @_;

    my $path;

    if ( _env_is_binary() ) {
        $0 =~ m<(?:.+/)?([^/]+)> or die "\$0 should be a path, not “$0”!";
        $path = $self_or_class->BINPOD_DIR() . "/$1";
        $path =~ s<\.[^/.]*\z><>;
    }
    else {
        my $class = ref($self_or_class) || $self_or_class;

        my $class_path = ( $class =~ s<::></>gr );

        $path = $INC{$class_path} || $0;
    }

    return $path;
}

#overridden in tests
*_env_is_binary = *Cpanel::Binary::is_binary;

sub _stdout_is_terminal { return -t \*STDOUT; }

1;
