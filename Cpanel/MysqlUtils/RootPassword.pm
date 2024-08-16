package Cpanel::MysqlUtils::RootPassword;

# cpanel - Cpanel/MysqlUtils/RootPassword.pm             Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::SafeRun::Object              ();
use Cpanel::MysqlUtils::MyCnf::Basic     ();
use Cpanel::MysqlUtils::MyCnf            ();
use Cpanel::Validate::LineTerminatorFree ();
use Cpanel::Exception                    ();
use Cpanel::PwCache                      ();

use Try::Tiny;

=encoding utf-8

=head1 NAME

Cpanel::MysqlUtils::RootPassword

=head1 SYNOPSIS

    Cpanel::MysqlUtils::RootPassword::set_mysql_root_password($raw_password);

    Cpanel::MysqlUtils::RootPassword::update_mysql_root_password_in_configuration($raw_password);

=head1 DESCRIPTION

This module will gracefully change the mysql root password if caller knows
the existing root password or it is in ~/.my.cnf

If you have lost the password you must use Cpanel::MysqlUtils::ResetRootPassword
instead which is a much larger (riskier) hammer.

=head1 FUNCTIONS

=head2 set_mysql_root_password($raw_password)

Set the password mysql and do everything
update_mysql_root_password_in_configuration does.

=cut

sub set_mysql_root_password {
    my ($raw_password) = @_;

    Cpanel::Validate::LineTerminatorFree::validate_or_die($raw_password);

    Cpanel::SafeRun::Object->new_or_die(
        program => '/usr/local/cpanel/scripts/mysqlpasswd',
        args    => ['--multistdin'],
        stdin   => "root\n$raw_password\n\n",
    );

    Cpanel::MysqlUtils::MyCnf::Basic::clear_cache();

    return 1;
}

=head2 update_mysql_root_password_in_configuration($raw_password)

Set the password in ~/.my.cnf and any other files that need to be
updated.

=cut

sub update_mysql_root_password_in_configuration {
    my ($pass) = @_;
    my $host   = Cpanel::MysqlUtils::MyCnf::Basic::getmydbhost('root');
    my $dbuser = Cpanel::MysqlUtils::MyCnf::Basic::getmydbuser('root') || 'root';

    # Whostmgr::API::1::LocalMySQL::set_local_mysql_root_password
    # does similar code but it does a full password reset
    Cpanel::MysqlUtils::MyCnf::update_mycnf(
        user  => 'root',
        items => [
            {
                user => $dbuser,
                pass => $pass,
                ( $host ? ( host => $host ) : () ),
            }
        ],
    );
    Cpanel::MysqlUtils::MyCnf::update_mycnf(
        user       => 'root',
        section    => 'mysqladmin',
        if_present => 1,
        items      => [
            {
                'pass' => $pass,
            }
        ],
    );

    _update_mysql_profile($pass);

    _check_for_relocated_root();

    return 1;
}

sub _check_for_relocated_root {
    my $homedir = Cpanel::PwCache::gethomedir('root');

    # Check for relocated root. Why, oh why change root's homedir???
    if ( !-e '/root' ) {
        mkdir '/root', 0700 or warn "mkdir(/root): $!";
    }
    if ( $homedir ne '/root' && -d '/root' ) {
        warn "Detected relocated /root directory ($homedir)\n";
        system 'cp', '-f', '--', $homedir . '/.my.cnf', '/root/.my.cnf';
    }

    return;
}

sub _update_mysql_profile {
    my $newpass = shift;

    try {
        require Cpanel::MysqlUtils::RemoteMySQL::ProfileManager;
        my $profile_manager = Cpanel::MysqlUtils::RemoteMySQL::ProfileManager->new();
        $profile_manager->generate_active_profile_if_none_set();
        $profile_manager->update_password_for_active_profile_host($newpass);
    }
    catch {
        print 'Failed to update MySQL profile: ' . Cpanel::Exception::get_string($_) . "\n";
    };

    return 1;
}

1;
