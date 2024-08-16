package Whostmgr::API::1::Sys;

# cpanel - Whostmgr/API/1/Sys.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf8

=head1 NAME

Whostmgr::API::1::Sys

=head1 DESCRIPTION

This module contains WHM API methods related to the system.

=head1 FUNCTIONS

=cut

use cPstrict;

use Cpanel::Imports;

use Cpanel::APICommon::Persona       ();    ## PPI NO PARSE - (constant)
use Cpanel::AcctUtils::Account       ();
use Cpanel::Auth::Digest::DB::Manage ();
use Cpanel::Auth::Digest::Utils      ();
use Cpanel::ChangePasswd             ();
use Cpanel::Config::Sources          ();
use Cpanel::DiskLib                  ();
use Cpanel::Exception                ();
use Cpanel::Form::Param              ();
use Cpanel::LoadModule               ();
use Cpanel::Locale                   ();
use Cpanel::MysqlUtils::MyCnf::Basic ();
use Cpanel::SafeRun::Errors          ();
use Cpanel::Sys::Hostname            ();
use Cpanel::Validate::Username       ();
use Whostmgr::API::1::Utils          ();
use Whostmgr::Authz                  ();
use Whostmgr::Dcpumon                ();
use Whostmgr::Passwd::Change         ();
use Whostmgr::Sys                    ();

use constant ARGUMENT_NEEDS_PARENT => {
    passwd => 'user',
};

use constant NEEDS_ROLE => {
    configurebackgroundprocesskiller => undef,
    get_appconfig_application_list   => undef,
    get_available_tiers              => undef,
    getdiskusage                     => undef,
    gethostname                      => undef,
    has_digest_auth                  => undef,
    has_mycnf_for_cpuser             => 'MySQLClient',
    passwd                           => undef,
    reboot                           => undef,
    run_cpkeyclt                     => undef,
    set_cpanel_updates               => undef,
    set_digest_auth                  => undef,
    set_tier                         => undef,
    validate_system_user             => undef,

    get_tcp4_sockets => undef,
    get_tcp6_sockets => undef,
    get_udp4_sockets => undef,
    get_udp6_sockets => undef,
    get_api_calls    => undef,
    get_api_pages    => undef,
};

my %ALLOWED_API_TYPES = ( 'cpapi1' => 1 );
my $locale;

sub get_tcp4_sockets {
    my ( undef, $metadata ) = @_;

    return _get_sockets( $metadata, 'tcp4' );
}

sub get_tcp6_sockets {
    my ( undef, $metadata ) = @_;

    return _get_sockets( $metadata, 'tcp6' );
}

sub get_udp4_sockets {
    my ( undef, $metadata ) = @_;

    return _get_sockets( $metadata, 'udp4' );
}

sub get_udp6_sockets {
    my ( undef, $metadata ) = @_;

    return _get_sockets( $metadata, 'udp6' );
}

sub _get_sockets {
    my ( $metadata, $type ) = @_;

    require Cpanel::Sys::Net;

    my $sockets_ar = Cpanel::Sys::Net->can("get_${type}_sockets")->();

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return { payload => $sockets_ar };
}

sub gethostname {
    my ( undef, $metadata ) = @_;
    my $hostname = Cpanel::Sys::Hostname::gethostname();
    if ( !defined $hostname ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'Unable to determine hostname.';
        return;
    }
    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    return { 'hostname' => $hostname };
}

sub validate_system_user {
    my ( $args, $metadata ) = @_;
    $locale ||= Cpanel::Locale->get_handle();
    my $user = $args->{'user'};
    if ( !defined $user ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext( 'No user name supplied: “[_1]” is a required argument.', "user" );
        return;
    }

    my $exists            = Cpanel::AcctUtils::Account::accountexists($user)           ? 1 : 0;
    my $reserved          = Cpanel::Validate::Username::reserved_username_check($user) ? 1 : 0;
    my $is_valid          = Cpanel::Validate::Username::is_valid($user)                ? 1 : 0;
    my $is_strictly_valid = Cpanel::Validate::Username::is_strictly_valid($user)       ? 1 : 0;

    @{$metadata}{qw(result reason)} = qw( 1 OK );

    return { 'exists' => $exists, 'valid_for_transfer' => $is_valid, 'valid_for_new' => $is_strictly_valid, 'reserved' => $reserved };
}

sub has_mycnf_for_cpuser {
    my ( $args, $metadata ) = @_;
    $locale ||= Cpanel::Locale->get_handle();
    my $user = $args->{'user'};

    if ( !defined $user ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext( 'No user name supplied: “[_1]” is a required argument.', "user" );
        return { 'digestauth' => 0 };
    }

    if ( !Cpanel::AcctUtils::Account::accountexists($user) ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext('Account does not exist.');
        return { 'digestauth' => 0 };
    }

    Whostmgr::Authz::verify_account_access($user);

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = $locale->maketext('OK');
    my $mydbuser = Cpanel::MysqlUtils::MyCnf::Basic::getmydbuser($user);
    return { 'has_mycnf_for_cpuser' => ( ( $mydbuser && $mydbuser eq $user ) ? 1 : 0 ) };
}

sub has_digest_auth {
    my ( $args, $metadata ) = @_;
    $locale ||= Cpanel::Locale->get_handle();
    my $user = $args->{'user'};

    if ( !length $user ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext( 'No user name supplied: “[_1]” is a required argument.', "user" );
        return { 'digestauth' => 0 };
    }

    if ( !Cpanel::AcctUtils::Account::accountexists($user) ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext('Account does not exist.');
        return { 'digestauth' => 0 };
    }

    Whostmgr::Authz::verify_account_access( $args->{'user'} );

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = $locale->maketext('OK');
    return { 'digestauth' => ( Cpanel::Auth::Digest::DB::Manage::has_entry($user) ? 1 : 0 ) };
}

sub set_digest_auth {
    my ( $args, $metadata ) = @_;

    Whostmgr::Authz::verify_account_access( $args->{'user'} );

    $locale ||= Cpanel::Locale->get_handle();

    if ( !exists $args->{'enabledigest'} && !exists $args->{'digestauth'} ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext( 'The “[_1]” parameter is required.', "enabledigest" );
        return;
    }

    my $ret = Cpanel::Auth::Digest::Utils::set_digest_auth($args);

    foreach my $key ( 'reason', 'result' ) {
        $metadata->{$key} = $ret->{$key};
    }
    return;
}

sub passwd {
    my ( $args, $metadata, $api_info_hr ) = @_;
    my $user     = $args->{'user'};
    my $password = $args->{'password'};
    $locale ||= Cpanel::Locale->get_handle();

    my $dbpassupdate = 1;
    if ( exists $args->{'db_pass_update'} && !$args->{'db_pass_update'} ) {
        $dbpassupdate = 0;
    }

    my $apps;
    if ( !defined $user ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext( 'No user name supplied: “[_1]” is a required argument.', "user" );
        return;
    }
    elsif ( !defined $password ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext( 'No password supplied: “[_1]” is a required argument.', "password" );
        return;
    }

    my $digest_auth = Cpanel::ChangePasswd::get_digest_auth_option( $args, $user );

    Whostmgr::Authz::verify_account_access( $args->{'user'} );

    my $persona   = $api_info_hr->{'persona'};
    my $is_parent = $persona && $persona eq Cpanel::APICommon::Persona::PARENT;

    my $xtra_opts = {};
    $xtra_opts->{password_strength_check} = 'none' if $is_parent;

    # The postgres key in the line below will do nothing as of this point, this is put in here as a place holder and should have no effect on current operations
    my %optional_services = ( 'mysql' => $dbpassupdate, 'postgres' => $dbpassupdate, 'digest' => $digest_auth );
    my ( $result, $reason, $output, $changed ) = Whostmgr::Passwd::Change::passwd( $user, $password, \%optional_services, $xtra_opts );

    $apps                 = $changed;
    $metadata->{'result'} = $result ? 1 : 0;
    $metadata->{'reason'} = $reason || ( $result ? $locale->maketext('OK') : $locale->maketext('Failed to set password.') );
    if ( length $output ) {
        $metadata->{'output'}->{'raw'} = $output;
    }

    return if !$apps;
    my @app_names;
    foreach my $app (@$apps) {
        push @app_names, $app->{'app'};
    }
    return { 'app' => \@app_names };
}

sub reboot {
    my ( $args, $metadata ) = @_;
    my $force = $args->{'force'} ? 1 : 0;

    my $ret;

    if ($force) {
        Whostmgr::Sys::forcereboot();
        $ret = { 'force' => $force };
    }
    else {
        Whostmgr::Sys::reboot();
    }

    @{$metadata}{ 'result', 'reason' } = ( 1, 'OK' );

    return $ret || ();
}

sub getdiskusage {
    my ( $args, $metadata ) = @_;
    my $disk_info_arr = Cpanel::DiskLib::get_disk_used_percentage_with_dupedevs();

    if ( !ref $disk_info_arr || !scalar @{$disk_info_arr} ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'Unable to retrieve disk usage';
        return;
    }

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'Successfully retrieved disk usage';
    return { partition => $disk_info_arr };
}

sub configurebackgroundprocesskiller {
    my ( $args, $metadata ) = @_;

    my %fixed_args = ( 'force' => $args->{'force'} );
    my $fixed_form = Cpanel::Form::Param->new( { 'parseform_hr' => $args } );

    for my $key (qw(processes_to_kill trusted_users)) {
        if ( exists $args->{$key} ) {
            $fixed_args{$key} = [ $fixed_form->param($key) ];
        }
    }

    $args = \%fixed_args;

    my $procs   = $args->{'processes_to_kill'};
    my $trusted = $args->{'trusted_users'};
    my $force   = $args->{'force'};

    if ( defined $procs || $force ) {
        my @procs = ref $procs ? @$procs : ( defined $procs ? ($procs) : () );
        my $ok    = Whostmgr::Dcpumon::save_processes_to_kill(@procs);

        if ( !$ok ) {
            my $err = $! || '(unknown)';
            $metadata->{'result'} = 0;
            $metadata->{'reason'} = "Error saving processes to kill: $err";
            return;
        }
    }
    elsif ( !defined $trusted ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'No useful data submitted; nothing to do.';
        return;
    }

    if ( defined $trusted || $force ) {
        my @trusted = ref $trusted ? @$trusted : ( defined $trusted ? ($trusted) : () );
        my $ok      = Whostmgr::Dcpumon::save_trusted_users(@trusted);

        if ( !$ok ) {
            $metadata->{'result'} = 0;
            $metadata->{'reason'} = "Error saving trusted users; check system logs for further details.";
            return;
        }
    }

    @{$metadata}{ 'result', 'reason' } = ( 1, 'OK' );
    return;
}

sub set_tier {
    my ( $args, $metadata ) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::Update');
    $args->{'tier'} = '' if ( !defined $args->{'tier'} );
    my $new_tier = Cpanel::Update::set_tier( $args->{'tier'} ) || '';

    if ( $new_tier ne $args->{'tier'} ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'Error: "' . $args->{'tier'} . '" is an invalid tier. Tier is set to ' . $new_tier;
        return;
    }

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'Update tier successfully changed to ' . $new_tier;
    return { 'tier' => $new_tier };
}

sub set_cpanel_updates {
    my ( $args, $metadata ) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::Update');
    my $updates     = $args->{'updates'} || '';
    my $update_type = Cpanel::Update::set_update_type($updates);

    if ( $update_type ne $updates ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'Error: ' . $updates . ' is an unsupported update frequency (daily/manual/never). Frequency is now ' . $update_type;
        return;
    }

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'Cpanel update frequency set to ' . $update_type;
    return { 'updates' => $update_type };
}

sub get_available_tiers {
    my ( $args, $metadata ) = @_;

    if ( !$args->{'HTTPUPDATE'} ) {
        my $OPTS = Cpanel::Config::Sources::loadcpsources();
        $args->{'HTTPUPDATE'} = $OPTS->{'HTTPUPDATE'};
    }

    require Cpanel::Update::Tiers;
    my $tiers = eval { Cpanel::Update::Tiers->new->get_flattened_hash };

    if ($@) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'Error: could not determine available tiers for upgrade: ' . $@;
        return;
    }

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'Got tiers list';
    return $tiers;
}

sub get_appconfig_application_list {
    my ( $args, $metadata ) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::AppConfig');
    my $app_list = Cpanel::AppConfig::get_application_list();

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'Got application list';
    return $app_list;
}

sub run_cpkeyclt {
    my ( $args, $metadata ) = @_;
    my $force = $args->{'force'};    # do not document this flag as users will break their system with it

    my @results = Cpanel::SafeRun::Errors::saferunnoerror( '/usr/local/cpanel/cpkeyclt', $force ? ('--force-no-tty-check') : () );

    my $success = scalar grep ( /Update succeeded/i, @results );
    unless ($success) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'Error: The system could not update the license.';
        return;
    }

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'The system successfully updated the license.';
    return;
}

=head2 get_api_calls(TYPE)

Gets a historic usage statistics by day of the API calls of the type requested.

=head3 ARGUMENTS

=over

=item TYPE - string

Optional. Defaults to 'cpapi1'. Only supports 'cpapi1' for now.

=back

=head3 RETURNS

The data field contains:

Array ref of hash refs where the hash refs have the following structure:

=over

=item entry - string

The API module and method called.

=item count - number

Total number of times the API was called on the day in the timestamp field.

=item timestamp - Unix timestamp

A UNIX timestamp representing the year, month, and day the record is for starting at midnight local time.

=back

=head3 EXAMPLES

=head4 Command line usage for today

    whmapi1 --output=jsonpretty get_api_calls type=cpapi1

The returned data will contain a structure similar to the JSON below:

    "data" : {
      "result" : [
         {
            "entry" : "internal::version",
            "count" : 200000,
            "timestamp" : 1548828000
         },
         {
            "entry" : "Email::printdomainoptions",
            "count" : 200000,
            "timestamp" : 1548828000
         },
         ...
    ]

=cut

sub get_api_calls ( $args, $metadata, $api_args = {} ) {
    $args->{'type'} ||= 'cpapi1';

    if ( !_validate_api_analytics_type( $args->{'type'} ) ) {
        Whostmgr::API::1::Utils::set_metadata_not_ok( $metadata, locale()->maketext('Invalid type specified.') );
        return;
    }

    my ( $result, $errors ) = _load_api1_analytics_data( ['api1_calls'], $api_args->{'filter'} );
    if ( defined $errors && ref $errors eq 'ARRAY' && scalar @$errors ) {
        $metadata->{'output'}->{'warnings'} = $errors;
    }
    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return { 'result' => $result };
}

=head2 get_api_pages(TYPE)

Get the historic page use per day with API calls of the type specified. This can be used to see if
any custom pages or third party plugins are using a specific kind of API calls.

=head3 ARGUMENTS

=over

=item TYPE - string

Optional. Defaults to 'cpapi1'. Only supports 'cpapi1' for now.

=back

=head3 RETURNS

The data field contains:

Array ref of hash refs where the hash refs have the following structure:

=over

=item entry - string

A path to the file where the API was called.

=item count - number

Total number of times the API was called on the day in the timestamp field.

=item timestamp - Unix timestamp

A UNIX timestamp representing the year, month, and day the record is for starting at midnight local time.

=back

=head3 EXAMPLES

=head4 Command line usage for today

    whmapi1 --output=jsonpretty get_api_pages type=cpapi1

The returned data will contain a structure similar to the JSON below:

    "result" : [
         {
            "count" : 200000,
            "timestamp" : 1548828000,
            "entry" : "/usr/local/cpanel/base/frontend/jupiter/plugin1/child.html.tt"
         },
         {
            "entry" : "/usr/local/cpanel/base/frontend/jupiter/plugin1/index.html.tt",
            "timestamp" : 1548828000,
            "count" : 200000
         },
         ...
    ]

=cut

sub get_api_pages ( $args, $metadata, $api_args = {} ) {

    $args->{'type'} ||= 'cpapi1';

    if ( !_validate_api_analytics_type( $args->{'type'} ) ) {
        Whostmgr::API::1::Utils::set_metadata_not_ok( $metadata, locale()->maketext('Invalid type specified.') );
        return;
    }

    my ( $result, $errors ) = _load_api1_analytics_data( ['api1_pages'], $api_args->{'filter'} );
    if ( defined $errors && ref $errors eq 'ARRAY' && scalar @$errors ) {
        $metadata->{'output'}->{'warnings'} = $errors;
    }
    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return { 'result' => $result };

}

sub _validate_api_analytics_type {
    my ($type) = @_;
    return $ALLOWED_API_TYPES{$type} ? 1 : 0;
}

=head2 _evaluate_api_analytics_filter(FILTER, FILE_EPOCH_TIME) [PRIVATE]

Compare the WHAPI1 style filters against a given date. Only supports
the field 'timestamp' and 'lt', 'gt', 'lt_equal' and 'gt_equal' types.

=head3 ARGUMENTS

=over

=item FILTER - hashref

A set of filters formatted in the WHAPI1 style: https://go.cpanel.net/WHMAPI1FilterOutput

    {
        'version' => 1,
        'filter' => {
            'enable' => '1',
            'a' => {
                'type' => 'eq',
                'arg0' => '400',
                'field' => 'timestamp'
            }
        }
    };

=item FILE_EPOCH_TIME - integer

The unix epoch time to use as the timestamp field to compare against.

=back

=head3 RETURNS - boolean

=over

=item TRUE - All filters passed

=item FALSE - At least one filter failed

=back

=cut

sub _evaluate_api_analytics_filter ( $filters, $file_epoch_time ) {
    for ( sort grep { m/^[a-z]$/ } keys %$filters ) {
        my $filter = $filters->{$_};

        next if $filter->{'field'} ne 'timestamp';

        # Check the inverse of the type/operation and return false if it succeeds
        # all conditions in the array are 'and'ed together so if any is false
        # we short circuit early
        if ( $filter->{'type'} eq 'gt' ) {
            if ( $file_epoch_time <= $filter->{'arg0'} ) {
                return;
            }
        }
        elsif ( $filter->{'type'} eq 'gt_equal' ) {
            if ( $file_epoch_time < $filter->{'arg0'} ) {
                return;
            }
        }
        elsif ( $filter->{'type'} eq 'lt' ) {
            if ( $file_epoch_time >= $filter->{'arg0'} ) {
                return;
            }
        }
        elsif ( $filter->{'type'} eq 'lt_equal' ) {
            if ( $file_epoch_time > $filter->{'arg0'} ) {
                return;
            }
        }
    }

    # If we've reached here none of the previous checks failed
    return 1;
}

# $types is an arrayref with a default value
# $days is an optional number of days to stop looking at previous logs
sub _load_api1_analytics_data ( $types = [qw/api1_calls api1_pages/], $filter = {} ) {
    require Cpanel::Analytics::Config;

    return [] unless -d Cpanel::Analytics::Config::ANALYTICS_DATA_DIR();

    require Cpanel::Transaction::File::JSONReader;
    require Cpanel::Autodie;
    require Time::Local;

    my @results;
    my @exceptions;
    $filter ||= {};

    Cpanel::Autodie::opendir( my $dh, Cpanel::Analytics::Config::ANALYTICS_DATA_DIR() );
    while ( my $filename = readdir($dh) ) {

        if ( $filename =~ /^api1.([0-9]{4})-([0-9]{2})-([0-9]{2}).log.summary$/ ) {
            my ( $year, $month, $day ) = ( $1, $2, $3 );
            my $file_epoch = Time::Local::timelocal_modern( 0, 0, 0, $day, $month - 1, $year );

            # Skip files that don't match our $filters, if they're set
            if ( $filter->{'enable'} and not _evaluate_api_analytics_filter( $filter, $file_epoch ) ) {
                next;
            }

            my $reader = eval { Cpanel::Transaction::File::JSONReader->new( path => Cpanel::Analytics::Config::ANALYTICS_DATA_DIR() . "/${filename}" ) };

            if ( my $exception = $@ ) {
                push( @exceptions, Cpanel::Exception::get_string($exception) );
                next;
            }

            my $data = $reader->get_data();

            for my $type (@$types) {

                if ( ref $data eq 'HASH' && ref $data->{$type} eq 'HASH' ) {

                    for my $entry ( keys %{ $data->{$type} } ) {
                        push(
                            @results,
                            {
                                'timestamp' => $file_epoch,
                                'entry'     => $entry,
                                'count'     => $data->{$type}->{$entry}
                            }
                        );
                    }
                }
            }

        }
    }
    Cpanel::Autodie::closedir($dh);

    return ( \@results, \@exceptions );
}

1;
