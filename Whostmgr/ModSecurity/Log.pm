
# cpanel - Whostmgr/ModSecurity/Log.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::ModSecurity::Log;

use strict;
use Try::Tiny;
use Cpanel::ModSecurity::DB ();
use Cpanel::Locale 'lh';
use Cpanel::Logger                            ();
use Whostmgr::ModSecurity                     ();
use Whostmgr::ModSecurity::Vendor             ();
use Whostmgr::API::1::Data::MysqlQueryBuilder ();

=head1 NAME

Whostmgr::ModSecurity::Log

=head1 DESCRIPTION

Module for extracting data from the database of mod_security hits log.

=head1 SUBROUTINES

=head2 get_log()

Consult the MySQL database containing mod_security hits gathered from the
Apache log and return the hits in a structure suitable for sending back
to the browser via xml-api.

The password stored in /var/cpanel/modsec_db_pass is used for the database
connection.

  Arguments

This function accepts a hash ref containing the API arguments (usually
called $api_args in other API-related code) related to sorting and
pagination.

  Returns

1. An array ref of log events following the structure described in the documentation for
   modsec_get_log in Whostmgr/API/1/ModSecurity.pm.

2. The total row count without any filtering.

=cut

sub get_log {
    my %args = @_;

    my $logger = Cpanel::Logger->new();

    my ( $metadata, $api_args ) = @args{qw(metadata api_args)};

    my $dbh = get_dbh();

    my $query_builder = Whostmgr::API::1::Data::MysqlQueryBuilder->new(
        table    => 'hits',
        columns  => [ Cpanel::ModSecurity::DB::columns() ],
        metadata => $metadata,
        api_args => $api_args,
    );
    my $query       = $query_builder->result_query;
    my $count_query = $query_builder->count_query;
    $query_builder->mark_processing_done();    # amends $api_args to prevent xml-api post-processing

    my $rows         = $dbh->selectall_arrayref($query);
    my $count_result = $dbh->selectall_arrayref($count_query);
    my $row_count    = $count_result->[0][0];

    my @columns = Cpanel::ModSecurity::DB::columns();

    my %exists;                                # cache for file_exists
    my %vendors;                               # cache for reportable

    my @result = map {
        my $row_from_table = $_;
        my %row_info       = map { $columns[$_] => $row_from_table->[$_] } 0 .. $#columns;

        #
        # Annotate the row info with whether the config file still exists on disk. Keep an in-memory
        # cache (above) of whether each file we care about exists so only one stat has to be done per
        # file.
        #
        if ( !defined $exists{ $row_info{meta_file} } ) {
            $exists{ $row_info{meta_file} } = -f $row_info{meta_file} ? 1 : 0;
        }
        $row_info{file_exists} = $exists{ $row_info{meta_file} };

        #
        # Annotate the row info with whether the rule is reportable (based on whether the vendor,
        # if any, has a report_url set). Keep an in-memory cache (above) of the vendors whose rules
        # produced hits so they don't have to be instantiated for each row.
        #
        $row_info{reportable} = 0;
        my $config = Whostmgr::ModSecurity::to_relative( $row_info{meta_file} );
        if ($config) {
            my $vendor_id = Whostmgr::ModSecurity::extract_vendor_id_from_config_name($config);
            if ($vendor_id) {

                try {
                    $vendors{$vendor_id} ||= Whostmgr::ModSecurity::Vendor->load( vendor_id => $vendor_id );
                }
                catch {
                    # The vendor not being installed is not an error we care about. That can be ignored.
                    # However, anything else that prevents us from determining whether the rule is
                    # reportable should be logged.
                    unless ( 'Cpanel::Exception::ModSecurity::NoSuchVendor' eq ref $_ ) {
                        $logger->warn($_);
                    }
                    $vendors{$vendor_id} ||= 1;    # put a dummy value here to prevent retrying the failed vendor load
                };

                $row_info{reportable} = 1
                  if ( ref $vendors{$vendor_id} && $vendors{$vendor_id}->report_url ) ? 1 : 0;
            }
        }

        \%row_info;
    } @$rows;

    return \@result, $row_count;
}

*get_dbh = \&Cpanel::ModSecurity::DB::get_dbh;

sub _extract_rule_id {
    my ($mod_security_message) = @_;
    if ( my ($id) = $mod_security_message =~ m{\[id "([0-9]+)"\]} ) {
        return $id;
    }
    return '';
}

1;
