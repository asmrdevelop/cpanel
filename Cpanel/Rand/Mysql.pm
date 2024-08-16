package Cpanel::Rand::Mysql;

# cpanel - Cpanel/Rand/Mysql.pm                    Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Rand::Mysql - helper to generate a random db/user/password for a cPanel user randomized and given back to the caller.

=cut

use Cpanel::DB::Prefix                              ();
use Cpanel::MysqlUtils::RemoteMySQL::ProfileManager ();
use Cpanel::Rand::Get                               ();
use Cpanel::Validate::DB::Name                      ();
use Cpanel::Validate::DB::User                      ();

use constant MAX_DB_LEN         => 50;
use constant MAX_USER_LEN       => 32;
use constant ALLOWED_DB_CHARS   => [ "a" .. "z", "0" .. "9" ];
use constant ALLOWED_PASS_CHARS => [ "a" .. "z", "A" .. "Z", "0" .. "9", qw{~ ! @ $ % ^ & * ( ) _ - + = { } [ ] / < > . ; ? : | }, '#', ',' ];

=head1 FUNCTIONS

=head2 mysql_host_port

Determines the host and port used to connect to Mysql.

=cut

sub mysql_host_port {
    my $profiles = Cpanel::MysqlUtils::RemoteMySQL::ProfileManager->new( { read_only => 1 } )->read_profiles();
    my ($active_profile) = grep { $profiles->{$_}->{'active'} } keys %$profiles;

    my $host = $profiles->{$active_profile}->{'mysql_host'} // 'localhost';
    my $port = $profiles->{$active_profile}->{'mysql_port'} // 3306;

    return ( $host, $port );
}

=head2 get_random_db_password

Provides a randomized database password that can be used for a Mysql user.

=cut

sub get_random_db_password {
    return Cpanel::Rand::Get::getranddata( 30, ALLOWED_PASS_CHARS );
}

=head2 get_random_db_name ( $cpuser, $prefix = "" ) {

Provides a randomized database name prefixed with the cpuser. If $prefix is passed, the
prefix is appended to the cpuser prior to the randomized portion of the name.

Example return: cpuser_wp_dkhfr3glrkrhvn3

You must pass what the cPanel user name is but prefix is optional. If you do not pass prefix
then the output would be something like:

Example return: cpuser_dkhfr3glrkrhvn3

=cut

sub get_random_db_name ( $cpuser, $prefix = "" ) {
    my $max_legal_len = $Cpanel::Validate::DB::Name::max_mysql_dbname_length;
    return _random_name( $cpuser, $prefix, $max_legal_len, MAX_DB_LEN ),;
}

=head2 get_random_db_user ( $cpuser, $prefix = "" ) {

Provides a randomized database user prefixed with the cpuser. If $prefix is passed, the
prefix is appended to the cpuser prior to the randomized portion of the name.

Example return: cpuser_wp_dkhfr3glrkrhvn3

You must pass what the cPanel user name is but prefix is optional. If you do not pass prefix
then the output would be something like:

Example return: cpuser_dkhfr3glrkrhvn3


=cut

sub get_random_db_user ( $cpuser, $prefix = "" ) {
    my $max_legal_len = Cpanel::Validate::DB::User::get_max_mysql_dbuser_length();
    return _random_name( $cpuser, $prefix, $max_legal_len, MAX_USER_LEN ),;
}

sub _random_name ( $cpuser, $prefix, $max_legal_len, $max_string_len ) {
    my $name_prefix = Cpanel::DB::Prefix::username_to_prefix($cpuser);

    my $prefix_len = length $prefix;
    if ($prefix_len) {
        $prefix =~ m/([^a-zA-Z0-9])/ and die("Illegal character '$1' found in database type prefix. Must be alphanumeric only");
        $prefix_len <= 6 or die("Database type prefixes must be 6 characters or less");
        $name_prefix .= '_' . $prefix;    # cpuser_prefix
    }
    $name_prefix .= '_';                  # cpuser_ or cpuser_prefix_

    # These chars take up 2 bytes so we need to adjust for them. We don't want to ever use them as a random character in getranddata.
    my @double_chars = $name_prefix =~ m/[_\\%]/g;

    my $random_len = $max_legal_len - length($name_prefix) - 2 * scalar @double_chars;

    $random_len = $max_string_len if $random_len > $max_string_len;
    $random_len >= 4 or die("Unexpected random length ($random_len) as '$name_prefix'");    # This should never happen.

    return Cpanel::DB::Prefix::add_prefix_if_name_needs( $cpuser, $name_prefix . Cpanel::Rand::Get::getranddata( $random_len, ALLOWED_DB_CHARS ) );
}

1;
