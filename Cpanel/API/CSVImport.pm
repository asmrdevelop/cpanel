package Cpanel::API::CSVImport;

# cpanel - Cpanel/API/CSVImport.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel            ();
use Cpanel::API       ();
use Cpanel::Email     ();
use Cpanel::Exception ();
use Cpanel::Locale::Lazy 'lh';
use Cpanel::PipeHandler  ();
use Cpanel::SafeStorable ();

=head1 NAME

Cpanel::API::CSVImport

=head1 DESCRIPTION

UAPI functions related to the bulk import of email addresses and forwards.

=head1 METHODS

=head2 doimport

Imports email accounts from a previously-uploaded CSV file.

=cut

sub doimport {
    my ( $args, $result ) = @_;
    my $data;
    my $results;

    my ( $id, $type, $domain ) = $args->get_length_required( 'id', 'type', 'domain' );

    my $return_status = 1;

    if ( $id =~ m{/} ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” argument is invalid.', ['id'] );
    }

    if ( $type !~ m/^(?:fwd|email)\z/ ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” argument must be “[_2]” or “[_3]”.', [qw(type email fwd)] );
    }

    my $file = $Cpanel::homedir . '/tmp/cpcsvimport/' . $id . '.import';
    if ( not -e $file ) {
        die Cpanel::Exception::create( 'InvalidParameter', "Can’t find the “[_1]” file.", [$file] );
    }

    # Deal with very large imports.
    local $SIG{'PIPE'} = \&Cpanel::PipeHandler::pipeBGMgr;
    alarm(7200);

    my $importdata = Cpanel::SafeStorable::lock_retrieve($file);

    my $domhash          = { map { $_ => 1 } @Cpanel::DOMAINS };
    my $number_of_errors = 0;
    foreach my $row (@$importdata) {
        my %info;
        if ( $type eq 'fwd' ) {
            my ( $status, $msg ) = Cpanel::Email::addforward( $row->{'source'}, $row->{'target'}, $domain, 1, $domhash );
            if ( not $status ) {
                $return_status = 0;
                $number_of_errors++;
            }
            $info{status} = $status;
            $info{type}   = "fwd";
            $info{reason} = $msg;
            $info{email}  = $row->{'source'};
            $info{fwd}    = $row->{'target'};
        }
        else {
            my $add_pop_result = Cpanel::API::execute(
                'Email', 'add_pop',
                { email => $row->{'email'}, password => $row->{'password'}, quota => $row->{'quota'}, domain => $domain }
            );
            $info{status} = $add_pop_result->status();
            $info{type}   = 'email';
            if ( $add_pop_result->status() ) {
                $info{reason} = $add_pop_result->data();
            }
            else {
                $info{reason}  = join "\n", @{ $add_pop_result->errors() };
                $return_status = 0;
                $number_of_errors++;
            }
            $info{email} = $row->{'email'};
        }
        push @$results, \%info;
    }
    if ($number_of_errors) {
        $result->raw_error( lh()->maketext('The system encountered errors while importing accounts.') );
    }
    $data->{results} = $results;
    $result->data($data);
    return $return_status;
}

our %API = (
    doimport => { needs_feature => 'csvimport', allow_demo => 0 },
);

1;
