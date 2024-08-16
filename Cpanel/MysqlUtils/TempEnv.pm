package Cpanel::MysqlUtils::TempEnv;

# cpanel - Cpanel/MysqlUtils/TempEnv.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Session::Temp ();

sub get_parameters {
    return ( get_host(), get_user(), get_password() );
}

sub get_user {
    if ( !$ENV{'REMOTE_USER'} ) {
        die "REMOTE_USER could not be determined from ENV";
    }
    return ( $ENV{'SESSION_TEMP_USER'} ? Cpanel::Session::Temp::full_username_from_temp_user( $ENV{'REMOTE_USER'}, $ENV{'SESSION_TEMP_USER'} ) : $ENV{'REMOTE_USER'} );
}

sub get_host {
    return $ENV{'REMOTE_MYSQL_HOST'} || 'localhost';
}

sub get_password {
    my $pass = ( $ENV{'SESSION_TEMP_PASS'} || $ENV{'REMOTE_PASSWORD'} );    #TEMP_SESSION_SAFE
    $pass or die "No mysql pass could be determined from ENV";
    return $pass;
}

sub new {
    my ( $class, %init ) = @_;

    my ( $host, $user, $password ) = @init{qw(host user password)};

    require Cpanel::MysqlUtils::Quote;
    require Cpanel::DbUtils;
    require Cpanel::TempFile;
    require Cpanel::FileUtils::Write;

    my $self = bless {}, $class;

    $self->{'temp_obj'}   = Cpanel::TempFile->new();
    $self->{'temp_dir'}   = $self->{'temp_obj'}->dir();
    $self->{'mysql_user'} = $user // get_user();

    my $mysql_host = $host     // get_host();
    my $mysql_pass = $password // get_password();

    my $quoted_mysql_user = Cpanel::MysqlUtils::Quote::quote_conf_value( $self->{'mysql_user'} );
    my $quoted_mysql_pass = Cpanel::MysqlUtils::Quote::quote_conf_value($mysql_pass);

    my $contents = "[client]\nhost=\"$mysql_host\"\nuser=\"$quoted_mysql_user\"\npassword=\"$quoted_mysql_pass\"\n";

    Cpanel::FileUtils::Write::overwrite_no_exceptions( "$self->{'temp_dir'}/.my.cnf", $contents, 0600 ) || die "Could not write $self->{'temp_dir'}/.my.cnf: $!";

    return $self;
}

sub exec_mysql {
    my ( $self, @args ) = @_;

    my $mysql_bin = Cpanel::DbUtils::find_mysql();

    local $ENV{'HOME'} = $self->{'temp_dir'};

    exec( $mysql_bin, $self->get_mysql_params(), @args ) or exit(1);
}

sub exec_coderef {
    my ( $self, $coderef ) = @_;

    local $ENV{'HOME'} = $self->{'temp_dir'};

    return $coderef->();
}

sub get_mysql_user {
    my ($self) = @_;

    return $self->{'mysql_user'};
}

sub get_mysql_params {
    my ($self) = @_;

    return ( '--defaults-file=' . "$self->{'temp_dir'}/.my.cnf", "-u$self->{'mysql_user'}" );
}

1;
