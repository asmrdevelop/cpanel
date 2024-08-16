package Cpanel::Template::Plugin::UIAnalytics;

#                                      Copyright 2024 WebPros International, LLC
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited.

use strict;
use warnings;

use Cpanel::License::CompanyID();
use Cpanel::Locale::Utils::User();
use Cpanel::Version();
use Cpanel::License::Flags();
use Cpanel::Server::Type();
use Cpanel::DIp::MainIP();
use Cpanel::OS();
use Cpanel::NAT();

use base 'Template::Plugin';

# Caches the root creation date so the system call happens ONLY once if needed.
$Cpanel::Template::Plugin::UIAnalytics::root_creation_date = 0;

=encoding utf-8

=head1 NAME

Cpanel::Template::Plugin::UIAnalytics - Plugin to gather information for analytics.

=head1 DESCRIPTION

This plugin is a consolidated module to gather information that is eventually
forwarded to the provider of cPanel analytics.

In case of something going wrong while trying to retrieve one of the values, it will
be set to 'N/A' instead to indicate that something went wrong.

=head1 METHODS

=cut

=head2 _get_common_analytics_data()

Retrieves information that is common to all user inferfaces, including WHM, cpanel, and webmail.

=head3 RETURNS

A hashref of the following key, value pairs.

=over

=item companyId - string

Unique identifier of the hosting company that holds license for the server.

=item server_current_license_kind - string

The type of license that the server holds.

=item product_locale - string

The locale that is being used for this session.

=item product_version - string

Current version of cPanel that is installed on the server.

=item server_main_ip - string

Main ip of the server.

=item server_operating_system - string

Operation system that runs the server.

=item product_trial_status - string

Whether the server holds a trial license of cPanel.

=item analytics_distribution - string

Set to 'cp-analytics' to indicate that it is distributed through cp-analytics plugin.

=back

=cut

sub _get_common_analytics_data {
    my %analytics_data = (
        _get_account_data(),
        'analytics_distribution'      => 'ULC',
        'company_id'                  => Cpanel::License::CompanyID::get_company_id(),
        'product_locale'              => Cpanel::Locale::Utils::User::get_user_locale(),
        'product_version'             => Cpanel::Version::get_version_display(),
        'product_trial_status'        => ( Cpanel::License::Flags::has_flag('trial') ? 'true' : 'false' ),
        'server_current_license_kind' => Cpanel::Server::Type::get_producttype(),
        'server_main_ip'              => Cpanel::NAT::get_public_ip( Cpanel::DIp::MainIP::getmainip() ),
        'server_operating_system'     => Cpanel::OS::display_name(),
        'is_nat'                      => Cpanel::NAT::is_nat(),
    );

    # This depends on a previous variable so we have to do it after the fact.
    $analytics_data{'server_main_ip_is_private'} = eval {
        require Cpanel::Ips;
        Cpanel::Ips::is_private( $analytics_data{'server_main_ip'} ) ? 1 : 0;
    } // 'N/A';    # 2 means this failed or we couldn't determine it.

    return \%analytics_data;
}

=head2 get_whm_analytics_data()

Retrieves information that is specific to WHM user interfaces in addition to common analytics data.

=head3 RETURNS

A hashref of the following key, value pairs.

=over

=item product_interface - string

Should be set to WHM.

=back

=cut

sub get_whm_analytics_data {
    my $is_root        = $ENV{'REMOTE_USER'} && $ENV{'REMOTE_USER'} eq 'root' ? 1 : 0;
    my %analytics_data = (
        %{ _get_common_analytics_data() },
        'product_interface' => 'WHM',
        'is_root'           => $is_root,
    );

    if ($is_root) {
        eval {
            require Cpanel::UUID::Server;
            $analytics_data{'UUID'}        = Cpanel::UUID::Server::get_server_uuid();
            $analytics_data{'ACCOUNT_AGE'} = _get_root_age();
        }
    }

    return \%analytics_data;
}

=head2 get_cpanel_analytics_data()

Retrieves information that is specific to cpanel user interfaces in addition to common analytics data.

=head3 RETURNS

A hashref of the following key, value pairs.

=over

=item product_interface - string

Should be set to cPanel.

=back

=cut

sub get_cpanel_analytics_data {
    my $is_team_user    = $ENV{'TEAM_USER'} ? 1 : 0;
    my $team_user_roles = 'N/A';
    if ($is_team_user) {
        require Cpanel::Team::Config;

        my $team_obj = Cpanel::Team::Config->new( $ENV{'TEAM_OWNER'} );
        $team_user_roles = $team_obj->get_team_user_roles( $ENV{'TEAM_USER'} );
    }
    my %analytics_data = (
        %{ _get_common_analytics_data() },
        'product_interface' => 'cPanel',
        'is_team_user'      => $is_team_user,
        'team_user_roles'   => $team_user_roles,
    );

    return \%analytics_data;
}

=head2 get_webmail_analytics_data()

Retrieves information that is specific to webmail user interfaces in addition to common analytics data.

=head3 RETURNS

A hashref of the following key, value pairs.

=over

=item product_interface - string

Should be set to Webmail.

=back

=head3 NOTE

UUID may need to be adjusted here because webmail user data is stored differently.

=cut

sub get_webmail_analytics_data {
    my %analytics_data = (
        %{ _get_common_analytics_data() },
        'product_interface' => 'Webmail',
    );

    my ( $login, $domain );

    ( $login, $domain ) = split( /\@/, $ENV{'REMOTE_USER'} ) if $ENV{'REMOTE_USER'} =~ m/\@/;

    if ( $login && ( $login ne $Cpanel::user ) ) {
        my $popdb;
        eval {
            require Cpanel::Email::Accounts;
            $popdb = Cpanel::Email::Accounts::manage_email_accounts_db( 'event' => 'fetch' );
        };
        if ($popdb) {
            my $uuid = $popdb->{$domain}->{'accounts'}->{$login}->{'UUID'};
            $analytics_data{'UUID'} = $uuid if $uuid;
        }
    }

    return \%analytics_data;
}

=head2 get_email_id_for_retently_embed()

Retently embed requires an email id to differentiate accounts. It does not have to be a
working email but should be in a valid email format.
Following the pseudonymization standard, we decided to use the uuid and server hostname
to form a unique email id specifically for Retently in app survey embed.

=head3 RETURNS

An email Id.

=over

Parameters:

=over

=item UUID - string

The cpanel account's unique identifier.

=back

=back

=cut

sub get_email_id_for_retently_embed {
    my ( $self, $uuid ) = @_;
    return () if !$uuid;

    require Cpanel::Sys::Hostname;
    my $hostname = Cpanel::Sys::Hostname::gethostname();
    return $uuid . "@" . $hostname;
}

=head2 _get_account_data

Retrieves information needed for tracking user account data.

=head3 RETURNS

A hashref of the following key, value pairs.

=over

=item UUID - string

A unique identifier of the user.

=item UUID_ADDED_AT_ACCOUNT_CREATION - boolean

Whether the UUID is generated when the account is created.

=item TRANSFERRED_OR_RESTORED - numeric

Starts at 0 when first added to an account and is incremented by 1 at the destination of the next transfer or restore from backup.

=item INITIAL_SERVER_ENV_TYPE - string

The licensed server environment type when the migration data is generated.

=item INITIAL_SERVER_LICENSE_TYPE - numeric

The type of server license when the migration data is generated. At this time this is simply the licensed user count (0 is unlimited).

=item ACCOUNT_AGE - numeric

The number of days from account's creation to the current date.

=back

=cut

sub _get_account_data {
    my $user = $Cpanel::user || $ENV{REMOTE_USER};

    # dummy user for building whm chrome
    return () if $ENV{'REMOTE_USER'} && $ENV{'REMOTE_USER'} eq 'cpuser00000000000';
    return () unless $user && $user ne 'root';

    my @migration_keys = (
        'UUID',
        'UUID_ADDED_AT_ACCOUNT_CREATION',
        'TRANSFERRED_OR_RESTORED',
        'INITIAL_SERVER_ENV_TYPE',
        'INITIAL_SERVER_LICENSE_TYPE'
    );

    my $cpuser_data = \%Cpanel::CPDATA;

    unless ( $cpuser_data->{'OWNER'} ) {
        eval {
            require Cpanel::Config::LoadCpUserFile;
            $cpuser_data = Cpanel::Config::LoadCpUserFile::loadcpuserfile($user);
        }
    }
    return () unless $cpuser_data;

    my $account_age = ( $cpuser_data->{'STARTDATE'} ) ? _get_account_age( $cpuser_data->{'STARTDATE'} ) : 0;

    my %account_data = (
        %{$cpuser_data}{@migration_keys},
        'ACCOUNT_AGE' => $account_age
    );
    return %account_data;
}

=head2 _get_account_age()

Calculates the age of an account in days.

=head3 RETURNS

A numeric integer representing the number of days since the account's creation.

=over

Parameters:

=over

=item start_date - numeric

The epoch value of Account's creation date.

=back

=back

=cut

sub _get_account_age {
    my ($start_date) = (@_);
    require DateTime;

    my $start_date_obj = DateTime->from_epoch( epoch => $start_date );
    my $today_date_obj = DateTime->now();
    return 0 if ( $start_date_obj > $today_date_obj );
    my $account_age = $start_date_obj->delta_days($today_date_obj)->in_units('days');

    return $account_age;
}

=head2 _get_root_age()

Calculates the age of the root account in days. Since root is not an actual account,
the age of a cpanel install file is used to determine the age.

=head3 RETURNS

A numeric integer representing the number of days since the cpanel install.

=cut

sub _get_root_age {
    my $cp_install_dir = "/var/cpanel/install_version";
    if ( !$Cpanel::Template::Plugin::UIAnalytics::root_creation_date ) {
        $Cpanel::Template::Plugin::UIAnalytics::root_creation_date = `stat --printf=%W $cp_install_dir`;
    }
    return _get_account_age($Cpanel::Template::Plugin::UIAnalytics::root_creation_date);
}

1;
