
# cpanel - Whostmgr/ModSecurity/Report.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::ModSecurity::Report;

use strict;

use Carp ();

use HTTP::Tiny   ();
use Cpanel::JSON ();
use Cpanel::Locale 'lh';
use Cpanel::ModSecurity::DB                   ();
use Whostmgr::API::1::Data::MysqlQueryBuilder ();
use Whostmgr::ModSecurity                     ();
use Whostmgr::ModSecurity::Chunk::Get         ();
use Whostmgr::ModSecurity::Vendor             ();

sub new {
    my ( $package, %args ) = @_;

    my $self = {};
    bless $self, $package;

    defined( $self->{row_ids} = delete $args{row_ids} ) or Carp::croak( _missing_attribute('row_ids') );
    defined( $self->{email}   = delete $args{email} )   or Carp::croak( _missing_attribute('email') );
    defined( $self->{type}    = delete $args{type} )    or Carp::croak( _missing_attribute('type') );
    defined( $self->{message} = delete $args{message} ) or Carp::croak( _missing_attribute('message') );

    if (%args) {
        Carp::croak( lh()->maketext( 'The system could not generate the report because it contained unexpected attributes: [list_and_quoted,_1]', [ keys %args ] ) );
    }

    return $self;
}

sub _build {
    my ($self) = @_;

    return $self->{_built_report} if $self->{_built_report};    # no need to rebuild the report if it's already been built

    #
    # Step 1: Look up the row from the table so we can learn the filename and rule id.
    #

    my $row_data       = $self->_row_data;
    my $first_row_data = $row_data->[0];

    my $file = $first_row_data->{meta_file};
    if ( !$file ) {
        die lh()->maketext('The system could not build the report. The row from the [asis,hits] table did not include the configuration file path.');
    }

    my $id = $first_row_data->{meta_id};
    if ( !$id ) {
        die lh()->maketext('The system could not build the report. The row from the [asis,hits] table did not include the rule ID.');
    }

    #
    # Step 2: Look up the rule itself so we can learn the vendor_id and the full text of the rule.
    #

    my $chunk = Whostmgr::ModSecurity::Chunk::Get::get_chunk( Whostmgr::ModSecurity::to_relative($file), $id );

    if ( !$chunk->vendor_id ) {
        die lh()->maketext('You cannot submit a report for a rule that you created.') . "\n";
    }

    my $rule_text = $chunk->text;

    #
    # Step 3: Look up the vendor so we can learn the report URL.
    #

    my $vendor = Whostmgr::ModSecurity::Vendor->load( vendor_id => $chunk->vendor_id );
    if ( !defined( $self->{report_url} = $vendor->report_url ) ) {
        die lh()->maketext('The vendor that provides this rule does not have a report [asis,API] available.') . "\n";
    }

    #
    # Step 4: Having stored the report URL for later, store the built report, and return it.
    #

    $self->{_built_report} = {
        hits      => $row_data,
        email     => $self->{email},
        type      => $self->{type},
        message   => $self->{message},
        rule_text => $rule_text,
    };

    return $self->{_built_report};
}

sub send {
    my ($self) = @_;
    my $built_report = $self->_build;
    return _http_post( url => $self->{report_url}, data => $built_report );
}

sub _http_post {
    my %args = @_;
    my $url  = $args{url}  || die( lh()->maketext('The system could not find the report URL.') . "\n" );
    my $data = $args{data} || die( lh()->maketext('The system could not find the report data.') . "\n" );

    unless ( $url && $data && $url =~ m{^https?://} ) {
        die lh()->maketext('Your request does not contain the required data or is not in a supported scheme.') . "\n";
    }

    my $json_data = Cpanel::JSON::Dump($data);

    my $http     = HTTP::Tiny->new( verify_SSL => 1 );
    my $response = $http->request( 'POST', $url, { content => $json_data, headers => { 'content-type' => 'application/json' } } );

    if ( !$response->{'success'} ) {
        my $error = "$response->{status} ($response->{reason})";
        $error .= ": $response->{content}" if ( $response->{status} && $response->{status} == 599 );
        die lh()->maketext( 'The system was unable to submit the request: [_1]', $error ) . "\n";
    }

    return 1;
}

sub get {
    my ($self) = @_;
    return $self->_build;
}

sub _row_data {
    my ($self) = @_;

    my $reporting_on_rule_id;

    my @rows;
    for my $row_id ( @{ $self->{row_ids} } ) {
        my $metadata = {};
        my $api_args = {
            filter => {
                enable => 1,
                a      => {
                    field => 'id',
                    type  => '==',
                    arg0  => $row_id,
                }
            }
        };
        my $query_builder = Whostmgr::API::1::Data::MysqlQueryBuilder->new(
            table    => 'hits',
            columns  => [ Cpanel::ModSecurity::DB::columns() ],
            metadata => $metadata,
            api_args => $api_args,
            sort_ip  => [qw(ip)],
        );
        my $query = $query_builder->result_query;

        my $dbh      = Cpanel::ModSecurity::DB::get_dbh();
        my $rows     = $dbh->selectall_arrayref($query);
        my $this_row = shift @$rows;
        my %row_data;
        for my $col_name ( Cpanel::ModSecurity::DB::columns() ) {
            my $col_value = shift @$this_row;
            $row_data{$col_name} = $col_value;
        }

        $row_data{id}      or die lh()->maketext( 'The system could not find the hits with the row ID “[_1]”.', $row_id ) . "\n";
        $row_data{meta_id} or die lh()->maketext('Some of the hits do not have known rule IDs.') . "\n";
        $reporting_on_rule_id ||= $row_data{meta_id};
        if ( $row_data{meta_id} != $reporting_on_rule_id ) {
            die lh()->maketext('Some of the rule IDs from these hits do not match the other rule IDs. Although you can report multiple hits at a time, they must all be about the same rule.') . "\n";
        }

        push @rows, \%row_data;
    }

    return \@rows;
}

sub _missing_attribute {
    my ($attr) = @_;
    return lh()->maketext( 'To create the report, you must provide the “[_1]” attribute.', $attr );
}

1;
