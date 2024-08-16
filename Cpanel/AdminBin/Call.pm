package Cpanel::AdminBin::Call;

# cpanel - Cpanel/AdminBin/Call.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
#NOTE: This assumes that the admin module subclasses Cpanel::AdminBin::Script.
#This allows it to accept an arbitrary list of inputs and to return an
#arbitrary list of outputs (including empty list/undef).
#
#NOTE: This requires that the admin module's .conf file specify "full" mode.
#
#This passes void/scalar/list calling context into the admin function
#and also catches exceptions. Cpanel/AdminBin/Script/Call.pm knows how to
#consume this "format-within-a-format" to recreate the arguments and to send
#back a payload or exception as appropriate.
#----------------------------------------------------------------------

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::AdminBin::Call - client logic for admin function calls

=head1 SYNOPSIS

    my $result = Cpanel::AdminBin::Call::call( qw/ Cpanel mysql GET_SERVER_INFORMATION/ );

    # Only for non-parent-check calls …
    Cpanel::AdminBin::Call::call_nowait( .. );

    # Send a filehandle (pipe, socket, etc.) to the admin function …
    $result = Cpanel::AdminBin::Call::stream( $fh, qw/ Cpanel mysql STREAM_DUMP_DATA_UTF8MB4 hughs_data / );

=head1 DESCRIPTION

This module sends an admin (privilege escalation) function request to cpsrvd.
It is the principal interface to the admin function system.

=head1 CALLING MECHANICS

The workflow here is meant to mimic that of an in-process function call.
Arguments are given to the admin function as you give them here, and
the Perl call context (void, scalar, or list) is reproduced as well.

=head1 ERRORS

The intended pattern for admin functions is to indicate failure via an
exception. Such errors will propagate in the caller.

=head1 LEGACY FUNCTIONS

Note that admin modules that aren’t subclasses of either
L<Cpanel::Admin::Base> or L<Cpanel::AdminBin::Script::Call> aren’t callable
from this module; for those you’ll need to use L<Cpanel::AdminBin>.

=cut

#----------------------------------------------------------------------

use Cpanel::Exception    ();
use Cpanel::Wrap         ();
use Cpanel::Wrap::Config ();

#For testing.
our $_CPWRAP_NAMESPACE = 'Cpanel';

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 call( $NAMESPACE, $MODULE, $FUNCTION_NAME, @ARGUMENTS )

Calls the indicated admin function with the given arguments.
The return will vary depending on the function called.

=cut

sub call {
    my ( $namespace, $module, $action, @args ) = @_;

    my $admin = _call_wrap(
        undef,
        $namespace, $module, $action, @args,
    );

    return _parse_cpwrapd_response($admin);
}

#----------------------------------------------------------------------

=head2 stream( $FILEHANDLE, $NAMESPACE, $MODULE, $FUNCTION_NAME, @ARGUMENTS )

Like C<call()> but also sends a filehandle to the admin function.

NB: Only subclasses of L<Cpanel::Admin::Base> support such calls.

B<IMPORTANT:> It is hoped that eventually the admin protocol can be updated
such that filehandles can be passed as regular variables, à la D-Bus.
Once that happens, this function can go away.

=cut

sub stream {
    my ( $wfh, $ns, $module, $action, @args ) = @_;

    my $admin = _call_wrap(
        [ fdpass => $wfh ],
        $ns, $module, $action, @args,
    );

    return _parse_cpwrapd_response($admin);
}

#----------------------------------------------------------------------

=head2 call_nowait( $NAMESPACE, $MODULE, $FUNCTION_NAME, @ARGUMENTS )

Like C<call()> but returns immediately.

B<IMPORTANT:> This is only safe to use in calls that forgo the parent
process check.

=cut

sub call_nowait {
    my ( $namespace, $module, $action, @args ) = @_;

    _call_wrap(
        [ nowait => 1 ],
        $namespace, $module, $action, @args,
    );

    return;
}

#----------------------------------------------------------------------

sub _call_wrap {
    my ( $opts_kv, $namespace, $module, $action, @args ) = @_;

    return Cpanel::Wrap::send_cpwrapd_request_no_cperror(
        'namespace' => $namespace,
        'module'    => $module,
        'function'  => $action,
        'data'      => [
            {
                'wantarray' => ( caller 1 )[5],
            },
            \@args,
        ],
        'action' => 'fetch',
        'env'    => Cpanel::Wrap::Config::safe_hashref_of_allowed_env(),
        $opts_kv ? @$opts_kv : (),
    );
}

#NOTE: Used by certain test modules. Do NOT use publicly in production!
sub _parse_cpwrapd_response {
    my ($admin) = @_;

    #If this happens, then execution of the script itself failed.
    if ( !$admin->{'status'} || $admin->{'exit_code'} ) {
        _throw_error($admin);
    }

    #Reminder: a "Call" admin module is always "full" per its .conf file.
    my $response_hr = $admin->{'data'};

    #If we died from an exception, it'll be recorded here.
    if ( !$response_hr->{'status'} ) {
        my $class = $response_hr->{'class'};
        if ( length $class && $class ne 'Cpanel::Exception::Collection' ) {
            substr( $class, 0, 19, '' ) if index( $class, 'Cpanel::Exception::' ) == 0;
        }
        else {
            $class = 'Cpanel::Exception';
        }

        my $err = Cpanel::Exception::create_raw(
            $class,
            ( $response_hr->{'error_string'}   // '' ),
            ( $response_hr->{'error_metadata'} // () ),
        );
        if ( $response_hr->{'error_id'} ) {
            $err->set_id( $response_hr->{'error_id'} );
        }

        die $err;
    }

    #NOTE: If this was called in scalar context, then the array contains
    #exactly one member anyway.
    return wantarray ? @{ $response_hr->{'payload'} } : $response_hr->{'payload'}[0];
}

#This throws a generic AdminBin error with a "UNIX-y" message. It should only
#happen when the script execution failed for some reason.
sub _throw_error {
    my ($admin) = @_;

    if ( $admin->{'exit_code'} ) {
        my %metadata = (
            CHILD_ERROR             => $admin->{'exit_code'},
            message_from_subprocess => $admin->{'statusmsg'},
        );

        $metadata{'message_from_subprocess'} =~ s<\n\z><>;

        die Cpanel::Exception::create( 'AdminBinError', \%metadata );
    }

    die Cpanel::Exception::create_raw( 'AdminBinError', $admin->{'statusmsg'} );
}

1;
