package Whostmgr::Transfers::Session::Start;

# cpanel - Whostmgr/Transfers/Session/Start.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Whostmgr::Transfers::Session::Setup ();
use Cpanel::CloseFDs                    ();
use Cpanel::SafeRun::Object             ();
use Cpanel::AdminBin::Serializer        ();
use Cpanel::Context                     ();
use Cpanel::Locale                      ();
use Try::Tiny;

our $START_TRANSFER_PATH = '/usr/local/cpanel/bin/start_transfer';

###########################################################################
#
# Method:
#   start_transfer_session
#
# Description:
#  Runs the start_transfer program which begins
#  processing the tasks that have been enqueued into
#  the provided transfer session.
#
#
# Parameters:
#   The transfer session id to start.
#
# Exceptions:
#   None.  Arguments are trapped into a two part return
#
# Returns:
#   Two Part
#       ( 1, The pid of the transfer session )
#          or
#       ( 0,  An error )
#
sub start_transfer_session {
    my ( $transfer_session_id, $opts_hr ) = @_;

    $opts_hr ||= {};

    Cpanel::Context::must_be_list();

    my ( $setup_ok, $session_obj ) = Whostmgr::Transfers::Session::Setup::setup_session_obj( { 'id' => $transfer_session_id } );
    if ( !$setup_ok ) {
        return ( $setup_ok, $session_obj );
    }

    # Start in a separate process to avoid keeping whostmgr5 in memory
    my $start_transfer_proc = Cpanel::SafeRun::Object->new(
        'program' => $START_TRANSFER_PATH,

        # We pass in the arguments over STDIN because
        # perlcc has a bug that will prevent use from changing
        # $0 if there are any arguments
        'before_exec' => sub {
            $ENV{'START_TRANSFER_USE_SERIALIZER'} = 1;
            Cpanel::CloseFDs::fast_closefds();
        },
        'stdin' => Cpanel::AdminBin::Serializer::Dump(
            {
                'transfer_session_id' => $transfer_session_id,
                'opts_hr'             => $opts_hr,
            }
        ),
    );

    my $start_pid;

    if ( $start_transfer_proc->CHILD_ERROR() ) {
        $session_obj->disconnect();    # TP TASK 20767 disconnect before global destruct

        return ( 0, $start_transfer_proc->stderr() );
    }
    else {
        my $response = $start_transfer_proc->stdout();
        my $response_ref;
        try {
            $response_ref = Cpanel::AdminBin::Serializer::Load($response);
        };

        if ($response_ref) {
            if ( $response_ref->{'status'} ) {
                $start_pid = $response_ref->{'pid'};
            }
            else {
                $session_obj->disconnect();    # TP TASK 20767 disconnect before global destruct

                return ( 0, $response_ref->{'statusmsg'} );
            }
        }
        else {
            my $stderr = $start_transfer_proc->stderr();
            $session_obj->disconnect();    # TP TASK 20767 disconnect before global destruct
            return ( 0, _locale()->maketext( "Failed to deserialize the response “[_1]” from [asis,start_transfer] with the following errors: [_2]", $response, $stderr ) );
        }
    }

    $session_obj->disconnect();    # TP TASK 20767 disconnect before global destruct
    return ( 1, $start_pid );
}

my $locale;

sub _locale {
    return $locale ||= Cpanel::Locale->get_handle();
}

1;
