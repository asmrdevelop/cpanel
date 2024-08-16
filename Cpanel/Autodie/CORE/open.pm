package Cpanel::Autodie;

# cpanel - Cpanel/Autodie/CORE/open.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 FUNCTIONS

=head2 open( .. )

cf. L<perlfunc/open>

B<NOTE:> This function does not attempt to support every possible way of calling
Perl's C<open()> built-in, but to support the minimal syntax required to do
everything that is useful to do with C<open()>, with preference given to those
forms that may (somewhat arbitrarily) be considered "better".

For example, this function does NOT allow one-arg or two-arg C<open()> except
for the more “useful” cases like when MODE is C<-|> or C<|->.

On the other hand, C<open($fh, '-')> seems harder to understand than its 3-arg
equivalent (C<open($fh, '<&=', STDIN)>), so that two-arg form is unsupported.

Current forms of C<open()> that this supports are:

=over

=item * any form of 3 or more arguments

=item * 2-arg when the MODE is '-|' or '|-'

=back

B<NOTE:> Bareword file handles DO NOT WORK. (Auto-vivification does, though.)

=cut

sub open {    ## no critic(RequireArgUnpacking)
              # $_[0]: fh
              # $_[1]: mode
              # $_[2]: expr
              # $_[3..$#_]: list
    my ( $mode, $expr, @list ) = ( @_[ 1 .. $#_ ] );

    die "Avoid bareword file handles." if !ref $_[0] && length $_[0];
    die "Avoid one-argument open()."   if !$mode;

    local ( $!, $^E );
    if ( !defined $expr ) {
        if ( $mode eq '|-' or $mode eq '-|' ) {

            #NOTE: Some Perl versions appear to have buggy
            #handling of the // operator.
            my $open = CORE::open( $_[0], $mode );
            if ( !defined $open ) {
                my $err = $!;

                local $@;
                require Cpanel::Exception;

                die Cpanel::Exception::create( 'IO::ForkError', [ error => $err ] );
            }

            return $open;
        }

        my $file = __FILE__;
        die "Avoid most forms of two-argument open(). (See $file and its tests for allowable forms.)";
    }

    return CORE::open( $_[0], $mode, $expr, @list ) || do {
        my $err = $!;

        local $@;
        require Cpanel::Exception;

        if ( $mode eq '|-' || $mode eq '-|' ) {
            my $cmd = $expr;

            #If the EXPR (cf. perldoc -f open) has spaces and no LIST
            #is given, then Perl interprets EXPR as a space-delimited
            #shell command, the first component of which is the actual
            #command.
            if ( !@list ) {
                ($cmd) = ( $cmd =~ m<\A(\S+)> );
            }

            die Cpanel::Exception::create( 'IO::ExecError', [ path => $cmd, error => $err ] );
        }

        if ( 'SCALAR' eq ref $expr ) {
            die Cpanel::Exception->create( 'The system failed to open a file handle to a scalar reference because of an error: [_1]', [$err] );
        }

        require Cpanel::FileUtils::Attr;
        my $attributes = Cpanel::FileUtils::Attr::get_file_or_fh_attributes($expr);

        die Cpanel::Exception::create( 'IO::FileOpenError', [ mode => $mode, path => $expr, error => $err, immutable => $attributes->{'IMMUTABLE'}, 'append_only' => $attributes->{'APPEND_ONLY'} ] );
    };
}

1;
