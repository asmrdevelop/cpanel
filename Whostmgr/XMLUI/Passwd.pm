package Whostmgr::XMLUI::Passwd;

# cpanel - Whostmgr/XMLUI/Passwd.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::ChangePasswd     ();
use Cpanel::Locale           ();
use Whostmgr::ApiHandler     ();
use Whostmgr::Passwd::Change ();
use Whostmgr::XMLUI          ();

my $locale;

sub passwd {
    my %OPTS         = @_;
    my $user         = $OPTS{'user'};
    my $pass         = $OPTS{'pass'};
    my $dbpassupdate = 1;
    $locale ||= Cpanel::Locale->get_handle();
    if ( exists $OPTS{'db_pass_update'} && !$OPTS{'db_pass_update'} ) {
        $dbpassupdate = 0;
    }

    my @RSD;
    if ( !defined $user ) {
        my $result = 0;
        my $output = $locale->maketext( 'No user name supplied: “[_1]” is a required argument.', "user" );
        @RSD = ( { 'status' => $result, 'statusmsg' => $output } );
    }
    elsif ( !defined $pass ) {
        my $result = 0;
        my $output = $locale->maketext( 'No password supplied: “[_1]” is a required argument.', "pass" );
        @RSD = ( { 'status' => $result, 'statusmsg' => $output } );
    }
    else {

        # The postgres key in the line below will do nothing as of this point, this is put in here as a place holder and should have no effect on current operations
        my $digest_auth       = Cpanel::ChangePasswd::get_digest_auth_option( \%OPTS, $user );
        my %optional_services = ( 'mysql' => $dbpassupdate, 'postgres' => $dbpassupdate, 'digest' => $digest_auth );
        my ( $result, $output, $passout, $services ) = Whostmgr::Passwd::Change::passwd( $user, $pass, \%optional_services );

        @RSD = (
            {
                'status'    => $result,
                'statusmsg' => $output,
                'rawout'    => $passout,
                'services'  => $services,
            }
        );
    }

    Whostmgr::XMLUI::xmlencode( \@RSD );

    my %RS;
    $RS{'passwd'} = \@RSD;
    return Whostmgr::ApiHandler::out( \%RS, 'RootName' => 'passwd', 'NoAttr' => 1 );
}

1;
