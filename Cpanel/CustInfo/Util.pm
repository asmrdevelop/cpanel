package Cpanel::CustInfo::Util;

# cpanel - Cpanel/CustInfo/Util.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Mkdir                        ();
use Cpanel::Exception                    ();
use Cpanel::Validate::FilesystemNodeName ();

#-----------------------------------------------------------------------------
# Developer Notes:
#
# This file contains only simple helpers
#-----------------------------------------------------------------------------

sub get_dir {
    my ( $cphomedir, $is_virtual, $username ) = @_;
    my $dir = '';
    if ($is_virtual) {
        $dir = _get_dir_for_just_webmail( $cphomedir, $username );
    }
    elsif ( $ENV{'TEAM_USER'} ) {
        $dir = "$cphomedir/$ENV{'TEAM_USER'}";
    }
    else {
        $dir = $cphomedir;
    }

    return $dir;
}

sub get_dot_cpanel {
    my ( $cphomedir, $is_virtual, $username ) = @_;
    my $dir = get_dir( $cphomedir, $is_virtual, $username );
    return ensure_dot_cpanel($dir);
}

sub ensure_dot_cpanel {
    my ($dir) = @_;
    my $dot_cpanel = "$dir/.cpanel";
    Cpanel::Mkdir::ensure_directory_existence_and_mode( $dot_cpanel, 0700 );
    return $dot_cpanel;
}

sub is_user_virtual {
    my ( $appname, $cpuser, $username ) = @_;
    $username = $cpuser if !$username;

    # team_user sending an activation email for email_account creation
    # should still return 1 for webmail account
    return 0 if $ENV{'TEAM_USER'} && $appname ne 'webmail' && $username eq "$ENV{'TEAM_USER'}\@$ENV{'TEAM_LOGIN_DOMAIN'}";
    return 1 if $username && $username =~ m{^[^@]*@[^@]*$};
    return 0 if !$appname;
    return 0 if $appname ne 'webmail';
    return 0 if $cpuser eq $username;

    return 1;
}

sub _get_dir_for_just_webmail {
    my ( $dir,     $username ) = @_;
    my ( $mailbox, $domain )   = split( '@', $username, 2 );

    if ( grep { !Cpanel::Validate::FilesystemNodeName::is_valid($_) } $mailbox, $domain ) {
        die Cpanel::Exception::create( 'InvalidUsername', [ value => $username ] );
    }

    return "$dir/etc/$domain/$mailbox";
}

1;
