package Whostmgr::Transfers::Session::Preflight::RemoteUser::Create;

# cpanel - Whostmgr/Transfers/Session/Preflight/RemoteUser/Create.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::SocketIP                    ();
use Whostmgr::Transfers::Session::Setup ();
use Cpanel::Locale                      ();

use Whostmgr::Transfers::Session::Constants          ();
use Whostmgr::Transfers::RestrictedRestore           ();
use Whostmgr::Transfers::Session::Preflight::Restore ();

my $locale;

sub create_remote_user_transfer_session {
    my $opts = shift;

    $locale ||= Cpanel::Locale->get_handle();

    if ( !Whostmgr::Transfers::RestrictedRestore::available() && !$opts->{'unrestricted_restore'} ) {
        return ( 0, $locale->maketext('Restricted Restore is not available in this version of [output,asis,cPanel].') );
    }

    foreach my $arg (qw(host password)) {
        return ( 0, $locale->maketext( "You must specify a “[_1]” argument.", $arg ) ) if !$opts->{$arg};
    }

    my $ip = Cpanel::SocketIP::_resolveIpAddress( $opts->{'host'}, 'timeout' => 5, any_proto => 1 );
    if ( !$ip ) {
        return ( 0, $locale->maketext( "The system was unable to resolve the hostname, “[_1]”, to an IP address.", $opts->{'host'} ) );
    }

    my ( $adjust_ok, $adjust_msg ) = Whostmgr::Transfers::Session::Preflight::Restore::ensure_mysql_is_sane_for_restore();
    return ( $adjust_ok, $adjust_msg ) if !$adjust_ok;

    my $new_session_data = _create_session_data_from_opts($opts);

    my ( $session_ok, $session_obj ) = Whostmgr::Transfers::Session::Setup::setup_session_obj(
        {
            'initiator'           => Whostmgr::Transfers::Session::Constants::USER_API_SESSION_INITIATOR,
            'create'              => 1,
            'session_id_template' => $opts->{'host'},
        },
        $new_session_data
    );
    return ( 0, $session_obj ) if !$session_ok;

    $session_obj->set_source_host( $opts->{'host'} );

    my $id = $session_obj->id();

    $session_obj->disconnect();    # TP TASK 20767 disconnect before global destruct

    return ( 1, $id );
}

sub _create_session_data_from_opts {

    my ($opts) = @_;

    my $new_session_data = {
        'session' => {
            'scriptdir'    => '/scripts',
            'state'        => 'preflight',
            'session_type' => $Whostmgr::Transfers::Session::Constants::SESSION_TYPES{'RemoteUser'},
        },
        'queue'   => { map { $_ => 0 } @Whostmgr::Transfers::Session::Constants::QUEUES },
        'options' => {
            'unrestricted' => $opts->{'unrestricted_restore'} ? 1 : 0,
        },
        'authinfo' => {
            'pass' => $opts->{'password'},
        },
        'remote' => {
            'can_stream' => 0,
            'host'       => $opts->{'host'},
        }
    };
    return $new_session_data;
}

1;
