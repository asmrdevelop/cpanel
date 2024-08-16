package Cpanel::API::Bandwidth;

# cpanel - Cpanel/API/Bandwidth.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::APITimezone              ();
use Cpanel::BandwidthDB              ();
use Cpanel::BandwidthDB::Read        ();
use Cpanel::BandwidthDB::State       ();
use Cpanel::LinkedNode::Worker::User ();
use Cpanel::Time                     ();

#Returns data transfer amounts from the system’s internal bandwidth datastore.
#
#Arguments are:
#
#   grouping    - required, pipe-concatenated (|) list of at least one of:
#       - domain
#       - protocol
#       - ...and/or ONE of the following:
#           year
#           year_month
#           year_month_day
#           year_month_day_hour
#           year_month_day_hour_minute
#
#   interval    - optional, length of time between samples for response
#               Possible values:
#                   - daily (default; data aggregated for each day)
#                   - hourly (data aggregated for each hour)
#                   - 5min
#
#               NOTE: Availability of data for a given interval depends on
#               the interval’s retention period, which is available via the
#               get_retention_periods() API call. Queries of 5-minute data,
#               for example, will not include data from a time before the
#               current time minus the expiration period for 5-minute data.
#
#   domains     - optional, pipe-concatenated (|) list of domains
#               to which the results of the API response will be restricted.
#               (i.e., a filter)
#
#               Note that, as of 11.52, the system counts all non-HTTP traffic
#               in the “UNKNOWN” domain.
#
#   protocols   - optional, pipe-concatenated (|) list of protocols
#               to which the results of the API response will be restricted.
#               (i.e., a filter) Can be any of:
#                   - http
#                   - imap
#                   - smtp
#                   - pop3
#                   - ftp
#
#   start       - optional, UNIX timestamp, specifies an inclusive lower
#               boundary for returned data.
#
#   end         - optional, like “start”, but an inclusive upper boundary
#
#   timezone    - optional, Olson/TZ name. If not given, and you specify a
#               time-based “grouping”, the system will use its own local time
#               zone to group data by time units.
#
#The return structure is an N-level-deep hash, where N is the number of
#items given in the “grouping” parameter. Times are represented as UNIX
#timestamps in the response.
#
#For example, if you submit query parameters:
#
#   { grouping => 'year_month_day|protocol' }
#
#...you might get back results like:
#
#   {
#       86400   => {    #i.e., midnight on 2 Jan 1970 UTC
#           'http' => 234,
#           'pop3' => 123,
#           ...
#       },
#       172800 => {     #i.e., midnight on 3 Jan 1970 UTC
#           'http' => 111,
#           ...
#       },
#       ...
#       2678400 => { .. },  #midnight on 1 Feb 1970 UTC
#   }
#
#The same data as above, had it been requested with:
#
#   { grouping => 'year_month|protocol' }   - NOTE: no “day”!
#
#...would give results like:
#
#   {
#       0   => {    #i.e., midnight on 1 Jan 1970 UTC
#           'http' => 345,
#           'pop3' => 123,
#           ...
#       },
#       2678400 => { .. },  #midnight on 1 Feb 1970 UTC
#   }
#
sub query ( $args, $result, @ ) {

    #Favor the passed-in timezone first.
    #
    #Then, use any pre-existing $ENV{'TZ'}
    #
    #If nothing else, set $ENV{'TZ'} for this function
    #since otherwise C’s strftime() function (which Perl & SQLite both use)
    #will stat(/etc/localtime) over and over.
    #
    require Cpanel::APITimezone;
    local $ENV{'TZ'} = Cpanel::APITimezone::get_uapi_timezone($args);

    $args->get_length_required('grouping');    #just to get an error

    my %opts;
    for my $key (qw( grouping  domains  protocols )) {
        my $val = $args->get($key);
        if ( length $val ) {
            $opts{$key} = [ split m<\|>, $val ];
        }
    }

    for my $key (qw( start end )) {
        my $val = $args->get($key);
        if ( length $val ) {
            $opts{$key} = join( '-', reverse( ( Cpanel::Time::localtime($val) )[ 0 .. 5 ] ) );
        }
    }

    my $the_goods = Cpanel::BandwidthDB::get_reader_for_user()->get_bytes_totals_as_hash(
        %opts,
        interval => $args->get('interval') || undef
    );

    my ($time_depth) = map { $opts{'grouping'}->[$_] =~ m<\Ayear> ? $_ : () } ( 0 .. $#{ $opts{'grouping'} } );

    if ( defined $time_depth ) {
        _convert_ymdhms_keys_to_epoch( $the_goods, $time_depth );
    }

    _add_remote_bw_usage( $args, $the_goods );

    $result->data($the_goods);

    return 1;
}

sub _add_remote_bw_usage ( $args, $local_data_hr ) {
    my ( $module, $fn ) = (
        __PACKAGE__ =~ s<.+::><>r,
        'query',
    );

    my %args = (
        %{ $args->get_raw_args_hr() },
        timezone => $ENV{'TZ'},
    );

    my @results = Cpanel::LinkedNode::Worker::User::call_all_workers_uapi(
        $module, $fn,
        \%args,
    );

    my $merger = @results && _create_merger();

    for my $remote_result_ar (@results) {
        my $result = $remote_result_ar->{'result'};

        %$local_data_hr = %{ $merger->merge( $result->data(), $local_data_hr ) };
    }

    return;
}

sub _die_array {
    die 'Got ARRAY value?';
}

sub _die_scalar_hash {
    die 'Mismatch: remote SCALAR, local HASH!';
}

sub _die_hash_scalar {
    die 'Mismatch: remote HASH, local SCALAR!';
}

sub _create_merger() {
    require Hash::Merge;
    my $merger = Hash::Merge->new();

    $merger->add_behavior_spec(
        {
            SCALAR => {
                SCALAR => sub ( $remote, $local ) {
                    return $remote + $local;
                },
                ARRAY => \&die_array,
                HASH  => \&die_scalar_hash,
            },
            ARRAY => {
                SCALAR => \&die_array,
                ARRAY  => \&die_array,
                HASH   => \&die_array,
            },
            HASH => {
                SCALAR => \&die_hash_scalar,
                ARRAY  => \&die_array,
                HASH   => sub ( $remote, $local ) {

                    # cf. https://metacpan.org/pod/Hash::Merge#_merge_hashes(-%3Chashref%3E,-%3Chashref%3E-)-INTERNAL-FUNCTION
                    return $merger->_merge_hashes( $remote, $local );
                },
            },
        },
        'AggregateBandwidth',
    );
    $merger->set_behavior('AggregateBandwidth');

    return $merger;
}

sub get_enabled_protocols {
    my ( $args, $result ) = @_;
    $result->data( [ Cpanel::BandwidthDB::State::get_enabled_protocols() ] );
    return 1;

}

sub _convert_ymdhms_keys_to_epoch {
    my ( $hash, $level ) = @_;

    if ( $level == 0 ) {
        for my $ymdhms ( keys %$hash ) {
            $hash->{ _ymdhms_to_epoch( split m<->, $ymdhms ) } = delete $hash->{$ymdhms};
        }
    }
    else {
        _convert_ymdhms_keys_to_epoch( $_, $level - 1 ) for values %$hash;
    }

    return;
}

sub _ymdhms_to_epoch {
    my (@ymdhms) = @_;

    $_ ||= 0 for @ymdhms[ 0, 3, 4, 5 ];
    $_ ||= 1 for @ymdhms[ 1, 2 ];

    return Cpanel::Time::timelocal( reverse @ymdhms );
}

#Takes no arguments.
#
#Returns a list of hashes like:
#
#   [
#       {
#           interval    => '5min',
#           retention   => <epoch seconds>,
#       },
#       ...
#   ]
#
sub get_retention_periods {
    my ( $args, $result ) = @_;

    my $exp_hr = \%Cpanel::BandwidthDB::Read::EXPIRATION_FOR_INTERVAL;

    my @resp = map { { interval => $_, retention => $exp_hr->{$_} } } keys %$exp_hr;

    $result->data( \@resp );

    return 1;
}

my $allow_demo = {
    needs_role => { match => 'any', roles => [ 'FileStorage', 'MailReceive', 'WebServer' ] },
    allow_demo => 1,
};

our %API = (
    query                 => $allow_demo,
    get_enabled_protocols => $allow_demo,
    get_retention_periods => $allow_demo,
);

1;
