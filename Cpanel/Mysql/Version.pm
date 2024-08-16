package Cpanel::Mysql::Version;

# cpanel - Cpanel/Mysql/Version.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

# This is global so tests can clear it; please create a function if
# the cache needs to be cleared in production.
our $_cached_server_information;

sub get_server_information {
    if ( !$_cached_server_information ) {
        require Cpanel::AdminBin::Call;
        require Cpanel::MysqlUtils::MyCnf::Basic;
        $_cached_server_information = Cpanel::AdminBin::Call::call( 'Cpanel', 'mysql', 'GET_SERVER_INFORMATION' );
        $_cached_server_information->{'is_remote'} = Cpanel::MysqlUtils::MyCnf::Basic::is_remote_mysql( $_cached_server_information->{'host'} );
    }

    return $_cached_server_information;
}

sub get_mysql_version {
    return get_server_information()->{'version'} if $>;
    require Cpanel::MysqlUtils::Version;
    return Cpanel::MysqlUtils::Version::current_mysql_version()->{'full'};
}

1;
