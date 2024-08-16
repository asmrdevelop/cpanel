package Whostmgr::API::1::cPHulk;

# cpanel - Whostmgr/API/1/cPHulk.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Config::Hulk     ();
use Cpanel::Hulk::Admin      ();
use Whostmgr::API::1::Utils  ();
use Cpanel::Exception        ();
use Cpanel::XTables::TempBan ();

use constant NEEDS_ROLE => {
    cphulk_status                      => undef,
    create_cphulk_record               => undef,
    batch_create_cphulk_records        => undef,
    delete_cphulk_record               => undef,
    disable_cphulk                     => undef,
    enable_cphulk                      => undef,
    flush_cphulk_login_history         => undef,
    flush_cphulk_login_history_for_ips => undef,
    get_cphulk_brutes                  => undef,
    get_cphulk_excessive_brutes        => undef,
    get_cphulk_failed_logins           => undef,
    get_cphulk_user_brutes             => undef,
    load_cphulk_config                 => undef,
    read_cphulk_records                => undef,
    save_cphulk_config                 => undef,
    set_cphulk_config_key              => undef,
};

use Try::Tiny;

=encoding utf-8

=head1 NAME

Whostmgr::API::1::cPHulk - functions to help manage cPHulk

=head1 SYNOPSIS

    use Whostmgr::API::1::cPHulk ();

=cut

my $dbh;
my $locale;

=head1 Methods

=over 8

=item B<cphulk_status>

Returns the status of the cPHulk service.

B<Output>:

    {
        'service'    => 'cPHulk'
        'is_enabled' => 0 or 1
    }

=cut

sub cphulk_status {
    my ( undef, $metadata ) = @_;

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    return { 'service' => 'cPHulk', 'is_enabled' => ( Cpanel::Config::Hulk::is_enabled() ? 1 : 0 ) };
}

=item B<enable_cphulk>

Enables cPHulk on the server.

If 'UseDNS' is enabled in the SSHD configuration, then the SSH configuration is altered, and SSHD is restarted.

Prior to v84 this API call didn’t restart SSHD but instead asked the
caller to do so. As of v84 SSHD is restarted automatically, so
C<restart_ssh> in the return is always falsy.

    {
        "restart_ssh": 0,
        "warning": "…"
    }

Otherwise, sets C<$metadata> and returns C<undef>.

=cut

sub enable_cphulk {
    my ( undef, $metadata ) = @_;

    _initialize();
    my $output;
    if ( !Cpanel::Config::Hulk::is_enabled() ) {
        require Whostmgr::Services;
        if ( Whostmgr::Services::enable('cphulkd') ) {

            # flush internal caches of configuration state
            undef $Cpanel::Config::Hulk::Load::cphulkd_conf_cache_ref;
            undef $Cpanel::Config::Hulk::enabled_cache;
            my ( $warning_ssh, $restart_ssh ) = _incompatibility_warnings();
            if ($warning_ssh) {
                $output->{'warning'}     = $warning_ssh;
                $output->{'restart_ssh'} = $restart_ssh;
            }

            require Cpanel::Chkservd::Manage;
            Cpanel::Chkservd::Manage::enable('cphulkd');

            $metadata->{'result'} = 1;
            $metadata->{'reason'} = 'OK';
        }
        else {
            $metadata->{'result'} = 0;
            $metadata->{'reason'} = $locale->maketext( 'Failed to enable [asis,cPHulk]: [_1]', $! );
        }
    }
    else {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = $locale->maketext('[asis,cPHulk] is already enabled.');
    }
    return $output;
}

=item B<disable_cphulk>

Disables cPHulk on the server.

=cut

sub disable_cphulk {
    my ( undef, $metadata ) = @_;

    _initialize();
    if ( Cpanel::Config::Hulk::is_enabled() ) {
        require Whostmgr::Services;
        my ( $disabled, $error_msgs ) = Whostmgr::Services::disable('cphulkd');
        if ($disabled) {
            require Cpanel::Chkservd::Manage;
            Cpanel::Chkservd::Manage::disable('cphulkd');
            $metadata->{'result'} = 1;
            $metadata->{'reason'} = 'OK';
        }
        else {
            $metadata->{'result'} = 0;
            $metadata->{'reason'} = $locale->maketext( 'Failed to disable [asis,cPHulk]: [_1]', $error_msgs );
        }
    }
    else {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = $locale->maketext('[asis,cPHulk] is already disabled.');
    }
    return;
}

=item B<create_cphulk_record>

Creates new record(s) in the cPHulk list specified. When adding records to the whitelist, any existing blocks
for IPs that match will be removed.

B<Input>:

    list_name => The name of the list being altered. Valid values are [ 'white', 'black' ].
    ip        => The IPs to create new entries for.
                 NOTE:
                    Given how C<legacy_parse_query_string_sr> works, if you specify multiple IPs in the URI,
                    example: /json-api/create_cphulk_record?api.version=1&list_name=white&ip=2.1.34.4&ip=2.3.3.4, then they
                    are parsed and passed into the API call as "ip=2.1.34.4", and "ip-0=2.3.3.4".
    comment   => The comment to tag the IPs with.

B<Output>:

A hashref containing the details of the operation:

    {
        'list_name' => $name_of_the_list
        'ips_added' => [
            ...
            $ip1,
            $ip2,
            ...
        ],
        'ips_failed' => [
            ...
            $ip1_that_failed => 'possible reason for failure',
            $ip2_that_failed => 'possible reason for failure',
            ...
        ],
        'comment' => 'a possibly empty string',
        'requester_ip' => 'the ip address of requester',
        'ip_blocks_removed' => 'number of existing blocks removed from the DB. Only returned when adding records to the whitelist.',
        'iptable_bans_removed' => 'number of blocks removed from the temp IPtables chain. Only returned when adding records to the whitelist.',
        'requester_ip_is_whitelisted' => 'boolean (1 or 0) indicating whether the requester's IP address is whitelisted. Only returned when adding records to the whitelist.',
    }

Returns undef, and sets the 'result' and 'reason' values in the C<$metadata> hash accordingly on failure.

=cut

sub create_cphulk_record {
    my ( $args, $metadata ) = @_;

    _initialize( { 'init_dbh' => 1 } );
    return if !_validateHulkEnabled( $args->{'skip_enabled_check'}, $metadata );

    my $list_name = delete $args->{'list_name'};
    return if !_validateListName( $list_name, $metadata );

    my $comment = delete $args->{'comment'};

    my $requester_ip = $ENV{'REMOTE_ADDR'} || '';
    my $ips_to_add   = _parse_ips($args);
    my $ips_failed   = {};
    my @ips_added;
    my ( $delete_count, $removed_temporary_count ) = ( 0, 0 );

    foreach my $ip ( @{$ips_to_add} ) {
        try {
            if ( my ( $start_address, $end_address ) = Cpanel::Hulk::Admin::add_ip_to_list( $dbh, $ip, $list_name, $comment ) ) {
                push @ips_added, ( $start_address eq $end_address ) ? $start_address : "$start_address-$end_address";
                if ( $list_name eq 'white' ) {
                    my ( $ip_flushed, $ip_block_removed ) = _flush_ip_history($ip);
                    $delete_count            += $ip_flushed;
                    $removed_temporary_count += $ip_block_removed;
                }
            }
            else {
                # default "failure" reason. Typically add_ip_to_list dies on failure,
                # so this is mostly for unforeseen failures.
                $ips_failed->{$ip} = $locale->maketext('Unable to add IP address to database.');
            }
        }
        catch {
            $ips_failed->{$ip} = Cpanel::Exception::get_string($_);
        };
    }

    if ( scalar @ips_added ) {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';
    }
    else {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext( 'No IP addresses added to the “[_1]”.', "${list_name}list" );
    }

    return {
        'list_name'    => $list_name,
        'ips_added'    => \@ips_added,
        'ips_failed'   => $ips_failed,
        'comment'      => ( $comment || '' ),
        'requester_ip' => $requester_ip,
        ( $list_name eq 'white' )
        ? (
            'ip_blocks_removed'           => $delete_count,
            'iptable_bans_removed'        => $removed_temporary_count,
            'requester_ip_is_whitelisted' => ( Cpanel::Hulk::Admin::is_ip_whitelisted( $dbh, $requester_ip ) ? 1 : 0 )
          )
        : (),
    };
}

sub batch_create_cphulk_records {
    my ( $args, $metadata ) = @_;

    _initialize( { 'init_dbh' => 1 } );
    return if !_validateHulkEnabled( $args->{'skip_enabled_check'}, $metadata );

    my $list_name = delete $args->{'list_name'};
    return if !_validateListName( $list_name, $metadata );

    my $requester_ip   = $ENV{'REMOTE_ADDR'} || '';
    my $records_to_add = $args->{'records'};

    my %ips_failed;
    my @ips_added;
    my @original_ips_added;

    my ( $delete_count, $removed_temporary_count ) = ( 0, 0 );

    foreach my $record ( @{$records_to_add} ) {
        my $ip = $record->{ip};
        try {
            if ( my ( $start_address, $end_address ) = Cpanel::Hulk::Admin::add_ip_to_list( $dbh, $ip, $list_name, $record->{comment} ) ) {
                push @ips_added, ( $start_address eq $end_address ) ? $start_address : "$start_address-$end_address";
                push @original_ips_added, $ip;
                if ( $list_name eq 'white' ) {
                    my ( $ip_flushed, $ip_block_removed ) = _flush_ip_history($ip);
                    $delete_count            += $ip_flushed;
                    $removed_temporary_count += $ip_block_removed;
                }
            }
            else {
                # default "failure" reason. Typically add_ip_to_list dies on failure,
                # so this is mostly for unforeseen failures.
                $ips_failed{$ip} = $locale->maketext('Unable to add IP address to database.');
            }
        }
        catch {
            $ips_failed{$ip} = Cpanel::Exception::get_string($_);
        };
    }

    if ( scalar @ips_added ) {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';
    }
    else {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext( 'No IP addresses added to the “[_1]”.', "${list_name}list" );
    }

    return {
        'list_name'          => $list_name,
        'ips_added'          => \@ips_added,             # so people that don't know CIDR format very well, can read the ranges as simple ranges.
        'original_ips_added' => \@original_ips_added,    # so we can cross reference the input with the results programatically
        'ips_failed'         => \%ips_failed,
        'requester_ip'       => $requester_ip,
        ( $list_name eq 'white' )
        ? (
            'ip_blocks_removed'           => $delete_count,
            'iptable_bans_removed'        => $removed_temporary_count,
            'requester_ip_is_whitelisted' => ( Cpanel::Hulk::Admin::is_ip_whitelisted( $dbh, $requester_ip ) ? 1 : 0 )
          )
        : (),
    };
}

=item B<read_cphulk_records>

Reads the records in the cPHulk list specified.

B<Input>:

    list_name => The name of the list being altered. Valid values are [ 'white', 'black' ].

B<Output>:

A hashref containing the details of the operation:

    {
        'list_name' => $name_of_the_list
        'ips_in_list' => [
            ...
            $ip1,
            $ip2,
            ...
        ],
        'requester_ip' => 'the ip address of requester',
    }

When reading the 'whitelist', the output can also contain the following data if the requester_ip is not whitelisted:

    {
        'requester_ip_is_whitelisted' => 0 or 1 (indicating whether or not the requester's IP is whitelisted).
        'warning_ip' => A localized string explaining that the requester's IP is not whitelisted.
    }

Returns undef, and sets the 'result' and 'reason' values in the C<$metadata> hash accordingly on failure.

=cut

sub read_cphulk_records {
    my ( $args, $metadata ) = @_;

    foreach my $param (qw(list_name)) {
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => $param ] ) unless defined $args->{$param};
    }

    _initialize( { 'init_dbh' => 1 } );
    return if !_validateHulkEnabled( $args->{'skip_enabled_check'}, $metadata );

    my $list_name = delete $args->{'list_name'};
    return if !_validateListName( $list_name, $metadata );

    my $requester_ip                = $ENV{'REMOTE_ADDR'} || '';
    my $output                      = { 'list_name' => $list_name, 'ips_in_list' => {}, 'requester_ip' => $requester_ip };
    my $requester_ip_is_whitelisted = 0;

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    try {
        my $ip_entries = Cpanel::Hulk::Admin::get_hosts( $dbh, $list_name, 'yes_to_comments' );
        foreach my $entry ( @{$ip_entries} ) {
            my ( $ip, $comment ) = split( m{\s*#\s*}, $entry, 2 );
            $output->{'ips_in_list'}->{$ip} = $comment;
            if ( $requester_ip and $requester_ip eq $ip ) {
                $requester_ip_is_whitelisted = 1;
            }
        }
    }
    catch {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext( 'Failed to read “[_1]”.', "${list_name}list" );
    };
    return if !$metadata->{'result'};

    if ( $list_name eq 'white' ) {
        my ( $warning_ssh, $restart_ssh ) = _incompatibility_warnings();
        if ($warning_ssh) {
            $output->{'warning_ssh'} = $warning_ssh;
            $output->{'restart_ssh'} = $restart_ssh;
        }
        if ( $requester_ip && !$requester_ip_is_whitelisted && !Cpanel::Hulk::Admin::is_ip_whitelisted( $dbh, $requester_ip ) ) {
            $output->{'requester_ip_is_whitelisted'} = 0;
            $output->{'warning_ip'}                  = $locale->maketext( 'Your current IP address “[_1]” is not on the whitelist.', $requester_ip );
        }
    }
    return $output;
}

=item B<delete_cphulk_record>

Delete entries in the cPHulk list specified.

B<Input>:

    list_name => The name of the list being altered. Valid values are [ 'white', 'black' ].
    ip        => The IPs to remove.
                 NOTE:
                    Given how C<legacy_parse_query_string_sr> works, if you specify multiple IPs in the URI,
                    example: /json-api/delete_cphulk_record?api.version=1&list_name=white&ip=2.1.34.4&ip=2.3.3.4, then they
                    are parsed and passed into the API call as "ip=2.1.34.4", and "ip-0=2.3.3.4".

B<Output>:

A hashref containing the details of the operation:

    {
        'list_name' => $name_of_the_list
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
        'requester_ip' => 'the ip address of requester',
        'requester_ip_is_whitelisted' => 'boolean (1 or 0) indicating whether the requester's IP address is whitelisted. Only returned when deleting records from the whitelist.',
    }

Returns undef, and sets the 'result' and 'reason' values in the C<$metadata> hash accordingly on failure.

=cut

sub delete_cphulk_record {
    my ( $args, $metadata ) = @_;

    _initialize( { 'init_dbh' => 1 } );
    return if !_validateHulkEnabled( $args->{'skip_enabled_check'}, $metadata );

    my $list_name = delete $args->{'list_name'};
    return if !_validateListName( $list_name, $metadata );

    my $requester_ip  = $ENV{'REMOTE_ADDR'} || '';
    my $ips_to_remove = _parse_ips($args);
    my $ips_failed    = {};
    my @ips_removed;

    foreach my $ip ( @{$ips_to_remove} ) {
        try {
            if ( Cpanel::Hulk::Admin::remove_ip_from_list( $dbh, $ip, $list_name ) ) {
                push @ips_removed, $ip;
            }
            else {
                # default "failure" reason. Typically remove_ip_from_list dies on failure,
                # so this is mostly for unforeseen failures.
                $ips_failed->{$ip} = $locale->maketext('Unable to remove IP address from database.');
            }
        }
        catch {
            $ips_failed->{$ip} = Cpanel::Exception::get_string($_);
        };
    }

    if ( scalar @ips_removed ) {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';
    }
    else {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext( 'No IP addresses removed from the “[_1]”.', "${list_name}list" );
    }

    return {
        'list_name'    => $list_name,
        'ips_removed'  => \@ips_removed,
        'ips_failed'   => $ips_failed,
        'requester_ip' => $requester_ip,
        ( $list_name eq 'white' ) ? ( 'requester_ip_is_whitelisted' => ( Cpanel::Hulk::Admin::is_ip_whitelisted( $dbh, $requester_ip ) ? 1 : 0 ) ) : (),
    };
}

=item B<load_cphulk_config>

Reads and returns the current cPHulk configuration settings.

B<Input>:

    None.

B<Output>:

A hashref containing the details about the current configuration:

    {
        "cphulk_config" => {
            "is_enabled" => 1,
            "can_temp_ban_firewall" => 1,
            "ip_brute_force_period_mins" => 15,
            "max_failures" => 15,
            "brute_force_period_sec" => 300,
            "lookback_period_min" => 360,
            "mark_as_brute" => 30,
            "ip_brute_force_period_sec" => 900,
            "lookback_time" => 21600,
            "brute_force_period_mins" => 5,
            "notify_on_brute" => 0,
            "notify_on_root_login" => 0,
            "notify_on_root_login_for_known_netblock" => 0,
            "max_failures_byip" => 5,
            "block_brute_force_with_firewall" => 0,
            "block_excessive_brute_force_with_firewall" => 1,
            "command_to_run_on_brute_force" => "",
            "command_to_run_on_excessive_brute_force" => ""
        }
    }

Returns undef, and sets the 'result' and 'reason' values in the C<$metadata> hash accordingly on failure.

=cut

sub load_cphulk_config {
    my ( $args, $metadata ) = @_;

    _initialize();
    my $cphulkconf_ref;
    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    try {
        require Cpanel::Config::Hulk::Load;
        $cphulkconf_ref = Cpanel::Config::Hulk::Load::loadcphulkconf();
        $cphulkconf_ref->{'can_temp_ban_firewall'} = 0;
        try {
            my $iptables_obj = Cpanel::XTables::TempBan->new( 'chain' => 'cphulk' );
            $iptables_obj->ipversion(4);
            if ( $iptables_obj->can_temp_ban() ) {
                $cphulkconf_ref->{'can_temp_ban_firewall'} = 1;
            }
            else {
                $cphulkconf_ref->{'can_temp_ban_firewall'} = 0;
                $cphulkconf_ref->{'iptable_error'}         = $locale->maketext('The system disabled firewall options. These options require [asis,IPTables v1.4] or higher and a non-[asis,Virtuozzo] environment.');
            }
        }
        catch {
            $cphulkconf_ref->{'iptable_error'} = $locale->maketext( 'The system disabled firewall options: [_1]', Cpanel::Exception::get_string_no_id($_) );
        };
    }
    catch {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext( 'Failed to read [asis,cPHulk] configuration: [_1]', $_ );
    };
    return if !$metadata->{'result'};

    return { 'cphulk_config' => $cphulkconf_ref };
}

=item B<save_cphulk_config>

Modifies the cPHulk configuration settings as specified.

B<Input>: Hashref containing one or more of the following keys:

    Options that take a positive integer as their values:

    'ip_brute_force_period_mins' => "IP Based Brute Force Protection Period in minutes"
    'brute_force_period_mins' => "Brute Force Protection Period in minutes"
    'max_failures' => "Maximum Failures By Account"
    'max_failures_byip' => "Maximum Failures Per IP"
    'mark_as_brute' => "Maximum Failures Per IP before IP is blocked for two week period"
    'lookback_period_min' => "The lookback period for counting failed logins against a user"

    Options that take a string as their value:

    'command_to_run_on_brute_force' => "Command to run when an IP address triggers brute force protection"
    'command_to_run_on_excessive_brute_force' => "Command to run when the system blocks an IP address blocked for a one day period"

    Boolean options (valid values are: 1 or 0), displayed as check boxes on the UI:

    'notify_on_brute' => "Send notification when brute force user is detected"
    'notify_on_root_login' => "Send a notification upon successful root login when the IP is not whitelisted"
    'notify_on_root_login_for_known_netblock' => "Send notifications for known netblocks (only if notify_on_root_login is enabled)",
    'block_brute_force_with_firewall' => "Block IP addresses that trigger brute force protection at the firewall level"
    'block_excessive_brute_force_with_firewall' => "Block IP addresses that match the criteria for a one day block at the firewall level"


B<Output>:

A hashref containing the details about the current configuration:

    {
        'cphulk_config' => {
            'brute_force_period_mins' => '5',
            'ip_brute_force_period_mins' => '15',
            'is_enabled' => 1,
            'mark_as_brute' => '30',
            'max_failures' => '15',
            'max_failures_byip' => '5',
            'notify_on_root_login' => '0'
            'notify_on_root_login_for_known_netblock' => '0'
        },
        'warning' => "A string warning that indicates that the SSHD configuration was altered, because the 'UseDNS' setting was turned off"
        'restart_ssh' => 1 or 0 (boolean value indicating whether or not SSHD has to be restarted),
    }

Returns undef, and sets the 'result' and 'reason' values in the C<$metadata> hash accordingly on failure.

=cut

sub save_cphulk_config {
    my ( $args, $metadata ) = @_;

    _initialize();
    return if !_validateHulkEnabled( $args->{'skip_enabled_check'}, $metadata );

    delete $args->{'skip_enabled_check'};

    if ( ( grep { defined $args->{$_} } qw( mark_as_brute max_failures_byip ) ) == 2 ) {
        if ( $args->{'mark_as_brute'} < $args->{'max_failures_byip'} ) {
            $metadata->{'result'} = 0;
            $metadata->{'reason'} = $locale->maketext('The number of failures per IP address before a one-day block must be greater than or equal to the number of failures per IP address before normal brute force protection.');
            return;
        }
    }

    # $args should be sanitized to only contain valid keys by this stage, so its safe
    # to pass the hashref directly on to savecphulkconf().
    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    try {
        require Cpanel::Config::Hulk::Conf;
        Cpanel::Config::Hulk::Conf::savecphulkconf($args);
    }
    catch {
        my $err = $_;
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext( 'Failed to save [asis,cPHulk] configuration: [_1]', $_->to_string() );
    };
    return if !$metadata->{'result'};

    my $_handle_post_cphulk_config_save = _handle_post_cphulk_config_save();
    return $_handle_post_cphulk_config_save if $_handle_post_cphulk_config_save;
    $metadata->{'result'} = 0;
    $metadata->{'reason'} = $locale->maketext('Failed to read [asis,cPHulk] configuration after saving.');
    return;
}

=item B<set_cphulk_config_key>

Modifies a single cPHulk configuration settings as specified.

B<Input>:

    key: A single configuration key (see save_cphulk_config)
    value: The new value for the key

B<Output>:

Returns 1 on a successful update.

Dies on failure.

=cut

sub set_cphulk_config_key {
    my ( $args, $metadata ) = @_;
    my $key   = Whostmgr::API::1::Utils::get_required_argument( $args, 'key' );
    my $value = Whostmgr::API::1::Utils::get_required_argument( $args, 'value' );

    # dies on failure
    require Cpanel::Config::Hulk::Conf;
    Cpanel::Config::Hulk::Conf::set_single_conf_key( $key, $value );

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    my $_handle_post_cphulk_config_save = _handle_post_cphulk_config_save();
    return $_handle_post_cphulk_config_save if $_handle_post_cphulk_config_save;

    return;
}

=item B<get_cphulk_brutes>

See L<_get_cphulk_login_history>

=cut

sub get_cphulk_brutes {
    my ( $args, $metadata ) = @_;
    return _get_cphulk_login_history( { 'brutes' => 1 }, $metadata );
}

=item B<get_cphulk_excessive_brutes>

See L<_get_cphulk_login_history>

=cut

sub get_cphulk_excessive_brutes {
    my ( $args, $metadata ) = @_;
    return _get_cphulk_login_history( { 'excessive_brutes' => 1 }, $metadata );
}

=item B<get_cphulk_failed_logins>

See L<_get_cphulk_login_history>

=cut

sub get_cphulk_failed_logins {
    my ( $args, $metadata ) = @_;
    return _get_cphulk_login_history( { 'failed_logins' => 1 }, $metadata );
}

=item B<get_cphulk_user_brutes>

See L<_get_cphulk_login_history>

=cut

sub get_cphulk_user_brutes {
    my ( $args, $metadata ) = @_;
    return _get_cphulk_login_history( { 'user_brutes' => 1 }, $metadata );
}

=item B<_get_cphulk_login_history>

Reads the DB and returns the entries for brutes, excessive brutes, and failed logins.

B<Input>:

    A hashref indicating what dataset you want returned. Valid keys are:

        'brutes'
        'excessive_brutes'
        'failed_logins'
        'user_brutes'

B<Output>:

A hashref containing details about the login history:

    {
          'brutes' => [
                        ...
                        {
                          'exptime' => '2014-10-10 14:25:51',
                          'notes' => 'lol',
                          'logintime' => '2014-10-09 14:25:51',
                          'ip' => '49.54.57.48.57.48.54.48'
                        }
                        ...
                      ],
          'excessive_brutes' => [
                                  ...
                                  {
                                    'exptime' => '2014-10-10 14:25:57',
                                    'notes' => 'lol',
                                    'logintime' => '2014-10-09 14:25:57',
                                    'ip' => '49.54.57.48.57.48.54.48'
                                  }
                                  ...
                                ],
          'failed_logins' => [
                               ...
                               {
                                 'exptime' => '2014-10-10 14:26:03',
                                 'logintime' => '2014-10-09 14:26:03',
                                 'ip' => '49.54.57.48.57.48.54.48',
                                 'user' => 'rishtes3',
                                 'service' => 'ftp',
                                 'authservice' => 'qut'
                               }
                               ...
                             ],
          'user_brutes' => [
                             ...
                             {
                                "exptime": "2014-10-30 10:49:59",
                                "timeleft": "1439",
                                "logintime": "2014-10-29 10:49:59",
                                "ip": "49.54.57.48.57.48.54.48",
                                "user": "rishtes3",
                                "service": "ftp",
                                "authservice": "qut"
                             }
                             ...
                           ]
    }

Returns undef, and sets the 'result' and 'reason' values in the C<$metadata> hash accordingly on failure.

=cut

sub _get_cphulk_login_history {
    my ( $args, $metadata ) = @_;

    _initialize( { 'init_dbh' => 1 } );
    return if !_validateHulkEnabled( 0, $metadata );

    my $output;
    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    try {
        ( $args->{'brutes'} )           ? ( $output->{'brutes'}           = Cpanel::Hulk::Admin::get_brutes($dbh) )           : ();
        ( $args->{'excessive_brutes'} ) ? ( $output->{'excessive_brutes'} = Cpanel::Hulk::Admin::get_excessive_brutes($dbh) ) : ();
        ( $args->{'failed_logins'} )    ? ( $output->{'failed_logins'}    = Cpanel::Hulk::Admin::get_failed_logins($dbh) )    : ();
        ( $args->{'user_brutes'} )      ? ( $output->{'user_brutes'}      = Cpanel::Hulk::Admin::get_user_brutes($dbh) )      : ();
    }
    catch {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $_;
    };
    return if !$metadata->{'result'};

    return $output;
}

=item B<flush_cphulk_login_history>

Removes the login history entries from the DB.

B<Input>:

    None

B<Output>:

A hashref containing details about the deletion:

    {
        'records_removed' => $number_of_rows_deleted_from_db
    }

Returns undef, and sets the 'result' and 'reason' values in the C<$metadata> hash accordingly on failure.

=cut

sub flush_cphulk_login_history {
    my ( $args, $metadata ) = @_;

    _initialize( { 'init_dbh' => 1 } );
    my $delete_count;
    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    try {
        $delete_count = Cpanel::Hulk::Admin::flush_login_history($dbh);
        my $banner = Cpanel::XTables::TempBan->new( 'chain' => 'cphulk' );
        foreach my $ipversion ( $banner->supported_ip_versions() ) {
            $banner->ipversion($ipversion);
            $banner->purge_chain();
        }
    }
    catch {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $_;
    };
    return if !$metadata->{'result'};

    return { 'records_removed' => $delete_count };
}

=item B<flush_cphulk_login_history_for_ips>

Removes the login history entries from the DB for a list of IP address.

B<Input>:

    A hashref indicating what ip address(es) you want to remove:

    ip        => The IPs to create new entries for.
                 NOTE:
                    Given how C<legacy_parse_query_string_sr> works, if you specify multiple IPs in the URI,
                    example: ...&ip=2.1.34.4&ip=2.3.3.4..., then they
                    are parsed and passed into the API call as "ip=2.1.34.4", and "ip-0=2.3.3.4".
B<Output>:

A hashref containing the details about the current configuration
and sets the 'result' and 'reason' values in the C<$metadata> hash accordingly on failure.

{
    # number of rows removed from the login_track table for these ips
    records_removed      => [0-9]+
    # number of tmporary iptables ban removed
    iptable_bans_removed => [0-9]+
}

=cut

sub flush_cphulk_login_history_for_ips {
    my ( $args, $metadata ) = @_;

    _initialize( { 'init_dbh' => 1 } );
    return if !_validateHulkEnabled( 0, $metadata );

    my $ips_to_remove = _parse_ips($args);

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    my $delete_count            = 0;
    my $removed_temporary_count = 0;
    try {
        foreach my $ip ( @{$ips_to_remove} ) {
            my ( $ip_flushed, $ip_block_removed ) = _flush_ip_history($ip);
            $delete_count            += $ip_flushed;
            $removed_temporary_count += $ip_block_removed;
        }
    }
    catch {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $_;
    };
    return if !$metadata->{'result'};

    return { 'records_removed' => $delete_count, 'iptable_bans_removed' => $removed_temporary_count };
}

sub _flush_ip_history {
    my $ip_to_remove = shift;

    my $ip_flushed = Cpanel::Hulk::Admin::flush_login_history_for_ip( $dbh, $ip_to_remove );
    my $ipversion  = ( $ip_to_remove =~ tr/:// ) ? 6 : 4;
    my $iptables   = Cpanel::XTables::TempBan->new(
        chain => 'cphulk',
    );
    $iptables->ipversion($ipversion);
    my $ip_block_removed = $iptables->can_temp_ban() ? ( $iptables->remove_temp_block($ip_to_remove) || 0 ) : 0;
    return ( $ip_flushed, $ip_block_removed );
}

sub _incompatibility_warnings {

    require Cpanel::Config::Hulk::Load;
    my $cphulkconf_ref = Cpanel::Config::Hulk::Load::loadcphulkconf();

    my $sshd_warning_message = "";

    _initialize();

    # 'UseDNS' is enabled by default, so disable and warn on any changes.
    if ( $cphulkconf_ref->{'is_enabled'} == 1 ) {
        require Whostmgr::Services::SSH::UseDNS;

        my $disabled;

        local $@;
        if ( eval { $disabled = Whostmgr::Services::SSH::UseDNS::disable_if_needed(); 1 } ) {
            if ($disabled) {
                $sshd_warning_message = $locale->maketext( 'The system disabled the “[_1]” setting for [asis,SSHD] in order to add IP addresses to the whitelist. The system will now restart [asis,SSHD].', 'UseDNS' );
            }
        }
        else {
            my $err = $@;

            $sshd_warning_message = $locale->maketext( 'An error occurred while the system tried to disable [asis,SSHD]’s “[_1]” setting. ([_2]) You must make this change manually for the whitelist to function properly.', 'UseDNS', "$@" );
        }
    }

    # We used to make the caller restart SSHD, but nowadays we
    # do the restart for them. Thus the hard-coded 0 (falsy) return.
    return ( $sshd_warning_message, 0 );
}

sub _parse_ips {
    my $args = shift;
    my @ips  = map { $args->{$_} } grep { $_ =~ /^ip(\-\d+)?$/ } ( keys %{$args} );
    return \@ips;
}

sub _initialize {
    my $opts_hr = shift // {};

    require Cpanel::Locale;
    $locale ||= Cpanel::Locale->get_handle();
    if ( $opts_hr->{'init_dbh'} ) {
        require Cpanel::Hulk::Admin::DB;
        $dbh ||= Cpanel::Hulk::Admin::DB::get_dbh();

        die "Failed to open Hulk DBH ($@)" if !$dbh;
    }

    return 1;
}

sub _handle_post_cphulk_config_save {

    if ( my $output = load_cphulk_config( {}, {} ) ) {
        my ( $ssh_warning, $restart_ssh ) = _incompatibility_warnings();
        if ($ssh_warning) {
            $output->{'warning'}     = $ssh_warning;
            $output->{'restart_ssh'} = $restart_ssh;
        }
        require Cpanel::Signal;
        Cpanel::Signal::send_hup_cphulkd();
        require Cpanel::ServerTasks;
        Cpanel::ServerTasks::schedule_task( ['CpServicesTasks'], 10, 'hupcpsrvd' );
        return $output;
    }
}

sub _validateHulkEnabled ( $skip_enabled_check, $metadata ) {
    if ( !$skip_enabled_check && !Cpanel::Config::Hulk::is_enabled() ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext('[asis,cPHulk] is disabled on the server.');
        return;
    }
    return 1;
}

sub _validateListName ( $list_name, $metadata ) {
    if ( not exists $Cpanel::Config::Hulk::LIST_TYPE_VALUES{$list_name} ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext('Invalid list name specified. Valid values are “[asis,white]” or “[asis,black]”.');
        return;
    }
    return 1;
}

=back

=cut

1;
