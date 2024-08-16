package Cpanel::Template::Plugin::Analytics;

# cpanel - SOURCES/Analytics.pm                    Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# MINIMUM_VERSION_SUPPORTED == 11.86

use strict;
use warnings;

use base 'Template::Plugin';

our $CPANEL_ANALYTICS_VERSION = "1.4.46-1";

=encoding utf-8

=head1 NAME

Cpanel::Template::Plugin::Analytics - Plugin to gather information for analytics.

=head1 DESCRIPTION
ATTENTION: This module is B<DEPRECATED> and should no longer be used in the cPanel & WHM code base.
Use L<Cpanel::Template::Plugin::UIAnalytics> module instead.

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
    my %subs2eval = (
        'company_id'                  => sub { require Cpanel::License::CompanyID;  Cpanel::License::CompanyID::get_company_id() },
        'product_locale'              => sub { require Cpanel::Locale::Utils::User; Cpanel::Locale::Utils::User::get_user_locale() },
        'product_version'             => sub { require Cpanel::Version;             Cpanel::Version::get_version_display() },
        'product_trial_status'        => sub { require Cpanel::License::Flags;      Cpanel::License::Flags::has_flag('trial') ? 'true' : 'false' },
        'server_current_license_kind' => sub { require Cpanel::Server::Type;        Cpanel::Server::Type::get_producttype() },
        'server_main_ip'              => sub { require Cpanel::DIp::MainIP;         require Cpanel::NAT; Cpanel::NAT::get_public_ip( Cpanel::DIp::MainIP::getmainip() ) },
        'server_operating_system'     => sub { require Cpanel::OS;                  Cpanel::OS::display_name() },
        'is_nat'                      => sub { require Cpanel::NAT;                 Cpanel::NAT::is_nat() },
    );
    my %analytics_data = (
        _get_migration_data(),
        'analytics_distribution' => 'cp-analytics',
        map {
            local $@;
            my $key = $_;
            my $val = eval { $subs2eval{$key}->() };
            $@ ? ( $key => 'N/A' ) : ( $key => $val );
        } keys(%subs2eval)
    );

    # This depends on a previous variable so we have to do it after the fact.
    $analytics_data{'server_main_ip_is_private'} = eval {
        require Cpanel::Ips;
        Cpanel::Ips::is_private( $analytics_data{'server_main_ip'} ) ? 1 : 0;
    } // 'N/A';    # 2 means this failed or we couldn't determine it.

    $analytics_data{'analytics_version'} = $CPANEL_ANALYTICS_VERSION;
    return \%analytics_data;
}

=head2 get_whm_analytics_data()
ATTENTION: This method is B<DEPRECATED> and should no longer be used in the cPanel & WHM code base.
Use the method provided by L<Cpanel::Template::Plugin::UIAnalytics> module instead.

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
            $analytics_data{'UUID'} = Cpanel::UUID::Server::get_server_uuid();
        }
    }

    return \%analytics_data;
}

=head2 get_cpanel_analytics_data()
ATTENTION: This method is B<DEPRECATED> and should no longer be used in the cPanel & WHM code base.
Use the method provided by L<Cpanel::Template::Plugin::UIAnalytics> module instead.

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
ATTENTION: This method is B<DEPRECATED> and should no longer be used in the cPanel & WHM code base.
Use the method provided by L<Cpanel::Template::Plugin::UIAnalytics> module instead.

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

=head2 _get_migration_data

Retrieves information needed for tracking user migration.

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

=back

=cut

sub _get_migration_data {
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

    return %{$cpuser_data}{@migration_keys};
}

1;
