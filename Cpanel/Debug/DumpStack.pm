package Cpanel::Debug::DumpStack;

# cpanel - Cpanel/Debug/DumpStack.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Debug::DumpStack

=head1 SYNOPSIS

    require Cpanel::Debug::DumpStack;

    Cpanel::Debug::DumpStack::dump();

=head1 DESCRIPTION

This module is a “C<Carp::longmess()> on steroids” that prints a stack
trace I<with arguments>. It’s thus useful for debugging.

It should not be compiled in.

=head1 SEE ALSO

The logic for this module derives from similar logic in L<X::Tiny::Base>.

=cut

#----------------------------------------------------------------------

use Data::Dumper      ();
use Devel::StackTrace ();

#----------------------------------------------------------------------

=head1 dump()

Prints a stack trace with the arguments given to each level.

=cut

sub dump () {
    my $framenum = 0;

    my $dump_yn = 0;

    my $currentsubname = ( caller 0 )[3];

    local $Data::Dumper::Indent   = 1;
    local $Data::Dumper::Sortkeys = 1;
    local $Data::Dumper::Deparse  = 1;

    Devel::StackTrace->new(
        frame_filter => sub ($frame_data_hr) {
            my ( $filename, $line, $subname ) = @{ $frame_data_hr->{'caller'} }[ 1, 2, 3 ];
            if ($dump_yn) {
                print STDERR "--> $framenum: $subname ($filename, line $line):\n";

                print STDERR _get_args_str($frame_data_hr);

                $framenum++;
            }
            elsif ( $currentsubname eq $subname ) {
                $dump_yn = 1;
            }

            return 0;
        },
        filter_frames_early => 1,
    );

    return;
}

sub _get_args_str ($frame_data_hr) {
    my $out = Data::Dumper::Dumper( $frame_data_hr->{'args'} );
    $out =~ s<\A\$VAR[0-9]+ = ><>;
    $out =~ s<;\Z><\n>;

    return $out;
}

1;
