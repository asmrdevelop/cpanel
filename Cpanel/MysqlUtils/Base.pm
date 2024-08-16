package Cpanel::MysqlUtils::Base;

# cpanel - Cpanel/MysqlUtils/Base.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

sub instance {    ## no critic qw(RequireArgUnpacking)
    my $class = shift;

    my $dbh_singleton = $class->get_singleton();

    if ( !$dbh_singleton ) {
        my $obj = $class->new(@_);    # connect sets $dbh_singleton
        $class->set_singleton( $obj->{'dbh'} );
        return $obj;
    }
    else {
        return bless { 'dbh' => $dbh_singleton }, $class;
    }
}

sub disconnect {
    my $self = shift;

    if ( ref $self ) {
        return _safe_disconnect( $self->{'dbh'} );
    }
    else {
        my $st = _safe_disconnect( $self->get_singleton() );
        $self->set_singleton(undef);
        return $st;
    }
}

sub db_handle {
    my ($self) = @_;
    return $self->{'dbh'};
}

# This is designed to be called as Cpanel::MysqlUtils::Connect::connect();
# or as Cpanel::MysqlUtils::Connect->connect() and it will setup the
# $dbh_singleton singleton
#
sub connect {    ## no critic qw(RequireArgUnpacking)
    my $class = shift;

    my $obj = $class->new(@_);

    if ( $obj && $obj->{'dbh'} ) {
        $class->set_singleton( $obj->{'dbh'} );
        return 1;
    }
    else {
        return 0;
    }

}

sub _safe_disconnect {
    my ($dbh_obj) = @_;

    return 1 if !$dbh_obj;

    # case 106345:
    # libmariadb has been patched to send
    # and receive with MSG_NOSIGNAL
    # thus avoiding the need to trap SIGPIPE
    # on disconnect which can not be reliably
    # done in perl because perl will overwrite
    # a signal handler that was done outside
    # of perl and fail to restore a localized
    # one.
    local $@;

    if ( $dbh_obj->can('close') ) {
        if (
            eval {
                local $SIG{'__DIE__'}  = sub { };
                local $SIG{'__WARN__'} = sub { };
                return $dbh_obj->{'socket'}->getpeername();
            }
        ) {
            eval { $dbh_obj->close(); };
        }
        else {
            $@ = undef;    # already disconnected, ignore error
        }
    }
    else {
        eval { $dbh_obj->disconnect(); };
    }

    $dbh_obj = undef;

    return $@ ? 0 : 1;
}

1;
