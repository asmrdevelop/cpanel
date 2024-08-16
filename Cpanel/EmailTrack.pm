package Cpanel::EmailTrack;

# cpanel - Cpanel/EmailTrack.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings) -- not fully vetted for warnings

use Cpanel::AdminBin                ();
use Cpanel::DeliveryReporter::Utils ();
use Cpanel::Validate::EmailRFC      ();

our $VERSION = '1.2';

my $mail_send_role_allow_demo = {
    needs_role => "MailSend",
    allow_demo => 1,
};

our %API = (
    search => $mail_send_role_allow_demo,
    stats  => $mail_send_role_allow_demo,
    trace  => {
        engine     => 'array',
        needs_role => { match => 'all', roles => [ 'MailSend', 'MailReceive' ] },
        allow_demo => 1,
    },
);

sub EmailTrack_init {
    return 1;
}

sub api2_stats {
    my %OPTS = @_;

    if ( $Cpanel::appname eq 'webmail' && $Cpanel::authuser ne $Cpanel::user ) {
        $OPTS{'webmail'} = $Cpanel::authuser;

        #
        # SECURITY: Do not let the webmail user change anything but their own account
        #
    }

    my $data = Cpanel::AdminBin::adminfetchnocache( 'eximstats', '', 'STATS', undef, \%OPTS );

    if ( !$data->[0] ) {
        $Cpanel::CPERROR{'emailtrack'} = $data->[1] || 'eximstatsadmin returned invalid data';
        return 0;
    }

    return $data->[2];
}

sub api2_search {
    my %OPTS = @_;

    require Cpanel::Api2::Exec;
    require Cpanel::Api2::Sort;
    require Cpanel::Api2::Filter;
    require Cpanel::Api2::Paginate;

    #
    # Note: we use the name by which we are exposed in the api as the sub api2_search is defined by the
    # sub api2 function in this module and it could change
    #
    my $state_hr = $Cpanel::Api2::Exec::STATE{ __PACKAGE__ . "::search" } = {};

    if ( $Cpanel::appname eq 'webmail' && $Cpanel::authuser ne $Cpanel::user ) {
        $OPTS{'webmail'} = $Cpanel::authuser;

        #
        # SECURITY: Do not let the webmail user change anything but their own account
        #
    }

    my $sorters_ar = Cpanel::Api2::Sort::get_sort_func_list( \%OPTS, $API{'search'} );

    # Tell API2 that the data is presorted so it does not need
    # to handle the sorting
    if ( $sorters_ar && scalar @$sorters_ar ) {
        $OPTS{'sort'} ||= $sorters_ar->[0]{'column'};
        $OPTS{'dir'} = ( $sorters_ar->[0]{'reverse'} ? 'desc' : 'asc' );
        $state_hr->{'sorted'} = [ $sorters_ar->[0] ];
    }

    #See note in Whostmgr::API::1::Exim.
    my $pagination_to_api;

    #cf. Whostmgr::API::1::Exim
    my $filters_ar = Cpanel::Api2::Filter::get_filters( \%OPTS );
    Cpanel::DeliveryReporter::Utils::convert_filters_for_query( \%OPTS, $filters_ar );

    # Tell API2 that the data is already filtered
    $state_hr->{'filtered'} = $filters_ar;

    my $is_paginated;
    if ( !$pagination_to_api ) {
        Cpanel::Api2::Paginate::setup_pagination_vars( \%OPTS, [] );
        my $page_state = Cpanel::Api2::Paginate::get_state();
        if ( $page_state->{'results_per_page'} ) {
            @OPTS{ 'startIndex', 'results' } = @{$page_state}{ 'start_result', 'results_per_page' };
            $OPTS{'startIndex'}-- if $OPTS{'startIndex'};

            # Tell API2 that the data is already paginated
            $is_paginated = $state_hr->{'paginated'} = 1;
        }
    }

    my $data = Cpanel::AdminBin::adminfetchnocache( 'eximstats', '', 'SEARCH', undef, \%OPTS );

    if ( !$data->[0] ) {
        $Cpanel::CPERROR{'emailtrack'}        = $data->[1] || 'eximstatsadmin returned invalid data';
        $Cpanel::CPVAR{'api2_paginate_total'} = 0;
        return 0;
    }

    if ($is_paginated) {
        $Cpanel::CPVAR{'api2_paginate_total'} = $data->[3];
    }

    $state_hr->{'metadata'}{'overflowed'} = $data->[4] || 0;

    return $data->[2];
}

sub api2_trace {
    my %OPTS = @_;

    my $addy = $OPTS{'address'};

    if ( !Cpanel::Validate::EmailRFC::is_valid_remote($addy) ) {
        $Cpanel::CPERROR{'emailtrack'} = "Invalid email address: $addy";
        return;
    }

    my $result = Cpanel::AdminBin::adminfetchnocache( 'mailroute', '', 'TRACE', 'storable', $addy, $ENV{REMOTE_USER} );

    return if 'HASH' ne ref $result;

    return [$result];
}

sub api2 {
    my ($func) = @_;
    return { worker_node_type => 'Mail', %{ $API{$func} } } if $API{$func};
    return;
}

1;
