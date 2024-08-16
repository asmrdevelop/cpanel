package Whostmgr::Transfers::Systems::WebCalls;

# cpanel - Whostmgr/Transfers/Systems/WebCalls.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Transfers::Systems::WebCalls

=head1 SYNOPSIS

N/A

=head1 DESCRIPTION

This module exists to be called from the account restore system.
It should not be invoked directly except from that framework.

It restores the user’s custom WebCalls configuration parameters
from the account archive. Its restricted and unrestricted modes
are identical.

=head1 METHODS

=cut

use Cpanel::Imports;

use Cpanel::JSON                       ();
use Cpanel::LoadFile                   ();
use Cpanel::LoadModule                 ();
use Cpanel::PromiseUtils               ();
use Cpanel::Regex                      ();    ## PPI NO PARSE - mis-parse
use Cpanel::WebCalls::Constants        ();    ## PPI NO PARSE - mis-parse
use Cpanel::WebCalls::Datastore::Write ();
use Cpanel::WebCalls::ID               ();
use Cpanel::WebCalls::Type::DynamicDNS ();

use parent qw(
  Whostmgr::Transfers::Systems
);

use constant {
    get_restricted_available => 1,
};

=head2 I<OBJ>->get_summary()

POD for cplint. Don’t call this directly.

=cut

sub get_summary ($self) {
    return [ $self->_locale()->maketext('This module restores the account’s [asis,web call] data.') ];
}

=head2 I<OBJ>->unrestricted_restore()

POD for cplint. Don’t call this directly.

=cut

sub unrestricted_restore ($self) {

    my $username = $self->newuser();

    my $extractdir = $self->extractdir();

    my $file = "$extractdir/webcalls.json";

    my $json = Cpanel::LoadFile::load_if_exists($file);

    if ($json) {
        my $wcdata_hr = Cpanel::JSON::Load($json);

        my $writer = Cpanel::PromiseUtils::wait_anyevent(
            Cpanel::WebCalls::Datastore::Write->new_p( timeout => 30 ),
        )->get();

        my @imports;

        for my $id ( keys %$wcdata_hr ) {
            if ( !Cpanel::WebCalls::ID::is_valid($id) ) {
                $self->warn("Invalid webcall ID: $id");
                next;
            }

            my $item = $wcdata_hr->{$id};

            next if !$self->_validate_dates($item);

            my $type                      = $item->{'type'};
            my $normalize_and_validate_fn = "_normalize_and_validate_$type";

            if ( !__PACKAGE__->can($normalize_and_validate_fn) ) {
                $self->warn("Unknown webcall type: $item->{'type'}");
                next;
            }

            my $entry_class = Cpanel::LoadModule::load_perl_module(
                "Cpanel::WebCalls::Entry::$type",
            );

            $entry_class->adopt($item);

            my $data_hr = $self->$normalize_and_validate_fn($item);

            next if !$data_hr;

            my %safe_item = (
                ( map { $_ => $item->$_() } qw(created_time last_update_time) ),
                last_run_times => [ $item->last_run_times() ],
                data           => $data_hr,
            );

            push @imports, [ $type, $id, \%safe_item ];
        }

        $writer->import_for_user( $username, \@imports );
    }

    return 1;
}

*restricted_restore = \&unrestricted_restore;

sub _normalize_and_validate_DynamicDNS ( $self, $item ) {
    my $domain = $item->domain();

    my %data = map { $_ => $item->$_() } qw( domain description );

    Cpanel::WebCalls::Type::DynamicDNS->normalize_entry_data( $self->newuser(), \%data );

    my $err = Cpanel::WebCalls::Type::DynamicDNS->why_entry_data_invalid( $self->newuser(), \%data );

    if ($err) {
        my $username = $self->newuser();
        $self->warn( locale()->maketext( 'The system cannot restore “[_1]” as a dynamic [asis,DNS] domain for “[_2]”. ([_3])', $domain, $username, $err ) );

        return undef;
    }

    return \%data;
}

sub _validate_dates ( $self, $item_hr ) {
    my $last_run_times_ar = $item_hr->{'last_run_times'};

    my $is_valid = 1;

    if ( @$last_run_times_ar > Cpanel::WebCalls::Constants::RATE_LIMIT_ALLOWANCE ) {
        $is_valid = 0;

        my $how_many = @$last_run_times_ar;

        $self->warn("run times list is too long ($how_many)");
    }
    else {
        my @dates = (
            $item_hr->{'created_time'},
            $item_hr->{'last_update_time'} || (),
            @{$last_run_times_ar},
        );

        my $re = qr<\A$Cpanel::Regex::regex{iso_z_time}\z>o;

        for my $d (@dates) {
            if ( $d !~ $re ) {
                $is_valid = 0;

                $self->warn("invalid time: $d");
            }
        }
    }

    return $is_valid;
}

1;
