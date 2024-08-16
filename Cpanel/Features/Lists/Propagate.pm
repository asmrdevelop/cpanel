package Cpanel::Features::Lists::Propagate;

# cpanel - Cpanel/Features/Lists/Propagate.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Features::Lists::Propagate

=head1 SYNOPSIS

    my ($do_cr, $undo_cr) = Cpanel::Features::Lists::Propagate::get_do_and_undo( $api_obj, 'mylist' );

    # 1st returned coderef does the propagation.
    $do_cr->();

    # The 2nd coderef is an undo. This is useful if this propagation is part of
    # a sequence of other events:
    #
    eval { die 'oh no!'; 1 } or do {
        _handle_error_however($@);

        $undo_cr->();
    };

=head1 DESCRIPTION

This module encapsulates logic to synchronize feature lists from the
local server to a remote.

=cut

#----------------------------------------------------------------------

use Cpanel::Context        ();
use Cpanel::Encoder::Tiny  ();
use Cpanel::Features::Load ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 ($do_cr, $undo_cr) = get_do_and_undo( $WHM_API_OBJ, $FEATURELIST_NAME )

Returns a pair of coderefs suitable for inclusion into a
L<Cpanel::CommandQueue> instance:

=over

=item * The first uses $WHM_API_OBJ (an instance of L<Cpanel::RemoteAPI::WHM>
to ensure that the remote cPanel & WHM server has a feature list named
$FEATURELIST_NAME with the same options as the local one.

=item * The second will undo the action of the first.

=back

=cut

sub get_do_and_undo ( $api_obj, $featurelist_name ) {
    Cpanel::Context::must_be_list();

    my $featurelist_name_html = Cpanel::Encoder::Tiny::safe_html_encode_str($featurelist_name);

    my $status_quo_hr = Cpanel::Features::Load::load_featurelist($featurelist_name_html);
    if ( !$status_quo_hr ) {
        die "No feature “$featurelist_name” exists!";
    }

    my $remote_featurelists_ar = $api_obj->request_whmapi1_or_die('get_featurelists')->get_data();

    my $exists_yn = grep { $_ eq $featurelist_name } @$remote_featurelists_ar;

    my $remote_status_quo_hr;

    if ($exists_yn) {
        my $features_ar = $api_obj->request_whmapi1_or_die(
            'get_featurelist_data',
            { featurelist => $featurelist_name },
        )->get_data()->{'features'};

        $remote_status_quo_hr = {};

        for my $feature_hr (@$features_ar) {
            $remote_status_quo_hr->{ $feature_hr->{'id'} } = !$feature_hr->{'is_disabled'} || 0;
        }
    }

    my $api_func = $exists_yn ? 'update_featurelist' : 'create_featurelist';

    my %sync_payload = (
        featurelist => $featurelist_name,
        %$status_quo_hr,
    );

    my $did;

    my $todo_cr = sub {
        $api_obj->request_whmapi1_or_die( $api_func, \%sync_payload );
        $did = 1;

        return;
    };

    my $undo_cr = sub {
        die sprintf '%s: Undo called without do!', __PACKAGE__ if !$did;

        if ($exists_yn) {
            $api_obj->request_whmapi1_or_die(
                'update_featurelist',
                {
                    featurelist => $featurelist_name,
                    %$remote_status_quo_hr,
                },
            );
        }
        else {
            $api_obj->request_whmapi1_or_die(
                'delete_featurelist',
                { featurelist => $featurelist_name },
            );
        }

        return;
    };

    return ( $todo_cr, $undo_cr );
}

1;
