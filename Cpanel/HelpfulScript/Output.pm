package Cpanel::HelpfulScript::Output;

# cpanel - Cpanel/HelpfulScript/Output.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::HelpfulScript::Output

=head1 SYNOPSIS

    my $output = $script_obj->get_output_object();

    $output->info('Checking …');

    {
        my $indent = $output->create_log_level_indent();

        $output->error('oh no!');
    }

=head1 DESCRIPTION

This module implements a L<Cpanel::Output> object for
L<Cpanel::HelpfulScript>.

=head1 ATTRIBUTES

This class requires that a C<script_obj> (i.e., L<Cpanel::HelpfulScript>
instance) be passed in to the constructor.

=cut

#----------------------------------------------------------------------

use parent (
    'Cpanel::Output::Formatted::Terminal',
);

use IO::Callback ();
use Scalar::Util ();

#----------------------------------------------------------------------

sub _init ( $self, $opts_hr ) {
    my $weak_script_obj = $opts_hr->{'script_obj'} or do {
        die 'Need “script_obj”!';
    };
    Scalar::Util::weaken($weak_script_obj);

    # Go through $script_obj’s _print() so that that method
    # remains overridable in tests.
    $self->{'filehandle'} = IO::Callback->new(
        '>',
        sub ( $out, @ ) {
            $weak_script_obj->_print($out);
        },
    );

    $self->{'_logger'} = $self;
    Scalar::Util::weaken( $self->{'_logger'} );

    return;
}

1;
