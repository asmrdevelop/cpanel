package Cpanel::Mysql::Error;

# cpanel - Cpanel/Mysql/Error.pm                     Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use constant {

    #cf. https://dev.mysql.com/doc/refman/5.5/en/error-messages-server.html
    ER_ACCESS_DENIED_ERROR           => 1045,
    ER_BAD_DB_ERROR                  => 1049,
    ER_BAD_FIELD_ERROR               => 1054,
    ER_DUP_FIELDNAME                 => 1060,
    ER_CANNOT_USER                   => 1396,
    ER_DB_CREATE_EXISTS              => 1007,
    ER_DB_DROP_EXISTS                => 1008,
    ER_NONEXISTING_GRANT             => 1141,
    ER_NOT_ALLOWED_COMMAND           => 1148,
    ER_PASSWORD_NO_MATCH             => 1133,
    ER_PARSE_ERROR                   => 1064,
    ER_SERVER_IS_IN_SECURE_AUTH_MODE => 1275,
    ER_USER_LIMIT_REACHED            => 1226,
    ER_SP_DOES_NOT_EXIST             => 1305,

    #cf. https://dev.mysql.com/doc/refman/5.5/en/error-messages-client.html
    #Also include/errmsg.h in the MariaDB client library source tree.
    CR_CONN_HOST_ERROR  => 2003,
    CR_CONNECTION_ERROR => 2002,
    CR_SERVER_LOST      => 2013,

    # Given when, e.g., INFORMATION_SCHEMA.GLOBAL_VARIABLES is referenced
    # in MySQL 5.7+ but “show_compatibility_56” is disabled.
    ER_FEATURE_DISABLED_SEE_DOC     => 3167,
    ER_COMPONENTS_UNLOAD_NOT_LOADED => 3537,

    # In MySQL 8:
    ER_CLIENT_LOCAL_FILES_DISABLED => 3948,

    # In MariaDB 10.5:
    ER_LOAD_INFILE_CAPABILITY_DISABLED => 4166,

    _cr_min_error => 2000,
    _cr_max_error => 2999,
};

sub is_client_error_code {
    my ($code) = @_;

    return ( $code >= _cr_min_error ) && ( $code <= _cr_max_error ) ? 1 : 0;
}

sub get_name_for_error {
    my ($num) = @_;

    for my $k ( keys %Cpanel::Mysql::Error:: ) {
        next if $k !~ m<\A(?:ER|CR)>;
        my $cr = __PACKAGE__->can($k) or next;

        return $k if $cr->() == $num;
    }

    return undef;
}

1;
