package Cpanel::Template::Plugin::Mysql;

# cpanel - Cpanel/Template/Plugin/Mysql.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

use parent 'Cpanel::Template::Plugin::CpanelDB';

use Cpanel::LoadModule ();
use Cpanel::Logger     ();

my $running;

=head1 NAME

C<Cpanel::Template::Plugin::Mysql>

=head1 DESCRIPTION

Template toolkit plugin used for some common interactions with the mySql
database used by cPanel.

=head1 SYNOPSIS

When used in template toolkit templates:

  [% USE Mysql; %]
  Version Installed: [% Mysql.mysql_display_name %] [% Mysql.mysqlversion %]
  Status: [% IF Mysql.running %]Running[% ELSE %]Not Running[% END%]
  Minimum Password Strength: [% Mysql.required_password_strength %]

  [% IF Mysql.is_version_no_longer_supported %]
  Your [% Mysql.mysql_display_name %] version is not compatible with
  this version of cPanel. Please update to a newer version.
  [% END %]

  [% IF Mysql.is_version_going_eol_soon %]
  Your [% Mysql.mysql_display_name %] version is going EOL soon. Please upgrade now.
  [% END %]

  [%
    # When calling one or more mySql related UAPI calls first:
    Mysql.initcache();

    # Then call one or more mySql UAPI calls.
    SET results = execute('Mysql', 'list_databases', {});
  %]
=cut

=head1 CONSTRUCTORS

=head2 new()

Constructor for the plugin

=head3 RETURNS

new instance of the C<Cpanel::Template::Plugin::Mysql> plugin.

=cut

sub new {
    my ($class) = @_;

    my $self = {};
    bless $self, $class;
    return $self;
}

=head1 MEMBERS

=head2 required_password_strength()

Gets the currently configured minimum password strength for mySql database user passwords

=head3 RETURNS

number - minimum password strength required. Password strengths are calculate by a cPanel proprietary system. May be in the range 0-100.

=cut

*required_password_strength = __PACKAGE__->can('_required_password_strength');

=head2 mysqlversion()

Get the current version of mySql.

=head3 RETURNS

string - the version number for the mySql used by cPanel.

=cut

sub mysqlversion {
    return try {

        local $Cpanel::Logger::DISABLE_OUTPUT = 1;
        local $Cpanel::Logger::STD_LOG_FILE   = '/dev/null';

        $> ? _mysqlversion_as_user() : _mysqlversion_as_root();
    }
    catch {
        $Cpanel::MysqlUtils::Version::DEFAULT_MYSQL_RELEASE_TO_ASSUME_IS_INSTALLED;
    };
}

=head2 mysql_display_name()

Get the display name (MySQL or MariaDB) of the currently installed version.

=head3 RETURNS

string - the display name (MySQL or MariaDB) correlated to the installed version number.

=cut

sub mysql_display_name {
    require Cpanel::MariaDB;
    return "MariaDB" if Cpanel::MariaDB::version_is_mariadb( mysqlversion() );
    return "MySQL";
}

=head2 is_version_no_longer_supported()

Checks if the minimum required mySQL version is available.

=head3 RETURNS

boolean - true value if the current mySql version is less than the minimum required version. false value otherwise. This uses Perl semantics for true and false.

=cut

sub is_version_no_longer_supported {
    require Cpanel::Update::Blocker::Constants::MySQL;
    return mysqlversion() < Cpanel::Update::Blocker::Constants::MySQL::MINIMUM_RECOMMENDED_MYSQL_RELEASE();
}

=head2 is_version_going_eol_soon()

Checks if the MySQL or MariaDB version will be EOL soon.

=head3 RETURNS

boolean - true value if the current MySQL/MariaDB version has been flagged as approaching EOL, otherwise returns false. This uses Perl semantics for true and false.

=cut

sub is_version_going_eol_soon {
    return 0 if is_mysql_remote();

    require Cpanel::Update::Blocker::Constants::MySQL;

    my $version = mysqlversion();
    return 1 if $version eq Cpanel::Update::Blocker::Constants::MySQL::MYSQL_RELEASE_APPROACHING_EOL();
    return 1 if $version eq Cpanel::Update::Blocker::Constants::MySQL::MARIADB_RELEASE_APPROACHING_EOL();
    return 0;
}

sub is_version_eol_now {
    return 0 if is_mysql_remote();

    require Cpanel::Update::Blocker::Constants::MySQL;
    require Cpanel::MysqlUtils::Version;

    my $version = mysqlversion();

    if ( Cpanel::MariaDB::version_is_mariadb($version) ) {
        return 0 if Cpanel::MysqlUtils::Version::is_at_least( $version, Cpanel::Update::Blocker::Constants::MySQL::MINIMUM_CURRENTLY_SUPPORTED_MARIADB() );
    }
    else {
        return 0 if Cpanel::MysqlUtils::Version::is_at_least( $version, Cpanel::Update::Blocker::Constants::MySQL::MINIMUM_CURRENTLY_SUPPORTED_MYSQL() );
    }

    return 1;
}

sub is_mysql_remote {
    require Cpanel::MysqlUtils::MyCnf::Basic;
    return Cpanel::MysqlUtils::MyCnf::Basic::is_remote_mysql();
}

=head2 is_mysql_unmanaged()

Checks if the MySQL or MariaDB install is unmanaged.

=head3 RETURNS

boolean - true value if the current MySQL/MariaDB install is unmanaged, otherwise returns false. This uses Perl semantics for true and false.

=cut

sub is_mysql_unmanaged {
    require Whostmgr::Mysql::Upgrade;

    return Whostmgr::Mysql::Upgrade::is_mysql_unmanaged();
}

=head2 running()

Checks if the mySql is running.

=head3 RETURNS

boolean - 1 if mySql is running. 0 otherwise.

=cut

sub running {
    my $running = try { mysqlversion() };
    return $running ? 1 : 0;
}

=head2 initcache()

Initialize the MySQL database information cache used to improve the performance of some cPanel MySQL api calls. Use this on pages that make use of UAPI Mysql method calls.

=cut

sub initcache {
    Cpanel::LoadModule::load_perl_module('Cpanel::MysqlFE::DB');
    return Cpanel::MysqlFE::DB::_initcache();
}

=head1 PROTECTED METHODS

=head2 __PASSWORD_STRENGTH_APP()

Method used by the parent class to define which password strength property to use.

=head3 RETURNS

string - name of the strength property. Always 'mysql'.

=cut

sub _PASSWORD_STRENGTH_APP { return 'mysql'; }

=head1 PRIVATE METHODS

=head2 _mysqlversion_as_root()

Get the current version of mySql. This method can be called by root only.

=head3 RETURNS

string - the version number for the installed mySql.

=cut

sub _mysqlversion_as_root {
    Cpanel::LoadModule::load_perl_module('Cpanel::MysqlUtils::Version');

    return Cpanel::MysqlUtils::Version::mysqlversion();
}

=head2 _mysqlversion_as_user()

Get the current version of mySql. This method can be called by a cPanel user.

=head3 RETURNS

string - the version number for the installed mySql.

=cut

sub _mysqlversion_as_user {

    #It’s almost certainly loaded by now, but just in case.
    Cpanel::LoadModule::load_perl_module('Cpanel::API');

    my $result = Cpanel::API::execute( 'Mysql', 'get_server_information' );
    die $result->errors_as_string() if !$result->status();

    return ( $result->data()->{'version'} =~ m<\A([0-9]+\.[0-9]+)> )[0];
}

1;
