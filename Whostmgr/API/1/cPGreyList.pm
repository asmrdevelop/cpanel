package Whostmgr::API::1::cPGreyList;

# cpanel - Whostmgr/API/1/cPGreyList.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

use Cpanel::Math              ();
use Cpanel::Locale            ();
use Cpanel::ForkAsync         ();
use Cpanel::Exception         ();
use Cpanel::ServerTasks       ();
use Cpanel::IP::GreyList      ();
use Cpanel::SafeRun::Errors   ();
use Cpanel::GreyList::Config  ();
use Cpanel::GreyList::Client  ();
use Cpanel::Chkservd::Manage  ();
use Cpanel::Services::Enabled ();

use constant NEEDS_ROLE => {
    cpgreylist_is_server_netblock_trusted               => undef,
    cpgreylist_list_entries_for_common_mail_provider    => undef,
    cpgreylist_load_common_mail_providers_config        => undef,
    cpgreylist_save_common_mail_providers_config        => undef,
    cpgreylist_status                                   => undef,
    cpgreylist_trust_entries_for_common_mail_provider   => undef,
    cpgreylist_untrust_entries_for_common_mail_provider => undef,
    create_cpgreylist_trusted_host                      => undef,
    delete_cpgreylist_trusted_host                      => undef,
    disable_cpgreylist                                  => undef,
    enable_cpgreylist                                   => undef,
    load_cpgreylist_config                              => undef,
    read_cpgreylist_deferred_entries                    => undef,
    read_cpgreylist_trusted_hosts                       => undef,
    save_cpgreylist_config                              => undef,
};

=head1 NAME

Whostmgr::API::1::cPGreyList - API to help manage the cPGreyList service.

=head1 SYNOPSIS

    use Whostmgr::API::1::cPGreyList ();
    my $status = Whostmgr::API::1::cPGreyList::cpgreylist_status();
    if ( $status->{'is_exim_enabled'} && not $status->{'is_enabled'} ) {
        Whostmgr::API::1::cPGreyList::enable_cpgreylist();
    }

=cut

my $locale;

=head1 Methods

=over 8

=item B<cpgreylist_status>

Returns the status of the cPGreyList service.

Additionally returns 'is_exim_enabled' to indicate whether or not exim is disabled on the server.

B<Input>: None.

B<Output>:

    {
        'service'    => 'cPGreyList'
        'is_enabled' => 0 or 1,
        'is_exim_enabled' => 0 or 1
    }

=cut

sub cpgreylist_status {
    my ( undef, $metadata ) = @_;

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    return {
        'service'         => 'cPGreyList',
        'is_enabled'      => Cpanel::GreyList::Config::is_enabled(),
        'is_exim_enabled' => Cpanel::Services::Enabled::is_enabled('exim'),
    };
}

=item B<enable_cpgreylist>

Enables the cPGreyList service.

Call will fail if the 'exim' service is disabled on the server.

B<Input>: a hashref (used to set the proper metadata).

B<Output>: None. Alters the hashref (C<$metadata>) to indicate success or failure.

=cut

sub enable_cpgreylist {
    my ( undef, $metadata ) = @_;

    _initialize();
    if ( !Cpanel::Services::Enabled::is_enabled('exim') ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext('Failed to enable [asis,cPGreyList]: [asis,Exim] is disabled on the server');
        return;
    }

    my $output;
    if ( !Cpanel::GreyList::Config::is_enabled() ) {
        if ( Cpanel::GreyList::Config::enable() ) {
            $metadata->{'result'} = 1;
            $metadata->{'reason'} = 'OK';
            _reset_services();
        }
        else {
            $metadata->{'result'} = 0;
            $metadata->{'reason'} = $locale->maketext( 'Failed to enable [asis,cPGreyList]: [_1]', $! );
        }
    }
    else {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = $locale->maketext('[asis,cPGreyList] is already enabled.');
    }
    return $output;
}

=item B<disable_cpgreylist>

Disables the cPGreyList service.

B<Input>: a hashref (used to set the proper metadata).

B<Output>: None. Alters the hashref (C<$metadata>) to indicate success or failure.

=cut

sub disable_cpgreylist {
    my ( undef, $metadata ) = @_;

    _initialize();
    if ( Cpanel::GreyList::Config::is_enabled() ) {
        if ( Cpanel::GreyList::Config::disable() ) {

            # CPANEL-6920: Remove the chksrvd monitoring automatically
            # when the service is disabled.
            $metadata->{'result'} = 1;
            $metadata->{'reason'} = 'OK';
            Cpanel::Chkservd::Manage::disable('cpgreylistd');
            _reset_services(1);
        }
        else {
            $metadata->{'result'} = 0;
            $metadata->{'reason'} = $locale->maketext( 'Failed to disable [asis,cPGreyList]: [_1]', $! );
        }
    }
    else {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = $locale->maketext('[asis,cPGreyList] is already disabled.');
    }
    return;
}

=item B<create_cpgreylist_trusted_host>

Creates a new Trusted Hosts entry. Emails from trusted hosts are not greylisted.

B<Input>: Takes two hashrefs. The second hashref should be a reference to the C<$metadata>.

The first hashref should contain information related to the new entries being created:

    ip        => The IPs to create new entries for. These can be single IPs, CIDRs, or IP ranges.
                 NOTE:
                    Given how C<legacy_parse_query_string_sr> works, if you specify multiple IPs in the URI,
                    like C</json-api/create_cpgreylist_trusted_host?api.version=1&ip=2.1.34.4&ip=2.3.3.4>, then they
                    are parsed as "ip=2.1.34.4", and "ip-0=2.3.3.4".
    comment   => The comment to tag the IPs with.

B<Output>: A hashref containing the details of the operation. The 'result' and 'reason' are set
in the C<$metadata> accordingly.

    {
        'ips_added' => [
            ...
            $ip1,
            $ip2,
            ...
        ],
        'ips_failed' => {
            ...
            $ip1_that_failed => 'possible reason for failure',
            $ip2_that_failed => 'possible reason for failure',
            ...
        },
        'comment' => 'a possibly empty string',
    }

If the cPGreyList service is disabled, then C<undef> is returned.

=cut

sub create_cpgreylist_trusted_host {
    my ( $args, $metadata ) = @_;

    _initialize();
    if ( !Cpanel::GreyList::Config::is_enabled() ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext('[asis,cPGreyList] is disabled on the server.');
        return;
    }

    my $client = Cpanel::GreyList::Client->new();

    my $comment    = delete $args->{'comment'};
    my $ips_to_add = _parse_ips($args);
    my $ips_failed = {};
    my @ips_added;

    foreach my $ip ( @{$ips_to_add} ) {
        try {
            if ( my $reply = $client->create_trusted_host( $ip, $comment ) ) {
                push @ips_added, $reply;
            }
        }
        catch {
            $ips_failed->{$ip} = Cpanel::Exception::get_string($_);
        };
    }

    if ( scalar @ips_added ) {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';
        Cpanel::ForkAsync::do_in_child(
            sub {
                Cpanel::IP::GreyList::update_trusted_netblocks_or_log();    # Its ok if this fails, it just means they will get a 20s connect delay if enabled.
            }
        );
    }
    else {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext('No trusted hosts added.');
    }

    return { 'ips_added' => \@ips_added, 'ips_failed' => $ips_failed, 'comment' => ( $comment || '' ) };
}

=item B<read_cpgreylist_trusted_hosts>

Returns a list of Trusted Hosts.

B<Input>: a hashref (used to set the proper metadata).

B<Output>: A hashref containing the details of the trusted hosts:

    {
        "greylist_trusted_hosts" => [
            ...
            {
                "comment" => "my comment",
                "create_time" => "2015-02-19 10:37:28",
                "id" => 8,
                "host_ip" => "1.2.3.4"
            },
            {
                "comment" => "my comment also",
                "create_time" => "2015-02-19 10:38:28",
                "id" => 9,
                "host_ip" => "2.3.4.5"
            }
            ...
        ]
    }

Returns undef, and sets the 'result' and 'reason' values in the C<$metadata> hash accordingly on failure.

=cut

sub read_cpgreylist_trusted_hosts {
    my ( undef, $metadata ) = @_;

    _initialize();
    if ( !Cpanel::GreyList::Config::is_enabled() ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext('[asis,cPGreyList] is disabled on the server.');
        return;
    }
    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    my $trusted_hosts;
    try {
        my $client = Cpanel::GreyList::Client->new();
        $trusted_hosts = $client->read_trusted_hosts() || {};
    }
    catch {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext( 'Failed to read [asis,cPGreyList] trusted hosts: [_1]', Cpanel::Exception::get_string($_) );
    };
    return if !$metadata->{'result'};

    return { 'greylist_trusted_hosts' => $trusted_hosts };
}

=item B<delete_cpgreylist_trusted_host>

Deletes the specified IPs from the Trusted Hosts list.

B<Input>: Takes two hashrefs. The second hashref should be a reference to the C<$metadata>.

The first hashref should contain information related to the new entries being created:

    ip => The IPs to delete. See note in C<create_cpgreylist_trusted_host>

B<Output>: A hashref containing the details of the operation. The 'result' and 'reason' are set
in the C<$metadata> accordingly.

    {
        'ips_removed' => [
            ...
            $ip1,
            $ip2,
            ...
        ],
        'ips_failed' => {
            ...
            $ip1_that_failed => 'possible reason for failure',
            $ip2_that_failed => 'possible reason for failure',
            ...
        },
    }

If the cPGreyList service is disabled, then C<undef> is returned.

=cut

sub delete_cpgreylist_trusted_host {
    my ( $args, $metadata ) = @_;

    _initialize();
    if ( !Cpanel::GreyList::Config::is_enabled() ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext('[asis,cPGreyList] is disabled on the server.');
        return;
    }

    my $client = Cpanel::GreyList::Client->new();

    my $ips_to_remove = _parse_ips($args);
    my $ips_failed    = {};
    my @ips_removed;

    foreach my $ip ( @{$ips_to_remove} ) {
        try {
            if ( $client->delete_trusted_host($ip) ) {
                push @ips_removed, $ip;
            }
        }
        catch {
            $ips_failed->{$ip} = Cpanel::Exception::get_string($_);
        };
    }

    if ( scalar @ips_removed ) {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';
        Cpanel::ForkAsync::do_in_child(
            sub {
                Cpanel::IP::GreyList::update_trusted_netblocks_or_log();    # Its ok if this fails, it just means they will get a 20s connect delay if enabled.
            }
        );
    }
    else {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext('No trusted hosts deleted.');
    }

    return { 'ips_removed' => \@ips_removed, 'ips_failed' => $ips_failed };
}

=item B<cpgreylist_is_server_netblock_trusted>

Determines if the network block that the server's main IP is in
has been added to the 'trusted hosts' list or not.

B<Input>: a hashref (used to set the proper metadata).

B<Output>: A hashref containing details of the IP ranges that the server's IPs belong to:

    {
        'ip_blocks' => {
            ...
            $ip_range1 => 1 or 0 (1 if the range is trusted, 0 if the range is not trusted),
            $ip_range2 => 1 or 0,
            ...
        },
    }

Returns undef, and sets the 'result' and 'reason' values in the C<$metadata> hash accordingly on failure.

=cut

sub cpgreylist_is_server_netblock_trusted {
    my ( undef, $metadata ) = @_;

    _initialize();
    if ( !Cpanel::GreyList::Config::is_enabled() ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext('[asis,cPGreyList] is disabled on the server.');
        return;
    }
    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    my $netblocks_hr;
    try {
        $netblocks_hr = _fetch_whois_cidrs_for_all_ips_on_server();
        die "WHOIS lookup failed\n" if !$netblocks_hr || !( 'HASH' eq ref $netblocks_hr && scalar keys %{$netblocks_hr} );

        my $client = Cpanel::GreyList::Client->new();

        # Note: verify_trusted_hosts() alters the hashref and
        # sets whether or not the cidr is trusted.
        # It will also 'convert' the cidrs into ip-ranges for easier usablity on the frontend.
        $client->verify_trusted_hosts( $netblocks_hr, 'send_raw_response' );
    }
    catch {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext( 'Failed to check if server netblock is added to the [asis,cPGreyList] trusted hosts: [_1]', Cpanel::Exception::get_string($_) );
    };
    return if !$metadata->{'result'};

    return { 'ip_blocks' => $netblocks_hr };
}

=item B<load_cpgreylist_config>

Returns the current cPGreyList configuration settings.

B<Input>: The first argument is ALWAYS discarded. The second argument should be a hashref for the c<$metadata>.

B<Output>:

A hashref containing the details about the current configuration:

    {
        "cpgreylist_config" => {
            "is_enabled" => "1",
            "child_timeout_secs" => "5",
            "record_exp_time_mins" => "1440",
            "is_exim_enabled" => 1,
            "initial_block_time_mins" => "1",
            "max_child_procs" => "5",
            "purge_interval_mins" => "60",
            "must_try_time_mins" => "5"
        }
    }

Returns undef, and sets the 'result' and 'reason' values in the C<$metadata> hash accordingly on failure.

=cut

sub load_cpgreylist_config {
    my ( undef, $metadata ) = @_;

    _initialize();
    my $config;
    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    try {
        $config = Cpanel::GreyList::Config::loadconfig();
    }
    catch {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext( 'Failed to read [asis,cPGreyList] configuration: [_1]', $_ );
    };
    return if !$metadata->{'result'};
    $config->{'is_exim_enabled'} = Cpanel::Services::Enabled::is_enabled('exim');

    return { 'cpgreylist_config' => $config };
}

=item B<save_cpgreylist_config>

Modifies the cPGreyList configuration settings as specified.

B<Input>: Takes two hashrefs. The second hashref should be a reference to the C<$metadata>.

The first hashref should contain information related to the settings being altered. Valid keys are:

    "initial_block_time_mins" => Number of minutes the initial block will last for a previously unknown triplet.
    "must_try_time_mins" => Number of minutes the triplet has to "retry".
                            If the triplet does not send another email within time period,
                            then the record is removed, and the greylisting cycle starts from the beginning.
    "record_exp_time_mins" => Number of minutes the records for triplets that have retried within the 'must_try_time_mins' time are kept.
                              Mail from these triplets is not greylisted as long the record exists.

B<Output>:

A hashref containing the details about the current configuration:

    {
        "cpgreylist_config" => {
            "is_enabled" => "1",
            "child_timeout_secs" => "5",
            "record_exp_time_mins" => "1440",
            "is_exim_enabled" => 1,
            "initial_block_time_mins" => "5",
            "max_child_procs" => "5",
            "purge_interval_mins" => "60",
            "must_try_time_mins" => "5"
        }
    }

Returns undef, and sets the 'result' and 'reason' values in the C<$metadata> hash accordingly on failure.

=cut

sub save_cpgreylist_config {
    my ( $args, $metadata ) = @_;

    _initialize();
    if ( !Cpanel::GreyList::Config::is_enabled() ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext('[asis,cPGreyList] is disabled on the server.');
        return;
    }

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    try {
        Cpanel::GreyList::Config::saveconfig($args);
    }
    catch {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext( 'Failed to save [asis,cPGreyList] configuration: [_1]', Cpanel::Exception::get_string($_) );
    };
    return if !$metadata->{'result'};

    if ( my $output = load_cpgreylist_config( undef, $metadata ) ) {

        _reset_services();
        return $output;
    }

    $metadata->{'result'} = 0;
    $metadata->{'reason'} = $locale->maketext('Failed to read [asis,cPGreyList] configuration after saving.');
    return;
}

=item B<read_cpgreylist_deferred_entries>

Returns the requested set of deferred triplet entries.

B<Input>: Takes two hashrefs. The second hashref should be a reference to the C<$metadata>.

The first hashref should contain the sort, filter and paginate options.

To control the sorting, the first hashref should contain:

    {
        'sort' => {
            'enable' => 1,
            'a' => {
                'field'   => column name to sort by. Default => 'id',
                'reverse' => 1 for DESC order, 0 for ASC order. Default => '0',
            }
        }
    }

To control the filtering, the first hashref should contain:

    {
        'filter' => {
            'enable' => 1,
            'a' => {
                'arg0' => String to match email addresses on, or full IP addresses to match
            }
        }
    }

To control the pagination, the first hashref should contain:

    {
        'chunk' => {
            'enable' => 1,
            'size'   => Number of elements to fetch. Default = 20,
            'start'  => The offset to use. Default = 0,
        }
    }

B<Output>: A hashref containing the requested set of data:

    {
        "total_rows" => 1,
        "limit" => 20,
        "offset" => 0,
        "greylist_deferred_entries" => [
            {
                "create_time" => "2015-02-19 13=>24=>54",
                "accepted_count" => 0,
                "block_exp_time" => "2015-02-19 13=>29=>54",
                "from_addr" => "wlnpbnni@eqqdy.ddd",
                "record_exp_time" => "2015-02-20 13=>24=>54",
                "to_addr" => "bonvljaj@qejpn.lds",
                "must_retry_by" => "2015-02-19 13=>29=>54",
                "deferred_count" => 1,
                "sender_ip" => "30.27.32.161",
                "id" => 6027
            }
        ],
   }

Returns undef, and sets the 'result' and 'reason' values in the C<$metadata> hash accordingly on failure.

=cut

sub read_cpgreylist_deferred_entries {
    my ( undef, $metadata, $api_args ) = @_;

    _initialize();
    if ( !Cpanel::GreyList::Config::is_enabled() ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext('[asis,cPGreyList] is disabled on the server.');
        return;
    }
    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    # TODO: Look into using Whostmgr::API::1::Data::MysqlQueryBuilder instead of parsing
    # api_args directly.
    my $args = _parse_api_args($api_args);

    my $deferred_list;
    try {
        my $client = Cpanel::GreyList::Client->new();
        $deferred_list = $client->get_deferred_list($args) || {};
    }
    catch {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext( 'Failed to read [asis,cPGreyList] deferred list: [_1]', Cpanel::Exception::get_string($_) );
    };
    return if !$metadata->{'result'};

    my ( $start, $size ) = @{ $api_args->{chunk} }{qw(start size)};
    if ($size) {
        $metadata->{chunk} = {
            'start'   => $start,
            'size'    => $size,
            'records' => $deferred_list->{'total_rows'},
            'chunks'  => Cpanel::Math::ceil( $deferred_list->{'total_rows'} / $size ),
            'current' => Cpanel::Math::ceil( $start / $size ),
        };
    }

    if ( exists $api_args->{filter} ) {
        $metadata->{filter} = {
            %{ $api_args->{filter} },
            'filtered' => $deferred_list->{'total_rows'},
        };
    }

    $api_args->{'sort'}{'a'}{'__done'} = 1;    # Prevent sort by xml-api. See Whostmgr::API::1::Data::Sort::_get_sort_func_list()
    $metadata->{__chunked}             = 1;    # Prevent pagination by xml-api
    $metadata->{__filtered}            = 1;    # Prevent filtering by xml-api

    require Time::Piece;
    my $t = Time::Piece->new();
    return {
        'greylist_deferred_entries' => $deferred_list->{'data'},
        'limit'                     => $args->{'limit'},
        'offset'                    => $args->{'offset'},
        'total_rows'                => $deferred_list->{'total_rows'},
        'server_tzoffset'           => $t->tzoffset()->minutes(),
        'server_timezone'           => $t->strftime("%Z"),
    };
}

=item B<cpgreylist_load_common_mail_providers_config>

Returns the current cPGreyList "Common Mail Providers" configuration settings.

B<Input>: The first argument is ALWAYS discarded. The second argument should be a hashref for the c<$metadata>.

B<Output>:

A hashref containing the details about the current configuration for the common mail providers
that are maintained by cPanel, and kept updated on the system:

    {
        "autotrust_new_common_mail_providers": 1,
        "common_mail_providers": {
            ...
            "google": {
                "display_name": "Google",
                "autoupdate": 1
            },
            "outlook": {
                "display_name": "Outlook",
                "autoupdate": 0
            },
            ...
        }
    }

Returns undef, and sets the 'result' and 'reason' values in the C<$metadata> hash accordingly on failure.

=cut

sub cpgreylist_load_common_mail_providers_config {
    my ( undef, $metadata ) = @_;

    _initialize();
    if ( !Cpanel::GreyList::Config::is_enabled() ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext('[asis,cPGreyList] is disabled on the server.');
        return;
    }

    my $output;
    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    try {
        require Cpanel::GreyList::CommonMailProviders::Config;
        $output = Cpanel::GreyList::CommonMailProviders::Config::load();
        $output->{'common_mail_providers'} = delete $output->{'provider_properties'};
    }
    catch {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext( 'Failed to read [asis,cPGreyList] Common Mail Providers configuration: [_1]', Cpanel::Exception::get_string($_) );
    };
    return if !$metadata->{'result'};

    return $output;
}

=item B<cpgreylist_save_common_mail_providers_config>

Modifies the cPGreyList "Common Mail Providers" configuration settings as specified.

B<Input>: Takes two hashrefs. The second hashref should be a reference to the C<$metadata>.

The first hashref should contain information related to the settings being altered. Valid keys are:

    * 'autotrust_new_common_mail_providers'
    * Names of any of the mail providers listed in the c<common_mail_providers> hash
      in the c<cpgreylist_load_common_mail_providers_config> output

B<Output>:

A hashref containing the details about the current configuration:

    cpgreylist_save_common_mail_providers_config( { 'google' => 0, 'outlook' => 1 }, $metadata );

    {
        "autotrust_new_common_mail_providers": 1,
        "common_mail_providers": {
            ...
            "google": {
                "display_name": "Google",
                "autoupdate": 0
            },
            "outlook": {
                "display_name": "Outlook",
                "autoupdate": 1
            },
            ...
        }
    }

Returns undef, and sets the 'result' and 'reason' values in the C<$metadata> hash accordingly on failure.

=cut

sub cpgreylist_save_common_mail_providers_config {
    my ( $args, $metadata ) = @_;

    _initialize();
    if ( !Cpanel::GreyList::Config::is_enabled() ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext('[asis,cPGreyList] is disabled on the server.');
        return;
    }

    my $filtered_args;
    my $providers_in_db = Cpanel::GreyList::Client->new()->get_common_mail_providers();
    foreach my $key ( keys %{$args} ) {
        next if $key ne 'autotrust_new_common_mail_providers' && not exists $providers_in_db->{$key};
        $filtered_args->{$key} = $args->{$key};
    }

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    try {
        Cpanel::GreyList::Config::save_common_mail_providers_config( { map { $_ => 1 } keys %{$providers_in_db} }, $filtered_args );    ## no critic qw(ProhibitVoidMap)
    }
    catch {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext( 'Failed to save [asis,cPGreyList] Common Mail Providers configuration: [_1]', Cpanel::Exception::get_string($_) );
    };
    return if !$metadata->{'result'};

    if ( my $output = cpgreylist_load_common_mail_providers_config( undef, $metadata ) ) {
        return $output;
    }

    $metadata->{'result'} = 0;
    $metadata->{'reason'} = $locale->maketext('Failed to read [asis,cPGreyList] Common Mail Providers configuration after saving.');
    return;
}

=item B<cpgreylist_trust_entries_for_common_mail_provider>

Marks the IPs for the specified common mail providers as 'trusted'.
Emails from these IPs are considered to be trusted, and are no longer greylisted.

B<Input>: Takes two hashrefs. The second hashref should be a reference to the C<$metadata>.

The first hashref should contain information related to the providers being altered:

    provider     => The common mail provider to trust.
                 NOTE:
                    Given how C<legacy_parse_query_string_sr> works, if you specify multiple providers in the URI,
                    like C</json-api/cpgreylist_trust_entries_for_common_mail_provider?api.version=1&provider=aol&provider=yahoo>,
                    then they are parsed as "provider=aol", and "provider-0=yahoo".

B<Output>: A hashref containing the details of the operation. The 'result' and 'reason' are set
in the C<$metadata> accordingly.

    {
        'providers_trusted' => {
            ...
            'provider1' => { 'ips_trusted' => $number_of_ips_trusted },
            ...
        },
        'providers_failed' => {
            ...
            $provider1_that_failed => 'possible reason for failure',
            $provider2_that_failed => 'possible reason for failure',
            ...
        },
    }

If the cPGreyList service is disabled, then C<undef> is returned.

=cut

sub cpgreylist_trust_entries_for_common_mail_provider {
    my ( $args, $metadata ) = @_;

    _initialize();
    if ( !Cpanel::GreyList::Config::is_enabled() ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext('[asis,cPGreyList] is disabled on the server.');
        return;
    }

    my $client                       = Cpanel::GreyList::Client->new();
    my $valid_list_of_mail_providers = $client->get_common_mail_providers();

    my $providers_to_trust = _parse_providers($args);
    my $providers_failed   = {};
    my $providers_trusted  = {};

    foreach my $provider ( @{$providers_to_trust} ) {
        $provider = lc $provider;
        try {
            die "Unknown mail provider: $provider\n" if not exists $valid_list_of_mail_providers->{$provider};

            if ( my $reply = $client->trust_entries_for_common_mail_provider($provider) ) {
                $providers_trusted->{$provider}->{'ips_trusted'} = $reply;
            }
        }
        catch {
            $providers_failed->{$provider} = Cpanel::Exception::get_string($_);
        };
    }

    if ( scalar keys %{$providers_trusted} ) {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';
        Cpanel::ForkAsync::do_in_child(
            sub {
                Cpanel::IP::GreyList::update_common_mail_providers_or_log();    # Its ok if this fails, it just means they will get a 20s connect delay if enabled.
            }
        );
    }
    else {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext('The system failed to trust any [asis,IP] addresses.');
    }

    return { 'providers_trusted' => $providers_trusted, 'providers_failed' => $providers_failed };
}

=item B<cpgreylist_untrust_entries_for_common_mail_provider>

Marks the IPs for the specified common mail providers as 'untrusted'.
Emails from these IPs are considered to be untrusted, and will be greylisted.

B<Input>: Takes two hashrefs. The second hashref should be a reference to the C<$metadata>.

The first hashref should contain information related to the providers being altered:

    provider     => The common mail provider to untrust.
                 NOTE:
                    Given how C<legacy_parse_query_string_sr> works, if you specify multiple providers in the URI,
                    like C</json-api/cpgreylist_untrust_entries_for_common_mail_provider?api.version=1&provider=aol&provider=yahoo>,
                    then they are parsed as "provider=aol", and "provider-0=yahoo".

B<Output>: A hashref containing the details of the operation. The 'result' and 'reason' are set
in the C<$metadata> accordingly.

    {
        'providers_untrusted' => {
            ...
            'provider1' => { 'ips_untrusted' => $number_of_ips_trusted },
            ...
        },
        'providers_failed' => {
            ...
            $provider1_that_failed => 'possible reason for failure',
            $provider2_that_failed => 'possible reason for failure',
            ...
        },
    }

If the cPGreyList service is disabled, then C<undef> is returned.

=cut

sub cpgreylist_untrust_entries_for_common_mail_provider {
    my ( $args, $metadata ) = @_;

    _initialize();
    if ( !Cpanel::GreyList::Config::is_enabled() ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext('[asis,cPGreyList] is disabled on the server.');
        return;
    }

    my $client                       = Cpanel::GreyList::Client->new();
    my $valid_list_of_mail_providers = $client->get_common_mail_providers();

    my $providers_to_untrust = _parse_providers($args);
    my $providers_failed     = {};
    my $providers_untrusted  = {};

    foreach my $provider ( @{$providers_to_untrust} ) {
        $provider = lc $provider;
        try {
            die "Unknown mail provider: $provider\n" if not exists $valid_list_of_mail_providers->{$provider};

            if ( my $reply = $client->untrust_entries_for_common_mail_provider($provider) ) {
                $providers_untrusted->{$provider}->{'ips_untrusted'} = $reply;
            }
        }
        catch {
            $providers_failed->{$provider} = Cpanel::Exception::get_string($_);
        };
    }

    if ( scalar keys %{$providers_untrusted} ) {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';
        Cpanel::ForkAsync::do_in_child(
            sub {
                Cpanel::IP::GreyList::update_common_mail_providers_or_log();    # Its ok if this fails, it just means they will get a 20s connect delay if enabled.
            }
        );
    }
    else {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext('The system failed to untrust any [asis,IP] addresses.');
    }

    return { 'providers_untrusted' => $providers_untrusted, 'providers_failed' => $providers_failed };
}

=item B<cpgreylist_list_entries_for_common_mail_provider>

Lists the IPs for the specified common mail providers..

B<Input>: Takes two hashrefs. The second hashref should be a reference to the C<$metadata>.

The first hashref should contain information related to the providers being listed:

    provider     => The common mail provider to list the IPs for.
                 NOTE:
                    Given how C<legacy_parse_query_string_sr> works, if you specify multiple providers in the URI,
                    like C</json-api/cpgreylist_untrust_entries_for_common_mail_provider?api.version=1&provider=aol&provider=yahoo>,
                    then they are parsed as "provider=aol", and "provider-0=yahoo".

B<Output>: A hashref containing the details of the operation. The 'result' and 'reason' are set
in the C<$metadata> accordingly.

    {
        "providers" => {
            "provider 1" => {
                "ips" => [
                    ...
                    {
                        "is_trusted" => 0,
                        "create_time" => "2015-07-24 15:18:40",
                        "host_ip" => "204.29.186.0-204.29.186.63"
                        "provider_id" => 4,
                    },
                    {
                        "is_trusted" => 0,
                        "create_time" => "2015-07-24 15:18:40",
                        "host_ip" => "204.29.186.64-204.29.186.95",
                        "provider_id" => 4,
                    },
                    ...
                ],
            },
            "provider 2" => {
                ...
            },
        },
        "providers_failed" => {
            "provider 3" => "Unknown mail provider: provider 3",
        }
    }

If the cPGreyList service is disabled, then C<undef> is returned.

=cut

sub cpgreylist_list_entries_for_common_mail_provider {
    my ( $args, $metadata ) = @_;

    _initialize();
    if ( !Cpanel::GreyList::Config::is_enabled() ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext('[asis,cPGreyList] is disabled on the server.');
        return;
    }

    my $client                       = Cpanel::GreyList::Client->new();
    my $valid_list_of_mail_providers = $client->get_common_mail_providers();

    my $providers_to_list = _parse_providers($args);
    my $providers_failed  = {};
    my $providers         = {};

    foreach my $provider ( @{$providers_to_list} ) {
        $provider = lc $provider;
        try {
            die "Unknown mail provider: $provider\n" if not exists $valid_list_of_mail_providers->{$provider};

            if ( my $reply = $client->list_entries_for_common_mail_provider($provider) ) {
                $providers->{$provider}->{'ips'} = $reply;
            }
        }
        catch {
            $providers_failed->{$provider} = Cpanel::Exception::get_string($_);
        };
    }

    if ( scalar keys %{$providers} ) {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';
    }
    else {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext('The specified providers are missing or invalid.');
    }

    return { 'providers' => $providers, 'providers_failed' => $providers_failed };
}

sub _fetch_whois_cidrs_for_all_ips_on_server {
    require Cpanel::Ips;
    require Cpanel::NAT;
    require Cpanel::Net::Whois::IP::Cached;

    my $public_ips;
    if ( Cpanel::NAT::is_nat() ) {
        $public_ips = Cpanel::NAT::get_all_public_ips();
    }
    else {
        $public_ips = [ map { $_->{'ip'} } @{ Cpanel::Ips::fetchifcfg() } ];
    }
    die "Failed to fetch public IPs on server\n" if !$public_ips || !( 'ARRAY' eq ref $public_ips and scalar @{$public_ips} );

    my $cidr_hr;
    foreach my $ip ( @{$public_ips} ) {
        my $whois_response = Cpanel::Net::Whois::IP::Cached->new()->lookup_address($ip) or next;

        # The cidr attribute is an array
        my $cidr_ar = $whois_response->get('cidr');
        next if !$cidr_ar || !( 'ARRAY' eq ref $cidr_ar and scalar @{$cidr_ar} );

        foreach my $cidr ( @{$cidr_ar} ) {
            $cidr_hr->{$cidr} = 0;
        }
    }
    return $cidr_hr;
}

sub _parse_api_args {
    my $api_args = shift;

    my $args = {};
    if ( 'HASH' eq ref $api_args->{'chunk'} && $api_args->{'chunk'}->{'enable'} ) {
        $args->{'limit'}  = $api_args->{'chunk'}->{'size'};
        $args->{'offset'} = $api_args->{'chunk'}->{'start'} - 1;
    }

    if ( 'HASH' eq ref $api_args->{'sort'} && $api_args->{'sort'}->{'enable'} ) {
        my $sort_params = $api_args->{'sort'}->{'a'};
        $args->{'order_by'} = $sort_params->{'field'};
        $args->{'order'}    = $sort_params->{'reverse'} ? 'DESC' : 'ASC';
    }

    if ( 'HASH' eq ref $api_args->{'filter'} && $api_args->{'filter'}->{'enable'} ) {
        my $filter_params = $api_args->{'filter'}->{'a'};
        $args->{'is_filter'} = 1;
        $args->{'column'}    = $filter_params->{'field'};
        $args->{'filter'}    = $filter_params->{'arg0'};
    }

    return $args;
}

sub _parse_ips {
    my $args = shift;
    my @ips  = map { $args->{$_} } grep { $_ =~ /^ip(\-\d+)?$/ } ( keys %{$args} );
    return \@ips;
}

sub _parse_providers {
    my $args      = shift;
    my @providers = map { $args->{$_} } grep { $_ =~ /^provider(\-\d+)?$/ } ( keys %{$args} );
    return \@providers;
}

sub _initialize {
    $locale ||= Cpanel::Locale->get_handle();
    return 1;
}

sub _reset_services {
    my $stop = shift;
    Cpanel::ServerTasks::queue_task( ['EximTasks'], 'buildeximconf --restart' );

    if ($stop) {
        Cpanel::SafeRun::Errors::saferunnoerror( '/usr/local/cpanel/scripts/restartsrv_cpgreylistd', '--stop', '--noverbose' );
    }
    else {
        Cpanel::ServerTasks::queue_task( ['CpServicesTasks'], "restartsrv cpgreylistd" );
        Cpanel::ForkAsync::do_in_child(
            sub {
                Cpanel::IP::GreyList::update_common_mail_providers_or_log();    # Its ok if this fails, it just means they will get a 20s connect delay if enabled.
            }
        );
    }
    return 1;
}

=back

=cut

1;
